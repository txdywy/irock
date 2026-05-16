import Foundation
import IrockProtocols
import IrockTransport
import IrockTunnelCore
import Network

final class MacOSPlatformUDPDatagramClient: UDPDatagramClient, @unchecked Sendable {
    private static let queue = DispatchQueue(label: "dev.irock.macos-udp-datagram-client")
    private let responseWindowNanoseconds: UInt64
    private let lock = NSLock()
    private var connectionsByFlowKey: [FlowKey: NWConnection] = [:]

    init(responseWindowNanoseconds: UInt64 = 50_000_000) {
        self.responseWindowNanoseconds = responseWindowNanoseconds
    }

    func send(_ request: UDPDatagramClientRequest) async throws -> [UInt8]? {
        let connection = try connection(for: request)
        let exchange = MacOSPlatformUDPDatagramExchange(
            connection: connection,
            request: request,
            responseWindowNanoseconds: responseWindowNanoseconds
        )
        return try await withTaskCancellationHandler {
            try await exchange.send()
        } onCancel: {
            exchange.cancel()
        }
    }

    private func connection(for request: UDPDatagramClientRequest) throws -> NWConnection {
        lock.lock()
        if let connection = connectionsByFlowKey[request.flowKey] {
            lock.unlock()
            return connection
        }
        lock.unlock()

        let endpointHost = try host(for: request.destination)
        let port = port(for: request.destination)
        guard (1...65_535).contains(port), let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw TransportError.invalidConfiguration("invalid udp port")
        }

        let connection = NWConnection(host: endpointHost, port: endpointPort, using: .udp)
        connection.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else { return }
            self?.removeConnection(for: request.flowKey, connection: connection)
        }
        connection.start(queue: Self.queue)

        lock.lock()
        if let existing = connectionsByFlowKey[request.flowKey] {
            lock.unlock()
            connection.cancel()
            return existing
        }
        connectionsByFlowKey[request.flowKey] = connection
        lock.unlock()
        return connection
    }

    private func removeConnection(for flowKey: FlowKey, connection: NWConnection) {
        lock.lock()
        if connectionsByFlowKey[flowKey] === connection {
            connectionsByFlowKey.removeValue(forKey: flowKey)
        }
        lock.unlock()
    }

    private func host(for destination: ProxyDestination) throws -> NWEndpoint.Host {
        switch destination {
        case let .host(host, _), let .ipv4(host, _), let .ipv6(host, _):
            let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedHost.isEmpty else {
                throw TransportError.invalidConfiguration("missing udp host")
            }
            return NWEndpoint.Host(normalizedHost)
        }
    }

    private func port(for destination: ProxyDestination) -> Int {
        switch destination {
        case let .host(_, port), let .ipv4(_, port), let .ipv6(_, port):
            return port
        }
    }
}

private final class MacOSPlatformUDPDatagramExchange: @unchecked Sendable {
    private let connection: NWConnection
    private let request: UDPDatagramClientRequest
    private let responseWindowNanoseconds: UInt64
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[UInt8]?, Error>?
    private var terminalResult: Result<[UInt8]?, Error>?

    init(connection: NWConnection, request: UDPDatagramClientRequest, responseWindowNanoseconds: UInt64) {
        self.connection = connection
        self.request = request
        self.responseWindowNanoseconds = responseWindowNanoseconds
    }

    func send() async throws -> [UInt8]? {
        let responseWindowTask = Task { [weak self] in
            guard let self else { return }
            try await Task.sleep(nanoseconds: responseWindowNanoseconds)
            resume(with: .success(nil))
        }

        defer {
            responseWindowTask.cancel()
        }

        return try await withCheckedThrowingContinuation { continuation in
            guard install(continuation) else { return }
            connection.send(content: Data(request.payload), completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    resume(with: .failure(TransportError.tcpConnectFailed(error.localizedDescription)))
                    return
                }
                receiveResponse()
            })
        }
    }

    func cancel() {
        resume(with: .failure(CancellationError()))
    }

    private func install(_ continuation: CheckedContinuation<[UInt8]?, Error>) -> Bool {
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

    private func receiveResponse() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                resume(with: .failure(TransportError.tcpConnectFailed(error.localizedDescription)))
                return
            }
            guard let data, !data.isEmpty else {
                resume(with: .success(nil))
                return
            }
            resume(with: .success(Array(data)))
        }
    }

    private func resume(with result: Result<[UInt8]?, Error>) {
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

    private func complete(_ continuation: CheckedContinuation<[UInt8]?, Error>, with result: Result<[UInt8]?, Error>) {
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
