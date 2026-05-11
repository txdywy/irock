import XCTest
import IrockCore
@testable import IrockTransport

final class IrockTransportTests: XCTestCase {
    func testTransportRequestStoresEndpointTLSMetadataAndInitialPayload() {
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let payload = Data([0xde, 0xad, 0xbe, 0xef])
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc, tls: tls, metadata: ["source": "unit-test"], initialPayload: payload)

        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 443)
        XCTAssertEqual(request.transport, .grpc)
        XCTAssertEqual(request.tls, tls)
        XCTAssertEqual(request.metadata, ["source": "unit-test"])
        XCTAssertEqual(request.initialPayload, payload)
    }

    func testTransportRequestDefaultsTLSAndMetadata() {
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp)

        XCTAssertNil(request.tls)
        XCTAssertEqual(request.metadata, [:])
        XCTAssertNil(request.initialPayload)
    }

    func testEstablishedTransportConnectionStoresEndpointAndKind() {
        let connection = EstablishedTransportConnection(host: "example.com", port: 443, transport: .tcp)

        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
    }

    func testUnsupportedTransportAdapterFailsWithRequestedTransport() async {
        let adapter = UnsupportedTransportAdapter(transport: .quic)
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.quic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNoopTransportAdapterRemainsUnsupportedAlias() async {
        let adapter = NoopTransportAdapter()
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportErrorDescriptionsAreStableAndCredentialSafe() {
        let errors: [(TransportError, String)] = [
            (.invalidConfiguration("secret missing server host"), "Invalid configuration"),
            (.dnsFailed("secret.example.com"), "DNS failed"),
            (.tcpConnectFailed("password refused"), "TCP connect failed"),
            (.tlsHandshakeFailed("token rejected"), "TLS handshake failed"),
            (.unsupportedTransport(.quic), "Unsupported transport: quic"),
            (.quicHandshakeFailed("secret timeout"), "QUIC handshake failed"),
            (.remoteClosed, "Remote closed"),
            (.timeout, "Timeout")
        ]

        for (error, description) in errors {
            XCTAssertEqual(error.description, description)
            XCTAssertFalse(error.description.contains("secret"))
            XCTAssertFalse(error.description.contains("password"))
            XCTAssertFalse(error.description.contains("token"))
        }
    }

    func testTransportAdapterRegistryReturnsRegisteredAdapter() async throws {
        let adapter = RecordingTransportAdapter(transport: .grpc)
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .grpc)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .grpc)
        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .grpc)
    }

    func testTransportAdapterRegistryFallsBackToUnsupportedAdapter() async {
        let registry = TransportAdapterRegistry(adapters: [])
        let selected = registry.adapter(for: .quic)
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        do {
            _ = try await selected.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.quic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportAdapterRegistryUsesLastRegisteredAdapterForDuplicates() async throws {
        let first = RecordingTransportAdapter(transport: .tcp, connectionHost: "first.example.com")
        let second = RecordingTransportAdapter(transport: .tcp, connectionHost: "second.example.com")
        let registry = TransportAdapterRegistry(adapters: [first, second])
        let selected = registry.adapter(for: .tcp)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(connection.host, "second.example.com")
    }

    func testTCPTransportAdapterRejectsNonTCPBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(dialer.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTransportAdapterRejectsEmptyHostBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let request = TransportRequest(host: "   ", port: 443, transport: .tcp)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as TransportError {
            XCTAssertEqual(error, .invalidConfiguration("missing tcp host"))
            XCTAssertEqual(dialer.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTransportAdapterRejectsInvalidPortBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)

        for port in [0, 65_536] {
            let request = TransportRequest(host: "example.com", port: port, transport: .tcp)

            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected invalid configuration")
            } catch let error as TransportError {
                XCTAssertEqual(error, .invalidConfiguration("invalid tcp port"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(dialer.requests, [])
    }

    func testTCPTransportAdapterRejectsTLSBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.tcp))
            XCTAssertEqual(dialer.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTransportAdapterReportsSupportedTransport() {
        let adapter = TCPTransportAdapter(dialer: RecordingTCPDialer())

        XCTAssertEqual(adapter.supportedTransport, .tcp)
    }

    func testTCPTransportAdapterDialsHostAndPortAndReturnsConnection() async throws {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let payload = Data([0xca, 0xfe])
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, initialPayload: payload)

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(dialer.requests, [TCPDialRequest(host: "example.com", port: 443, initialPayload: payload)])
    }

    func testTCPTransportAdapterPropagatesDialerTransportError() async {
        let adapter = TCPTransportAdapter(dialer: FailingTCPDialer(error: .tcpConnectFailed("connection refused")))
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected dialer failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .tcpConnectFailed("connection refused"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportAdapterRegistryCanSelectTCPTransportAdapter() async throws {
        let adapter = TCPTransportAdapter(dialer: RecordingTCPDialer())
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .tcp)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .tcp)
        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
    }

    func testTLSTransportAdapterReportsTCPTransport() {
        let adapter = TLSTransportAdapter(underlying: RecordingTransportAdapter(transport: .tcp))

        XCTAssertEqual(adapter.supportedTransport, .tcp)
    }

    func testTLSTransportAdapterStripsTLSAndReturnsUnderlyingConnection() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp, connectionHost: "connected.example.com")
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: nil)
        let request = TransportRequest(host: " example.com ", port: 443, transport: .tcp, tls: tls, metadata: ["source": "unit-test"])

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "connected.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(underlying.requests, [TransportAdapterRequest(host: "example.com", port: 443, transport: .tcp, tls: nil, metadata: ["source": "unit-test"])])
    }

    func testTLSTransportAdapterRejectsNonTCPBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .grpc)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(underlying.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTLSTransportAdapterRejectsMissingOrDisabledTLSBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let disabled = TLSOptions.disabled
        let requests = [
            TransportRequest(host: "example.com", port: 443, transport: .tcp),
            TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: disabled)
        ]

        for request in requests {
            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected invalid configuration")
            } catch let error as TransportError {
                XCTAssertEqual(error, .invalidConfiguration("missing tls options"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(underlying.requests, [])
    }

    func testTLSTransportAdapterRejectsEmptyHostBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "   ", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as TransportError {
            XCTAssertEqual(error, .invalidConfiguration("missing tls host"))
            XCTAssertEqual(underlying.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTLSTransportAdapterRejectsInvalidPortBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)

        for port in [0, 65_536] {
            let request = TransportRequest(host: "example.com", port: port, transport: .tcp, tls: tls)

            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected invalid configuration")
            } catch let error as TransportError {
                XCTAssertEqual(error, .invalidConfiguration("invalid tls port"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(underlying.requests, [])
    }

    func testTLSTransportAdapterRejectsEmptyServerNameBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "   ", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as TransportError {
            XCTAssertEqual(error, .invalidConfiguration("invalid tls server name"))
            XCTAssertEqual(underlying.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTLSTransportAdapterRejectsRealityBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let reality = RealityOptions(publicKey: "public", shortID: nil, spiderX: nil)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: reality)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.tcp))
            XCTAssertEqual(underlying.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRealityTransportAdapterOpensUnderlyingTCPWithCredentialSafeMetadataAndPayload() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp, connectionHost: "connected.example.com")
        let adapter = RealityTransportAdapter(underlying: underlying)
        let payload = Data("vless-open".utf8)
        let reality = RealityOptions(publicKey: "reality-public-key", shortID: "abc123", spiderX: "/")
        let tls = TLSOptions(enabled: true, serverName: " reality.example.com ", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: reality)
        let request = TransportRequest(host: " example.com ", port: 443, transport: .tcp, tls: tls, metadata: ["proxyProtocol": "vless"], initialPayload: payload)

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "connected.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(underlying.requests.count, 1)
        XCTAssertEqual(underlying.requests.first?.host, "example.com")
        XCTAssertEqual(underlying.requests.first?.port, 443)
        XCTAssertEqual(underlying.requests.first?.transport, .tcp)
        XCTAssertNil(underlying.requests.first?.tls)
        XCTAssertEqual(underlying.requests.first?.metadata["proxyProtocol"], "vless")
        XCTAssertEqual(underlying.requests.first?.metadata["realityServerName"], "reality.example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["realityPublicKeyPresent"], "true")
        XCTAssertEqual(underlying.requests.first?.metadata["realityShortIDPresent"], "true")
        XCTAssertEqual(underlying.requests.first?.metadata["realitySpiderX"], "/")
        XCTAssertEqual(underlying.requests.first?.metadata["realityFingerprint"], "chrome")
        XCTAssertEqual(underlying.requests.first?.metadata["realityALPN"], "h2")
        let opened = underlying.requests.first?.initialPayload ?? Data()
        XCTAssertEqual(String(data: opened, encoding: .utf8), "reality-foundation:reality.example.com:public-key-present:true:/\nvless-open")
        XCTAssertFalse(opened.contains(Data("reality-public-key".utf8)))
        XCTAssertFalse(opened.contains(Data("abc123".utf8)))
    }

    func testRealityTransportAdapterRejectsInvalidConfigurationBeforeOpeningUnderlying() async {
        let reality = RealityOptions(publicKey: "public", shortID: nil, spiderX: nil)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: reality)
        let cases: [(TransportRequest, TransportError)] = [
            (TransportRequest(host: "example.com", port: 443, transport: .grpc, tls: tls), .unsupportedTransport(.grpc)),
            (TransportRequest(host: "   ", port: 443, transport: .tcp, tls: tls), .invalidConfiguration("missing reality host")),
            (TransportRequest(host: "example.com", port: 0, transport: .tcp, tls: tls), .invalidConfiguration("invalid reality port")),
            (TransportRequest(host: "example.com", port: 443, transport: .tcp), .invalidConfiguration("missing reality tls options")),
            (TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: .disabled), .invalidConfiguration("missing reality tls options")),
            (TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: TLSOptions(enabled: true, serverName: "   ", allowInsecure: false, alpn: [], fingerprint: nil, reality: reality)), .invalidConfiguration("invalid reality server name")),
            (TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: RealityOptions(publicKey: "   ", shortID: nil, spiderX: nil))), .invalidConfiguration("invalid reality public key")),
            (TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: RealityOptions(publicKey: "public", shortID: "   ", spiderX: nil))), .invalidConfiguration("invalid reality short id")),
            (TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: RealityOptions(publicKey: "public", shortID: nil, spiderX: "   "))), .invalidConfiguration("invalid reality spider x"))
        ]

        for (request, expectedError) in cases {
            let underlying = RecordingTransportAdapter(transport: .tcp)
            let adapter = RealityTransportAdapter(underlying: underlying)
            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected Reality validation failure")
            } catch let error as TransportError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(underlying.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testWebSocketTransportAdapterOpensUnderlyingTCPWithMetadataAndPayload() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp, connectionHost: "connected.example.com")
        let adapter = WebSocketTransportAdapter(underlying: underlying)
        let payload = Data("protocol-open".utf8)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(
            host: " example.com ",
            port: 443,
            transport: .webSocket,
            tls: tls,
            metadata: ["webSocketPath": "/proxy", "webSocketProtocol": "vmess"],
            initialPayload: payload
        )

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "connected.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .webSocket)
        XCTAssertEqual(underlying.requests.count, 1)
        XCTAssertEqual(underlying.requests.first?.host, "example.com")
        XCTAssertEqual(underlying.requests.first?.port, 443)
        XCTAssertEqual(underlying.requests.first?.transport, .tcp)
        XCTAssertEqual(underlying.requests.first?.tls, tls)
        XCTAssertEqual(underlying.requests.first?.metadata["webSocketHost"], "example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["webSocketPath"], "/proxy")
        XCTAssertEqual(underlying.requests.first?.metadata["webSocketProtocol"], "vmess")
        XCTAssertEqual(underlying.requests.first?.metadata["webSocketUpgrade"], "true")
        XCTAssertEqual(String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8), "websocket-foundation:example.com:/proxy:vmess\nprotocol-open")
    }

    func testWebSocketTransportAdapterDefaultsPathAndHostMetadata() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = WebSocketTransportAdapter(underlying: underlying)
        let request = TransportRequest(host: "example.com", port: 80, transport: .webSocket)

        _ = try await adapter.open(request: request)

        XCTAssertEqual(underlying.requests.first?.metadata["webSocketHost"], "example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["webSocketPath"], "/")
        XCTAssertNil(underlying.requests.first?.metadata["webSocketProtocol"])
        XCTAssertEqual(String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8), "websocket-foundation:example.com:/:\n")
    }

    func testWebSocketTransportAdapterRejectsInvalidConfigurationBeforeOpeningUnderlying() async {
        let cases: [(TransportRequest, TransportError)] = [
            (TransportRequest(host: "example.com", port: 443, transport: .tcp), .unsupportedTransport(.tcp)),
            (TransportRequest(host: "   ", port: 443, transport: .webSocket), .invalidConfiguration("missing websocket host")),
            (TransportRequest(host: "example.com", port: 0, transport: .webSocket), .invalidConfiguration("invalid websocket port")),
            (TransportRequest(host: "example.com", port: 443, transport: .webSocket, metadata: ["webSocketPath": "proxy"]), .invalidConfiguration("invalid websocket path")),
            (TransportRequest(host: "example.com", port: 443, transport: .webSocket, metadata: ["webSocketHost": "   "]), .invalidConfiguration("invalid websocket host header"))
        ]

        for (request, expectedError) in cases {
            let underlying = RecordingTransportAdapter(transport: .tcp)
            let adapter = WebSocketTransportAdapter(underlying: underlying)
            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected WebSocket validation failure")
            } catch let error as TransportError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(underlying.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testHTTP2TransportAdapterOpensUnderlyingTCPWithMetadataAndPayload() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp, connectionHost: "connected.example.com")
        let adapter = HTTP2TransportAdapter(underlying: underlying)
        let payload = Data("protocol-open".utf8)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let request = TransportRequest(
            host: " example.com ",
            port: 443,
            transport: .http2,
            tls: tls,
            metadata: ["http2Path": "/proxy", "http2Protocol": "vmess"],
            initialPayload: payload
        )

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "connected.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .http2)
        XCTAssertEqual(underlying.requests.count, 1)
        XCTAssertEqual(underlying.requests.first?.host, "example.com")
        XCTAssertEqual(underlying.requests.first?.port, 443)
        XCTAssertEqual(underlying.requests.first?.transport, .tcp)
        XCTAssertEqual(underlying.requests.first?.tls, tls)
        XCTAssertEqual(underlying.requests.first?.metadata["http2Authority"], "example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["http2Path"], "/proxy")
        XCTAssertEqual(underlying.requests.first?.metadata["http2Protocol"], "vmess")
        XCTAssertEqual(underlying.requests.first?.metadata["http2Upgrade"], "true")
        XCTAssertEqual(String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8), "http2-foundation:example.com:/proxy:vmess\nprotocol-open")
    }

    func testHTTP2TransportAdapterDefaultsPathAndAuthorityMetadata() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = HTTP2TransportAdapter(underlying: underlying)
        let request = TransportRequest(host: "example.com", port: 80, transport: .http2)

        _ = try await adapter.open(request: request)

        XCTAssertEqual(underlying.requests.first?.metadata["http2Authority"], "example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["http2Path"], "/")
        XCTAssertNil(underlying.requests.first?.metadata["http2Protocol"])
        XCTAssertEqual(String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8), "http2-foundation:example.com:/:\n")
    }

    func testHTTP2TransportAdapterRejectsInvalidConfigurationBeforeOpeningUnderlying() async {
        let cases: [(TransportRequest, TransportError)] = [
            (TransportRequest(host: "example.com", port: 443, transport: .tcp), .unsupportedTransport(.tcp)),
            (TransportRequest(host: "   ", port: 443, transport: .http2), .invalidConfiguration("missing http2 host")),
            (TransportRequest(host: "example.com", port: 0, transport: .http2), .invalidConfiguration("invalid http2 port")),
            (TransportRequest(host: "example.com", port: 443, transport: .http2, metadata: ["http2Path": "proxy"]), .invalidConfiguration("invalid http2 path")),
            (TransportRequest(host: "example.com", port: 443, transport: .http2, metadata: ["http2Authority": "   "]), .invalidConfiguration("invalid http2 authority"))
        ]

        for (request, expectedError) in cases {
            let underlying = RecordingTransportAdapter(transport: .tcp)
            let adapter = HTTP2TransportAdapter(underlying: underlying)
            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected HTTP/2 validation failure")
            } catch let error as TransportError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(underlying.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testGRPCTransportAdapterOpensUnderlyingTCPWithMetadataAndPayload() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp, connectionHost: "connected.example.com")
        let adapter = GRPCTransportAdapter(underlying: underlying)
        let payload = Data("protocol-open".utf8)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let request = TransportRequest(
            host: " example.com ",
            port: 443,
            transport: .grpc,
            tls: tls,
            metadata: ["grpcService": "/TunnelService/Connect", "grpcProtocol": "vmess"],
            initialPayload: payload
        )

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "connected.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .grpc)
        XCTAssertEqual(underlying.requests.count, 1)
        XCTAssertEqual(underlying.requests.first?.host, "example.com")
        XCTAssertEqual(underlying.requests.first?.port, 443)
        XCTAssertEqual(underlying.requests.first?.transport, .tcp)
        XCTAssertEqual(underlying.requests.first?.tls, tls)
        XCTAssertEqual(underlying.requests.first?.metadata["grpcAuthority"], "example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["grpcService"], "/TunnelService/Connect")
        XCTAssertEqual(underlying.requests.first?.metadata["grpcProtocol"], "vmess")
        XCTAssertEqual(underlying.requests.first?.metadata["grpcUpgrade"], "true")
        XCTAssertEqual(String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8), "grpc-foundation:example.com:/TunnelService/Connect:vmess\nprotocol-open")
    }

    func testGRPCTransportAdapterDefaultsServiceAndAuthorityMetadata() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = GRPCTransportAdapter(underlying: underlying)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        _ = try await adapter.open(request: request)

        XCTAssertEqual(underlying.requests.first?.metadata["grpcAuthority"], "example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["grpcService"], "/TunService/Connect")
        XCTAssertNil(underlying.requests.first?.metadata["grpcProtocol"])
        XCTAssertEqual(String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8), "grpc-foundation:example.com:/TunService/Connect:\n")
    }

    func testGRPCTransportAdapterRejectsInvalidConfigurationBeforeOpeningUnderlying() async {
        let cases: [(TransportRequest, TransportError)] = [
            (TransportRequest(host: "example.com", port: 443, transport: .tcp), .unsupportedTransport(.tcp)),
            (TransportRequest(host: "   ", port: 443, transport: .grpc), .invalidConfiguration("missing grpc host")),
            (TransportRequest(host: "example.com", port: 0, transport: .grpc), .invalidConfiguration("invalid grpc port")),
            (TransportRequest(host: "example.com", port: 443, transport: .grpc, metadata: ["grpcService": "TunnelService/Connect"]), .invalidConfiguration("invalid grpc service")),
            (TransportRequest(host: "example.com", port: 443, transport: .grpc, metadata: ["grpcAuthority": "   "]), .invalidConfiguration("invalid grpc authority"))
        ]

        for (request, expectedError) in cases {
            let underlying = RecordingTransportAdapter(transport: .tcp)
            let adapter = GRPCTransportAdapter(underlying: underlying)
            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected gRPC validation failure")
            } catch let error as TransportError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(underlying.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testTLSTransportAdapterPropagatesUnderlyingTransportError() async {
        let adapter = TLSTransportAdapter(underlying: FailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("handshake failed")))
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected underlying failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .tlsHandshakeFailed("handshake failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportAdapterRegistryCanSelectTLSTransportAdapter() async throws {
        let adapter = TLSTransportAdapter(underlying: RecordingTransportAdapter(transport: .tcp))
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .tcp)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .tcp)
        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
    }

    func testTCPTLSTransportAdapterReportsTCPTransport() {
        let adapter = TCPTLSTransportAdapter(
            plain: RecordingTransportAdapter(transport: .tcp),
            tls: RecordingTransportAdapter(transport: .tcp)
        )

        XCTAssertEqual(adapter.supportedTransport, .tcp)
    }

    func testTCPTLSTransportAdapterRoutesPlainTCPToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp, connectionHost: "plain.example.com")
        let tls = RecordingTransportAdapter(transport: .tcp, connectionHost: "tls.example.com")
        let adapter = TCPTLSTransportAdapter(plain: plain, tls: tls)
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp, metadata: ["mode": "plain"])

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "plain.example.com")
        XCTAssertEqual(connection.port, 80)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(plain.requests, [TransportAdapterRequest(host: "example.com", port: 80, transport: .tcp, tls: nil, metadata: ["mode": "plain"])])
        XCTAssertEqual(tls.requests, [])
    }

    func testTCPTLSTransportAdapterRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp, connectionHost: "plain.example.com")
        let tlsChild = RecordingTransportAdapter(transport: .tcp, connectionHost: "tls.example.com")
        let adapter = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls, metadata: ["mode": "tls"])

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "tls.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests, [TransportAdapterRequest(host: "example.com", port: 443, transport: .tcp, tls: tls, metadata: ["mode": "tls"])])
    }

    func testTCPTLSTransportAdapterRoutesDisabledTLSToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp, connectionHost: "plain.example.com")
        let tlsChild = RecordingTransportAdapter(transport: .tcp, connectionHost: "tls.example.com")
        let adapter = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp, tls: .disabled)

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "plain.example.com")
        XCTAssertEqual(plain.requests, [TransportAdapterRequest(host: "example.com", port: 80, transport: .tcp, tls: .disabled, metadata: [:])])
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testTCPTLSTransportAdapterRejectsNonTCPBeforeOpeningChildren() async {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let adapter = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(plain.requests, [])
            XCTAssertEqual(tlsChild.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTLSTransportAdapterPropagatesPlainChildError() async {
        let adapter = TCPTLSTransportAdapter(
            plain: FailingTransportAdapter(transport: .tcp, error: .tcpConnectFailed("plain refused")),
            tls: RecordingTransportAdapter(transport: .tcp)
        )
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected plain child failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .tcpConnectFailed("plain refused"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTLSTransportAdapterPropagatesTLSChildError() async {
        let adapter = TCPTLSTransportAdapter(
            plain: RecordingTransportAdapter(transport: .tcp),
            tls: FailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("tls refused"))
        )
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected TLS child failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .tlsHandshakeFailed("tls refused"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportAdapterRegistryCanSelectTCPTLSTransportAdapter() async throws {
        let adapter = TCPTLSTransportAdapter(
            plain: RecordingTransportAdapter(transport: .tcp, connectionHost: "plain.example.com"),
            tls: RecordingTransportAdapter(transport: .tcp, connectionHost: "tls.example.com")
        )
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .tcp)
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .tcp)
        XCTAssertEqual(connection.host, "plain.example.com")
        XCTAssertEqual(connection.port, 80)
        XCTAssertEqual(connection.transport, .tcp)
    }
}

private struct TransportAdapterRequest: Equatable {
    let host: String
    let port: Int
    let transport: TransportType
    let tls: TLSOptions?
    let metadata: [String: String]
    let initialPayload: Data?

    init(host: String, port: Int, transport: TransportType, tls: TLSOptions?, metadata: [String: String], initialPayload: Data? = nil) {
        self.host = host
        self.port = port
        self.transport = transport
        self.tls = tls
        self.metadata = metadata
        self.initialPayload = initialPayload
    }
}

private final class RecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    let connectionHost: String
    private let lock = NSLock()
    private var storedRequests: [TransportAdapterRequest] = []

    init(transport: TransportType, connectionHost: String = "example.com") {
        self.supportedTransport = transport
        self.connectionHost = connectionHost
    }

    var requests: [TransportAdapterRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        record(request)
        return EstablishedTransportConnection(host: connectionHost, port: request.port, transport: request.transport)
    }

    private func record(_ request: TransportRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(TransportAdapterRequest(host: request.host, port: request.port, transport: request.transport, tls: request.tls, metadata: request.metadata, initialPayload: request.initialPayload))
    }
}

private struct FailingTransportAdapter: TransportAdapter {
    let supportedTransport: TransportType
    let error: TransportError

    init(transport: TransportType, error: TransportError) {
        self.supportedTransport = transport
        self.error = error
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        throw error
    }
}

private struct TCPDialRequest: Equatable {
    let host: String
    let port: Int
    let initialPayload: Data?
}

private final class RecordingTCPDialer: TCPDialer, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [TCPDialRequest] = []

    var requests: [TCPDialRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func open(host: String, port: Int, initialPayload: Data?) async throws -> TCPDialResult {
        record(host: host, port: port, initialPayload: initialPayload)
        return TCPDialResult(host: host, port: port)
    }

    private func record(host: String, port: Int, initialPayload: Data?) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(TCPDialRequest(host: host, port: port, initialPayload: initialPayload))
    }
}

private struct FailingTCPDialer: TCPDialer {
    let error: TransportError

    func open(host: String, port: Int, initialPayload: Data?) async throws -> TCPDialResult {
        throw error
    }
}
