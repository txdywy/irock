import Foundation
import IrockCore
import IrockTransport
import Network
import Security

final class MacOSTLSByteStream: TransportByteStream, @unchecked Sendable {
    private let connection: NWConnection
    private let initialPayload: Data?
    private let queue = DispatchQueue(label: "dev.irock.macos-tls-byte-stream")

    init(host: String, port: Int, tls: TLSOptions, initialPayload: Data?) throws {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: try NWEndpoint.Port(validatingTCPPort: port))
        let options = NWProtocolTLS.Options()
        if let serverName = tls.serverName?.trimmingCharacters(in: .whitespacesAndNewlines), !serverName.isEmpty {
            serverName.withCString { sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, $0) }
        }
        for alpn in tls.alpn.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            alpn.withCString { sec_protocol_options_add_tls_application_protocol(options.securityProtocolOptions, $0) }
        }
        if tls.allowInsecure {
            sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, complete in
                complete(true)
            }, queue)
        }
        if tls.fingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            throw TransportError.invalidConfiguration("tls certificate pinning is unsupported in macOS local proxy")
        }
        if tls.reality != nil {
            throw TransportError.invalidConfiguration("reality tls is unsupported in Trojan local proxy")
        }
        let parameters = NWParameters(tls: options)
        self.connection = NWConnection(to: endpoint, using: parameters)
        self.initialPayload = initialPayload
    }

    func start() async throws {
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
                        if let initialPayload = self.initialPayload, !initialPayload.isEmpty {
                            self.connection.send(content: initialPayload, completion: .contentProcessed { error in
                                if let error {
                                    continuation.resume(throwing: TransportError.tcpConnectFailed(error.localizedDescription))
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
                        continuation.resume(throwing: TransportError.tlsHandshakeFailed(error.localizedDescription))
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
                    continuation.resume(throwing: TransportError.tcpConnectFailed(error.localizedDescription))
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
                    continuation.resume(throwing: TransportError.tcpConnectFailed(error.localizedDescription))
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
    init(validatingTCPPort port: Int) throws {
        guard (1...65_535).contains(port), let value = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw TransportError.invalidConfiguration("invalid tcp port")
        }
        self = value
    }
}
