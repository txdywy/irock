import Foundation
import IrockCore
import IrockTransport
import Network

struct MacOSPlatformTCPByteStreamDialer: TransportStreamAdapter {
    let supportedTransport: TransportType = .tcp

    func openStream(request: TransportRequest) async throws -> any TransportByteStream {
        guard request.transport == .tcp else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        guard request.tls?.enabled == true, let tls = request.tls else {
            throw TransportError.invalidConfiguration("missing tls options")
        }
        let stream = try MacOSTLSByteStream(host: request.host, port: request.port, tls: tls, initialPayload: nil)
        try await stream.start()
        return stream
    }
}

struct MacOSPlatformTCPDialer: TCPDialer {
    private static let queue = DispatchQueue(label: "dev.irock.macos-tcp-dialer")
    private let timeoutNanoseconds: UInt64

    init(timeoutNanoseconds: UInt64 = 5_000_000_000) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func open(host: String, port: Int, initialPayload: Data?) async throws -> TCPDialResult {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            throw TransportError.invalidConfiguration("missing tcp host")
        }
        guard (1...65_535).contains(port), let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw TransportError.invalidConfiguration("invalid tcp port")
        }

        let connection = NWConnection(host: NWEndpoint.Host(normalizedHost), port: endpointPort, using: .tcp)
        let waiter = MacOSPlatformTCPDialWaiter(
            connection: connection,
            host: normalizedHost,
            port: port,
            timeoutNanoseconds: timeoutNanoseconds,
            initialPayload: initialPayload
        )

        return try await withTaskCancellationHandler {
            try await waiter.open(on: Self.queue)
        } onCancel: {
            waiter.cancel()
        }
    }
}

private final class MacOSPlatformTCPDialWaiter: @unchecked Sendable {
    private let connection: NWConnection
    private let host: String
    private let port: Int
    private let timeoutNanoseconds: UInt64
    private let initialPayload: Data?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TCPDialResult, Error>?
    private var terminalResult: Result<TCPDialResult, Error>?

    init(connection: NWConnection, host: String, port: Int, timeoutNanoseconds: UInt64, initialPayload: Data?) {
        self.connection = connection
        self.host = host
        self.port = port
        self.timeoutNanoseconds = timeoutNanoseconds
        self.initialPayload = initialPayload
    }

    func open(on queue: DispatchQueue) async throws -> TCPDialResult {
        let timeoutTask = Task { [weak self] in
            guard let self else { return }
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            resume(with: .failure(TransportError.tcpConnectFailed("tcp dial timed out")))
        }

        defer {
            timeoutTask.cancel()
            connection.cancel()
        }

        return try await withCheckedThrowingContinuation { continuation in
            guard install(continuation) else { return }
            connection.stateUpdateHandler = { [weak self] state in
                self?.handle(state)
            }
            connection.start(queue: queue)
        }
    }

    func cancel() {
        resume(with: .failure(CancellationError()))
        connection.cancel()
    }

    private func install(_ continuation: CheckedContinuation<TCPDialResult, Error>) -> Bool {
        lock.lock()
        if let terminalResult {
            lock.unlock()
            complete(continuation, with: terminalResult)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            sendInitialPayloadIfNeeded()
        case .failed(let error):
            resume(with: .failure(TransportError.tcpConnectFailed(error.localizedDescription)))
        case .cancelled:
            resume(with: .failure(CancellationError()))
        case .setup, .preparing, .waiting:
            break
        @unknown default:
            resume(with: .failure(TransportError.tcpConnectFailed("unknown tcp connection state")))
        }
    }

    private func sendInitialPayloadIfNeeded() {
        guard let initialPayload, !initialPayload.isEmpty else {
            resume(with: .success(TCPDialResult(host: host, port: port)))
            return
        }

        connection.send(content: initialPayload, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                resume(with: .failure(TransportError.tcpConnectFailed(error.localizedDescription)))
                return
            }
            resume(with: .success(TCPDialResult(host: host, port: port)))
        })
    }

    private func resume(with result: Result<TCPDialResult, Error>) {
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        terminalResult = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        if let continuation {
            complete(continuation, with: result)
        }
    }

    private func complete(_ continuation: CheckedContinuation<TCPDialResult, Error>, with result: Result<TCPDialResult, Error>) {
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
