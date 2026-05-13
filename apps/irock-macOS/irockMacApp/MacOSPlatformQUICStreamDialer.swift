import Foundation
import IrockCore
import IrockTransport
import Network
import Security

struct MacOSPlatformQUICStreamDialer: QUICStreamDialer {
    func openBidirectionalStream(host: String, port: Int, tls: TLSOptions?, metadata: [String: String], initialPayload: Data?) async throws -> any TransportByteStream {
        try validateTLSOptions(tls)
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: try NWEndpoint.Port(validating: port))
        let options = NWProtocolQUIC.Options()
        options.direction = .bidirectional
        if let serverName = tls?.serverName?.trimmingCharacters(in: .whitespacesAndNewlines), !serverName.isEmpty {
            serverName.withCString { sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, $0) }
        }
        let alpnValues = metadata["quicALPN"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        for alpn in alpnValues {
            alpn.withCString { sec_protocol_options_add_tls_application_protocol(options.securityProtocolOptions, $0) }
        }
        let parameters = NWParameters(quic: options)
        let connection = NWConnection(to: endpoint, using: parameters)
        let stream = NetworkQUICByteStream(connection: connection)
        try await stream.start(initialPayload: initialPayload)
        return stream
    }

    private func validateTLSOptions(_ tls: TLSOptions?) throws {
        guard let tls else { return }
        if tls.allowInsecure {
            throw TransportError.invalidConfiguration("quic allowInsecure is unsupported")
        }
        if tls.fingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            throw TransportError.invalidConfiguration("quic certificate pinning is unsupported")
        }
        if tls.reality != nil {
            throw TransportError.invalidConfiguration("quic reality tls is unsupported")
        }
    }
}

private final class NetworkQUICByteStream: TransportByteStream, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "dev.irock.macos-quic-stream")

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(initialPayload: Data?) async throws {
        final class ResumeGate: @unchecked Sendable {
            private let lock = NSLock()
            private var didResume = false

            func runOnce(_ body: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                body()
            }
        }

        let resumeGate = ResumeGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeGate.runOnce {
                        if let initialPayload, !initialPayload.isEmpty {
                            self.connection.send(content: initialPayload, completion: .contentProcessed { error in
                                if let error {
                                    continuation.resume(throwing: TransportError.quicHandshakeFailed(error.localizedDescription))
                                } else {
                                    continuation.resume()
                                }
                            })
                        } else {
                            continuation.resume()
                        }
                    }
                case let .failed(error):
                    resumeGate.runOnce {
                        continuation.resume(throwing: TransportError.quicHandshakeFailed(error.localizedDescription))
                    }
                case .cancelled:
                    resumeGate.runOnce {
                        continuation.resume(throwing: TransportError.remoteClosed)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func read(maxLength: Int) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: TransportError.quicHandshakeFailed(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: TransportError.quicHandshakeFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func closeWrite() async {
        connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in })
    }

    func close() async {
        connection.cancel()
    }
}

private extension NWEndpoint.Port {
    init(validating port: Int) throws {
        guard let value = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw TransportError.invalidConfiguration("invalid quic port")
        }
        self = value
    }
}
