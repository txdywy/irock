import XCTest
import IrockCore
@testable import IrockTransport

private let plannedFoundationMarkers = [
    "vmess-foundation",
    "vless-foundation",
    "trojan-foundation",
    "hysteria2-foundation",
    "tuic-foundation",
    "websocket-foundation",
    "http2-foundation",
    "grpc-foundation",
    "quic-foundation",
    "reality-foundation"
]

final class IrockTransportTests: XCTestCase {
    func testPlannedFoundationMarkersAreNotEmittedByProtocolOrTransportSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoots = [
            root.appendingPathComponent("packages/IrockProtocols/Sources"),
            root.appendingPathComponent("packages/IrockTransport/Sources")
        ]
        let sourceFiles = sourceRoots.flatMap { root in
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
        }
        XCTAssertFalse(sourceFiles.isEmpty)

        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in plannedFoundationMarkers {
                XCTAssertFalse(source.contains(marker), "\(file.path) still contains \(marker)")
            }
        }
    }

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
        XCTAssertTrue(opened.starts(with: Data([0x49, 0x52, 0x4c, 0x52, 0x01])))
        XCTAssertNotNil(opened.range(of: Data([0x01, UInt8("reality.example.com".utf8.count)]) + Data("reality.example.com".utf8)))
        XCTAssertNotNil(opened.range(of: Data([0x02, 0x01, 0x01])))
        XCTAssertNotNil(opened.range(of: Data([0x03, UInt8("/".utf8.count)]) + Data("/".utf8)))
        XCTAssertNotNil(opened.range(of: Data([0x04, UInt8("chrome".utf8.count)]) + Data("chrome".utf8)))
        XCTAssertNotNil(opened.range(of: Data([0x05, UInt8("h2".utf8.count)]) + Data("h2".utf8)))
        XCTAssertEqual(opened.dropLast(payload.count).last, 0x00)
        XCTAssertTrue(opened.suffix(payload.count).elementsEqual(payload))
        XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("reality-foundation") == true)
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
        let prelude = String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8)
        XCTAssertTrue(prelude?.hasPrefix("GET /proxy HTTP/1.1\r\n") == true)
        XCTAssertTrue(prelude?.contains("Host: example.com\r\n") == true)
        XCTAssertTrue(prelude?.contains("Upgrade: websocket\r\n") == true)
        XCTAssertTrue(prelude?.contains("Connection: Upgrade\r\n") == true)
        XCTAssertTrue(prelude?.contains("Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n") == true)
        XCTAssertTrue(prelude?.contains("Sec-WebSocket-Version: 13\r\n") == true)
        XCTAssertTrue(prelude?.contains("Sec-WebSocket-Protocol: vmess\r\n") == true)
        XCTAssertTrue(prelude?.hasSuffix("\r\n\r\nprotocol-open") == true)
        XCTAssertFalse(prelude?.contains("websocket-foundation") == true)
    }

    func testWebSocketTransportAdapterDefaultsPathAndHostMetadata() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = WebSocketTransportAdapter(underlying: underlying)
        let request = TransportRequest(host: "example.com", port: 80, transport: .webSocket)

        _ = try await adapter.open(request: request)

        XCTAssertEqual(underlying.requests.first?.metadata["webSocketHost"], "example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["webSocketPath"], "/")
        XCTAssertNil(underlying.requests.first?.metadata["webSocketProtocol"])
        let prelude = String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8)
        XCTAssertTrue(prelude?.hasPrefix("GET / HTTP/1.1\r\n") == true)
        XCTAssertTrue(prelude?.contains("Host: example.com\r\n") == true)
        XCTAssertFalse(prelude?.contains("Sec-WebSocket-Protocol:") == true)
        XCTAssertTrue(prelude?.hasSuffix("\r\n\r\n") == true)
        XCTAssertFalse(prelude?.contains("websocket-foundation") == true)
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
        let opened = underlying.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(opened.starts(with: Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data([0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00])))
        XCTAssertNotNil(opened.range(of: Data("http2-authority:example.com\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("http2-path:/proxy\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("http2-protocol:vmess\n".utf8)))
        let expectedSuffix = Data("\nprotocol-open".utf8)
        XCTAssertTrue(opened.suffix(expectedSuffix.count).elementsEqual(expectedSuffix))
        XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("http2-foundation") == true)
    }

    func testHTTP2TransportAdapterDefaultsPathAndAuthorityMetadata() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = HTTP2TransportAdapter(underlying: underlying)
        let request = TransportRequest(host: "example.com", port: 80, transport: .http2)

        _ = try await adapter.open(request: request)

        XCTAssertEqual(underlying.requests.first?.metadata["http2Authority"], "example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["http2Path"], "/")
        XCTAssertNil(underlying.requests.first?.metadata["http2Protocol"])
        let opened = underlying.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(opened.starts(with: Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("http2-authority:example.com\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("http2-path:/\n".utf8)))
        XCTAssertNil(opened.range(of: Data("http2-protocol:".utf8)))
        XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("http2-foundation") == true)
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
        let opened = underlying.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(opened.starts(with: Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data([0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00])))
        XCTAssertNotNil(opened.range(of: Data("grpc-authority:example.com\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("grpc-service:/TunnelService/Connect\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("grpc-protocol:vmess\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data([0x00, 0x00, 0x00, 0x00, UInt8(payload.count)])))
        XCTAssertTrue(opened.suffix(payload.count).elementsEqual(payload))
        XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("grpc-foundation") == true)
    }

    func testGRPCTransportAdapterDefaultsServiceAndAuthorityMetadata() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = GRPCTransportAdapter(underlying: underlying)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        _ = try await adapter.open(request: request)

        XCTAssertEqual(underlying.requests.first?.metadata["grpcAuthority"], "example.com")
        XCTAssertEqual(underlying.requests.first?.metadata["grpcService"], "/TunService/Connect")
        XCTAssertNil(underlying.requests.first?.metadata["grpcProtocol"])
        let opened = underlying.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(opened.starts(with: Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("grpc-authority:example.com\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("grpc-service:/TunService/Connect\n".utf8)))
        XCTAssertNil(opened.range(of: Data("grpc-protocol:".utf8)))
        XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("grpc-foundation") == true)
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

    func testQUICTransportAdapterDialsWithMetadataAndPayload() async throws {
        let dialer = RecordingQUICDialer(connectionHost: "connected.example.com")
        let adapter = QUICTransportAdapter(dialer: dialer)
        let payload = Data("protocol-open".utf8)
        let request = TransportRequest(
            host: " example.com ",
            port: 443,
            transport: .quic,
            metadata: ["quicServerName": " quic.example.com ", "quicProtocol": "hysteria2", "quicALPN": "h3"],
            initialPayload: payload
        )

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "connected.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .quic)
        XCTAssertEqual(dialer.requests.count, 1)
        XCTAssertEqual(dialer.requests.first?.host, "example.com")
        XCTAssertEqual(dialer.requests.first?.port, 443)
        XCTAssertEqual(dialer.requests.first?.metadata["quicServerName"], "quic.example.com")
        XCTAssertEqual(dialer.requests.first?.metadata["quicProtocol"], "hysteria2")
        XCTAssertEqual(dialer.requests.first?.metadata["quicALPN"], "h3")
        XCTAssertEqual(dialer.requests.first?.metadata["quicHandshake"], "local-prelude")
        let opened = dialer.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(opened.starts(with: Data([0x49, 0x52, 0x4c, 0x51, 0x01])))
        XCTAssertNotNil(opened.range(of: Data([0x01, UInt8("quic.example.com".utf8.count)]) + Data("quic.example.com".utf8)))
        XCTAssertNotNil(opened.range(of: Data([0x02, UInt8("hysteria2".utf8.count)]) + Data("hysteria2".utf8)))
        XCTAssertNotNil(opened.range(of: Data([0x03, UInt8("h3".utf8.count)]) + Data("h3".utf8)))
        XCTAssertEqual(opened.dropLast(payload.count).last, 0x00)
        XCTAssertTrue(opened.suffix(payload.count).elementsEqual(payload))
        XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("quic-foundation") == true)
    }

    func testQUICTransportAdapterDefaultsServerNameAndALPNMetadata() async throws {
        let dialer = RecordingQUICDialer()
        let adapter = QUICTransportAdapter(dialer: dialer)
        let tls = TLSOptions(enabled: true, serverName: nil, allowInsecure: false, alpn: ["h3", "hq-29"], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic, tls: tls)

        _ = try await adapter.open(request: request)

        XCTAssertEqual(dialer.requests.first?.metadata["quicServerName"], "example.com")
        XCTAssertNil(dialer.requests.first?.metadata["quicProtocol"])
        XCTAssertEqual(dialer.requests.first?.metadata["quicALPN"], "h3,hq-29")
        let opened = dialer.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(opened.starts(with: Data([0x49, 0x52, 0x4c, 0x51, 0x01])))
        XCTAssertNotNil(opened.range(of: Data([0x01, UInt8("example.com".utf8.count)]) + Data("example.com".utf8)))
        XCTAssertNil(opened.range(of: Data([0x02])))
        XCTAssertNotNil(opened.range(of: Data([0x03, UInt8("h3,hq-29".utf8.count)]) + Data("h3,hq-29".utf8)))
        XCTAssertEqual(opened.last, 0x00)
        XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("quic-foundation") == true)
    }

    func testQUICTransportAdapterRejectsInvalidConfigurationBeforeDialing() async {
        let cases: [(TransportRequest, TransportError)] = [
            (TransportRequest(host: "example.com", port: 443, transport: .tcp), .unsupportedTransport(.tcp)),
            (TransportRequest(host: "   ", port: 443, transport: .quic), .invalidConfiguration("missing quic host")),
            (TransportRequest(host: "example.com", port: 0, transport: .quic), .invalidConfiguration("invalid quic port")),
            (TransportRequest(host: "example.com", port: 443, transport: .quic, metadata: ["quicServerName": "   "]), .invalidConfiguration("invalid quic server name")),
            (TransportRequest(host: "example.com", port: 443, transport: .quic, metadata: ["quicProtocol": "   "]), .invalidConfiguration("invalid quic protocol")),
            (TransportRequest(host: "example.com", port: 443, transport: .quic, metadata: ["quicALPN": "   "]), .invalidConfiguration("invalid quic alpn"))
        ]

        for (request, expectedError) in cases {
            let dialer = RecordingQUICDialer()
            let adapter = QUICTransportAdapter(dialer: dialer)
            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected QUIC validation failure")
            } catch let error as TransportError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(dialer.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testQUICTransportAdapterPropagatesDialerTransportError() async {
        let adapter = QUICTransportAdapter(dialer: FailingQUICDialer(error: .quicHandshakeFailed("handshake failed")))
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected QUIC dialer failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .quicHandshakeFailed("handshake failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testQUICStreamTransportAdapterOpensBidirectionalStreamWithMetadataAndPayload() async throws {
        let stream = RecordingTransportByteStream(reads: [Data("server-data".utf8), nil])
        let dialer = RecordingQUICStreamDialer(stream: stream)
        let adapter = QUICStreamTransportAdapter(dialer: dialer)
        let tls = TLSOptions(enabled: true, serverName: nil, allowInsecure: false, alpn: ["h3"], fingerprint: nil, reality: nil)
        let payload = Data("hy2-open".utf8)
        let request = TransportRequest(
            host: " example.com ",
            port: 443,
            transport: .quic,
            tls: tls,
            metadata: ["quicServerName": " hy2.example.com ", "quicProtocol": "hysteria2", "quicALPN": "h3"],
            initialPayload: payload
        )

        let opened = try await adapter.openStream(request: request)
        try await opened.write(Data("client-data".utf8))
        let received = try await opened.read(maxLength: 1024)
        await opened.closeWrite()
        await opened.close()

        XCTAssertEqual(received, Data("server-data".utf8))
        XCTAssertEqual(stream.writes, [Data("client-data".utf8)])
        XCTAssertTrue(stream.didCloseWrite)
        XCTAssertTrue(stream.didClose)
        XCTAssertEqual(dialer.requests.count, 1)
        XCTAssertEqual(dialer.requests.first?.host, "example.com")
        XCTAssertEqual(dialer.requests.first?.port, 443)
        XCTAssertEqual(dialer.requests.first?.tls, tls)
        XCTAssertEqual(dialer.requests.first?.metadata["quicServerName"], "hy2.example.com")
        XCTAssertEqual(dialer.requests.first?.metadata["quicProtocol"], "hysteria2")
        XCTAssertEqual(dialer.requests.first?.metadata["quicALPN"], "h3")
        XCTAssertEqual(dialer.requests.first?.metadata["quicHandshake"], "local-prelude")
        let initialPayload = dialer.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(initialPayload.starts(with: Data([0x49, 0x52, 0x4c, 0x51, 0x01])))
        XCTAssertNotNil(initialPayload.range(of: Data([0x01, UInt8("hy2.example.com".utf8.count)]) + Data("hy2.example.com".utf8)))
        XCTAssertNotNil(initialPayload.range(of: Data([0x02, UInt8("hysteria2".utf8.count)]) + Data("hysteria2".utf8)))
        XCTAssertNotNil(initialPayload.range(of: Data([0x03, UInt8("h3".utf8.count)]) + Data("h3".utf8)))
        XCTAssertEqual(initialPayload.dropLast(payload.count).last, 0x00)
        XCTAssertTrue(initialPayload.suffix(payload.count).elementsEqual(payload))
    }

    func testTransportAdapterRegistryCanSelectQUICTransportAdapter() async throws {
        let dialer = RecordingQUICDialer(connectionHost: "quic.example.com")
        let adapter = QUICTransportAdapter(dialer: dialer)
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .quic)
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .quic)
        XCTAssertEqual(connection.host, "quic.example.com")
        XCTAssertEqual(connection.transport, .quic)
        XCTAssertEqual(dialer.requests.count, 1)
    }

    func testWebSocketClientByteStreamUpgradesMasksWritesAndUnframesBinaryReads() async throws {
        let response = Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ICX+Yqv66kxgM0FcWaLWlFLwTAI=\r\n\r\n".utf8)
        let serverFrame = Data([0x82, 0x05]) + Data("reply".utf8)
        let underlying = RecordingTransportByteStream(reads: [response + serverFrame, nil])
        let stream = WebSocketClientByteStream(
            underlying: underlying,
            host: "edge.example.com",
            path: "/ray",
            protocolName: "vmess",
            initialPayload: Data("open".utf8),
            maskingKey: Data([0x01, 0x02, 0x03, 0x04])
        )

        try await stream.start()
        try await stream.write(Data("ping".utf8))
        let reply = try await stream.read(maxLength: 1024)

        XCTAssertEqual(reply, Data("reply".utf8))
        XCTAssertEqual(underlying.writes.count, 3)
        let handshake = String(data: underlying.writes[0], encoding: .utf8)
        XCTAssertTrue(handshake?.hasPrefix("GET /ray HTTP/1.1\r\n") == true)
        XCTAssertTrue(handshake?.contains("Host: edge.example.com\r\n") == true)
        XCTAssertTrue(handshake?.contains("Upgrade: websocket\r\n") == true)
        XCTAssertTrue(handshake?.contains("Sec-WebSocket-Protocol: vmess\r\n") == true)
        XCTAssertTrue(handshake?.hasSuffix("\r\n\r\n") == true)
        XCTAssertEqual(underlying.writes[1], Data([0x82, 0x84, 0x01, 0x02, 0x03, 0x04, 0x6e, 0x72, 0x66, 0x6a]))
        XCTAssertEqual(underlying.writes[2], Data([0x82, 0x84, 0x01, 0x02, 0x03, 0x04, 0x71, 0x6b, 0x6d, 0x63]))
    }

    func testWebSocketClientByteStreamRejectsNonSwitchingProtocolResponse() async {
        let cases = [
            "HTTP/1.1 403 Forbidden\r\n\r\n",
            "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: invalid\r\n\r\n",
            "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ICX+Yqv66kxgM0FcWaLWlFLwTAI=\r\n\r\n"
        ]

        for response in cases {
            let underlying = RecordingTransportByteStream(reads: [Data(response.utf8)])
            let stream = WebSocketClientByteStream(underlying: underlying, host: "edge.example.com", path: "/ray", maskingKey: Data([0x01, 0x02, 0x03, 0x04]))

            do {
                try await stream.start()
                XCTFail("Expected websocket upgrade failure")
            } catch let error as TransportError {
                XCTAssertEqual(error, .invalidConfiguration("invalid websocket upgrade response"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testWebSocketClientByteStreamRejectsOversizedWritesBeforeCorruptingFrame() async throws {
        let response = Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ICX+Yqv66kxgM0FcWaLWlFLwTAI=\r\n\r\n".utf8)
        let underlying = RecordingTransportByteStream(reads: [response])
        let stream = WebSocketClientByteStream(underlying: underlying, host: "edge.example.com", path: "/ray", maskingKey: Data([0x01, 0x02, 0x03, 0x04]))
        try await stream.start()

        do {
            try await stream.write(Data(repeating: 0x41, count: 65_536))
            XCTFail("Expected oversized websocket frame rejection")
        } catch let error as TransportError {
            XCTAssertEqual(error, .invalidConfiguration("unsupported websocket frame length"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(underlying.writes.count, 1)
    }

    func testWebSocketClientByteStreamRejectsOversizedHandshakeResponse() async {
        let underlying = RecordingTransportByteStream(reads: [Data(repeating: 0x41, count: 16_385)])
        let stream = WebSocketClientByteStream(underlying: underlying, host: "edge.example.com", path: "/ray", maskingKey: Data([0x01, 0x02, 0x03, 0x04]))

        do {
            try await stream.start()
            XCTFail("Expected oversized websocket upgrade response rejection")
        } catch let error as TransportError {
            XCTAssertEqual(error, .invalidConfiguration("invalid websocket upgrade response"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWebSocketClientByteStreamReassemblesFragmentedBinaryFrames() async throws {
        let response = Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ICX+Yqv66kxgM0FcWaLWlFLwTAI=\r\n\r\n".utf8)
        let firstFrame = Data([0x02, 0x05]) + Data("hello".utf8)
        let secondFrame = Data([0x80, 0x06]) + Data("-world".utf8)
        let underlying = RecordingTransportByteStream(reads: [response + firstFrame + secondFrame, nil])
        let stream = WebSocketClientByteStream(underlying: underlying, host: "edge.example.com", path: "/ray", maskingKey: Data([0x01, 0x02, 0x03, 0x04]))

        try await stream.start()
        let data = try await stream.read(maxLength: 64)

        XCTAssertEqual(data, Data("hello-world".utf8))
    }

    func testWebSocketClientByteStreamPreservesFrameRemainderAcrossShortReads() async throws {
        let response = Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ICX+Yqv66kxgM0FcWaLWlFLwTAI=\r\n\r\n".utf8)
        let serverFrame = Data([0x82, 0x0b]) + Data("hello-world".utf8)
        let underlying = RecordingTransportByteStream(reads: [response + serverFrame, nil])
        let stream = WebSocketClientByteStream(underlying: underlying, host: "edge.example.com", path: "/ray", maskingKey: Data([0x01, 0x02, 0x03, 0x04]))

        try await stream.start()
        let first = try await stream.read(maxLength: 5)
        let second = try await stream.read(maxLength: 64)

        XCTAssertEqual(first, Data("hello".utf8))
        XCTAssertEqual(second, Data("-world".utf8))
    }

    func testHTTP2ClientByteStreamStartsWithPrefaceSettingsHeadersAndInitialData() async throws {
        let underlying = RecordingTransportByteStream(reads: [nil])
        let stream = HTTP2ClientByteStream(
            underlying: underlying,
            authority: "edge.example.com",
            path: "/ray",
            initialPayload: Data("open".utf8)
        )

        try await stream.start()

        let frames = http2Frames(in: underlying.writes.reduce(Data(), +))
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].type, 0x04)
        XCTAssertEqual(frames[0].flags, 0x00)
        XCTAssertEqual(frames[0].streamID, 0)
        XCTAssertEqual(frames[0].payload, Data())
        XCTAssertEqual(frames[1].type, 0x01)
        XCTAssertEqual(frames[1].flags, 0x04)
        XCTAssertEqual(frames[1].streamID, 1)
        XCTAssertTrue(frames[1].payload.contains(Data([0x83])))
        XCTAssertTrue(frames[1].payload.contains(Data([0x87])))
        XCTAssertTrue(frames[1].payload.contains(Data("/ray".utf8)))
        XCTAssertTrue(frames[1].payload.contains(Data("edge.example.com".utf8)))
        XCTAssertTrue(frames[1].payload.contains(Data("application/octet-stream".utf8)))
        XCTAssertEqual(frames[2].type, 0x00)
        XCTAssertEqual(frames[2].flags, 0x00)
        XCTAssertEqual(frames[2].streamID, 1)
        XCTAssertEqual(frames[2].payload, Data("open".utf8))
    }

    func testHTTP2ClientByteStreamLargeInitialDataWaitsForWindowUpdatesAfterReaderPumpStarts() async throws {
        let windowUpdates = http2Frame(type: 0x08, flags: 0x00, streamID: 0, payload: Data([0x00, 0x00, 0x11, 0x71]))
            + http2Frame(type: 0x08, flags: 0x00, streamID: 1, payload: Data([0x00, 0x00, 0x11, 0x71]))
        let underlying = ControllableTransportByteStream()
        let initialPayload = Data(repeating: 0x44, count: 70_000)
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray", initialPayload: initialPayload)

        let startTask = Task { try await stream.start() }
        let initialWrites = await underlying.waitForWriteCount(5)
        let initialDataFrames = http2DataFrames(in: initialWrites)
        XCTAssertEqual(initialDataFrames.map(\.payload.count).reduce(0, +), 65_535)

        underlying.enqueueRead(windowUpdates)
        try await startTask.value

        let allDataFrames = http2DataFrames(in: underlying.writes)
        XCTAssertEqual(allDataFrames.map(\.payload.count).reduce(0, +), 70_000)
        await stream.close()
    }

    func testHTTP2ClientByteStreamWritesDataFrames() async throws {
        let underlying = RecordingTransportByteStream(reads: [nil])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()

        try await stream.write(Data("ping".utf8))

        XCTAssertEqual(underlying.writes.count, 2)
        let frames = http2Frames(in: underlying.writes[1])
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].type, 0x00)
        XCTAssertEqual(frames[0].flags, 0x00)
        XCTAssertEqual(frames[0].streamID, 1)
        XCTAssertEqual(frames[0].payload, Data("ping".utf8))
    }

    func testHTTP2ClientByteStreamCloseWriteOnlyEndsStreamOne() async throws {
        let underlying = RecordingTransportByteStream(reads: [nil])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()

        await stream.closeWrite()

        XCTAssertFalse(underlying.didCloseWrite)
        XCTAssertEqual(underlying.writes.count, 2)
        let frames = http2Frames(in: underlying.writes[1])
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].type, 0x00)
        XCTAssertEqual(frames[0].flags, 0x01)
        XCTAssertEqual(frames[0].streamID, 1)
        XCTAssertEqual(frames[0].payload, Data())
    }

    func testHTTP2ClientByteStreamWriteHonorsInitialSendWindowThenWindowUpdates() async throws {
        let windowUpdates = http2Frame(type: 0x08, flags: 0x00, streamID: 0, payload: Data([0x00, 0x00, 0x11, 0x71]))
            + http2Frame(type: 0x08, flags: 0x00, streamID: 1, payload: Data([0x00, 0x00, 0x11, 0x71]))
        let underlying = ControllableTransportByteStream()
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        let payload = Data(repeating: 0x41, count: 70_000)
        try await stream.start()

        let writeTask = Task { try await stream.write(payload) }
        let initialWrites = await underlying.waitForWriteCount(5)
        let initialDataFrames = http2DataFrames(in: initialWrites)
        XCTAssertEqual(initialDataFrames.map(\.payload.count).reduce(0, +), 65_535)
        XCTAssertTrue(initialDataFrames.allSatisfy { $0.payload.count <= 16_384 })

        underlying.enqueueRead(windowUpdates)
        try await writeTask.value

        let allDataFrames = http2DataFrames(in: underlying.writes)
        XCTAssertEqual(allDataFrames.map(\.payload.count).reduce(0, +), 70_000)
        XCTAssertTrue(allDataFrames.allSatisfy { $0.payload.count <= 16_384 })
        await stream.close()
    }

    func testHTTP2ClientByteStreamAppliesLowerInitialWindowSettingBeforeWrite() async throws {
        let settings = http2Frame(type: 0x04, flags: 0x00, streamID: 0, payload: Data([0x00, 0x04, 0x00, 0x00, 0x04, 0x00]))
        let headers = http2Frame(type: 0x01, flags: 0x04, streamID: 1, payload: Data([0x88]))
        let windowUpdates = http2Frame(type: 0x08, flags: 0x00, streamID: 0, payload: Data([0x00, 0x00, 0x04, 0x00]))
            + http2Frame(type: 0x08, flags: 0x00, streamID: 1, payload: Data([0x00, 0x00, 0x04, 0x00]))
        let underlying = ControllableTransportByteStream(reads: [settings + headers])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()
        try await stream.waitForResponseHeaders()

        let writeTask = Task { try await stream.write(Data(repeating: 0x42, count: 2_048)) }
        let initialDataFrames = http2DataFrames(in: await underlying.waitForWriteCount(3))
        XCTAssertEqual(initialDataFrames.map(\.payload.count).reduce(0, +), 1_024)

        underlying.enqueueRead(windowUpdates)
        try await writeTask.value

        let allDataFrames = http2DataFrames(in: underlying.writes)
        XCTAssertEqual(allDataFrames.map(\.payload.count).reduce(0, +), 2_048)
        await stream.close()
    }

    func testHTTP2ClientByteStreamWriteBuffersInboundDataWhileWaitingForWindowUpdate() async throws {
        let inboundData = http2Frame(type: 0x00, flags: 0x00, streamID: 1, payload: Data("reply".utf8))
        let windowUpdates = http2Frame(type: 0x08, flags: 0x00, streamID: 0, payload: Data([0x00, 0x00, 0x11, 0x71]))
            + http2Frame(type: 0x08, flags: 0x00, streamID: 1, payload: Data([0x00, 0x00, 0x11, 0x71]))
        let underlying = ControllableTransportByteStream(reads: [inboundData])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()

        let writeTask = Task { try await stream.write(Data(repeating: 0x43, count: 70_000)) }
        _ = await underlying.waitForWriteCount(5)
        underlying.enqueueRead(windowUpdates)
        try await writeTask.value
        let reply = try await stream.read(maxLength: 64)

        XCTAssertEqual(reply, Data("reply".utf8))
        await stream.close()
    }

    func testHTTP2ClientByteStreamReadsDataAndPreservesRemainder() async throws {
        let serverSettings = http2Frame(type: 0x04, flags: 0x00, streamID: 0, payload: Data())
        let windowUpdate = http2Frame(type: 0x08, flags: 0x00, streamID: 0, payload: Data([0x00, 0x00, 0x10, 0x00]))
        let serverData = http2Frame(type: 0x00, flags: 0x00, streamID: 1, payload: Data("hello-world".utf8))
        let underlying = RecordingTransportByteStream(reads: [serverSettings + windowUpdate + serverData, nil])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()

        let first = try await stream.read(maxLength: 5)
        let second = try await stream.read(maxLength: 64)

        XCTAssertEqual(first, Data("hello".utf8))
        XCTAssertEqual(second, Data("-world".utf8))
        XCTAssertEqual(underlying.writes.count, 4)
        XCTAssertEqual(http2Frames(in: underlying.writes[1]).first?.type, 0x04)
        XCTAssertEqual(http2Frames(in: underlying.writes[1]).first?.flags, 0x01)
        let firstUpdates = http2Frames(in: underlying.writes[2])
        XCTAssertEqual(firstUpdates.count, 2)
        XCTAssertEqual(firstUpdates[0].type, 0x08)
        XCTAssertEqual(firstUpdates[0].streamID, 0)
        XCTAssertEqual(firstUpdates[0].payload, Data([0x00, 0x00, 0x00, 0x05]))
        XCTAssertEqual(firstUpdates[1].type, 0x08)
        XCTAssertEqual(firstUpdates[1].streamID, 1)
        XCTAssertEqual(firstUpdates[1].payload, Data([0x00, 0x00, 0x00, 0x05]))
        let secondUpdates = http2Frames(in: underlying.writes[3])
        XCTAssertEqual(secondUpdates.count, 2)
        XCTAssertEqual(secondUpdates[0].type, 0x08)
        XCTAssertEqual(secondUpdates[0].streamID, 0)
        XCTAssertEqual(secondUpdates[0].payload, Data([0x00, 0x00, 0x00, 0x06]))
        XCTAssertEqual(secondUpdates[1].type, 0x08)
        XCTAssertEqual(secondUpdates[1].streamID, 1)
        XCTAssertEqual(secondUpdates[1].payload, Data([0x00, 0x00, 0x00, 0x06]))
    }

    func testHTTP2ClientByteStreamDelaysWindowUpdatesUntilInboundDataIsRead() async throws {
        let inboundData = http2Frame(type: 0x00, flags: 0x00, streamID: 1, payload: Data("reply".utf8))
        let underlying = RecordingTransportByteStream(reads: [inboundData, nil])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()

        let reply = try await stream.read(maxLength: 2)

        XCTAssertEqual(reply, Data("re".utf8))
        let updates = underlying.writes.dropFirst().flatMap { http2Frames(in: $0) }.filter { $0.type == 0x08 }
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].streamID, 0)
        XCTAssertEqual(updates[0].payload, Data([0x00, 0x00, 0x00, 0x02]))
        XCTAssertEqual(updates[1].streamID, 1)
        XCTAssertEqual(updates[1].payload, Data([0x00, 0x00, 0x00, 0x02]))
    }

    func testHTTP2ClientByteStreamHandlesPaddedDataAndPriorityHeaders() async throws {
        let priority = Data([0x00, 0x00, 0x00, 0x00, 0x10])
        let headers = http2Frame(type: 0x01, flags: 0x2c, streamID: 1, payload: Data([0x00]) + priority + Data([0x88]))
        let dataPayload = Data([0x02]) + Data("ok".utf8) + Data([0x00, 0x00])
        let data = http2Frame(type: 0x00, flags: 0x08, streamID: 1, payload: dataPayload)
        let underlying = RecordingTransportByteStream(reads: [headers + data, nil])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()

        try await stream.waitForResponseHeaders()
        let reply = try await stream.read(maxLength: 64)

        XCTAssertEqual(reply, Data("ok".utf8))
        let updates = underlying.writes.dropFirst().flatMap { http2Frames(in: $0) }.filter { $0.type == 0x08 }
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].payload, Data([0x00, 0x00, 0x00, 0x02]))
        XCTAssertEqual(updates[1].payload, Data([0x00, 0x00, 0x00, 0x02]))
    }

    func testHTTP2ClientByteStreamWaitForResponseHeadersAccepts2xxStatus() async throws {
        let headers = http2Frame(type: 0x01, flags: 0x04, streamID: 1, payload: Data([0x88]))
        let underlying = RecordingTransportByteStream(reads: [headers, nil])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()

        try await stream.waitForResponseHeaders()
    }

    func testHTTP2ClientByteStreamWaitForResponseHeadersAcceptsLiteralIndexedStatus() async throws {
        let headers = http2Frame(type: 0x01, flags: 0x04, streamID: 1, payload: Data([0x48, 0x03]) + Data("200".utf8))
        let underlying = RecordingTransportByteStream(reads: [headers, nil])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()

        try await stream.waitForResponseHeaders()
    }

    func testHTTP2ClientByteStreamWaitForResponseHeadersCombinesContinuation() async throws {
        let headers = http2Frame(type: 0x01, flags: 0x00, streamID: 1, payload: Data([0x48]))
        let continuation = http2Frame(type: 0x09, flags: 0x04, streamID: 1, payload: Data([0x03]) + Data("200".utf8))
        let underlying = RecordingTransportByteStream(reads: [headers + continuation, nil])
        let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
        try await stream.start()

        try await stream.waitForResponseHeaders()
    }

    func testHTTP2ClientByteStreamWaitForResponseHeadersRejectsNon2xxAndReset() async throws {
        let non2xx = http2Frame(type: 0x01, flags: 0x04, streamID: 1, payload: Data([0x8d]))
        let reset = http2Frame(type: 0x03, flags: 0x00, streamID: 1, payload: Data([0x00, 0x00, 0x00, 0x00]))

        for frame in [non2xx, reset] {
            let underlying = RecordingTransportByteStream(reads: [frame, nil])
            let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
            try await stream.start()

            do {
                try await stream.waitForResponseHeaders()
                XCTFail("Expected HTTP/2 response rejection")
            } catch let error as TransportError {
                XCTAssertEqual(error, .invalidConfiguration("invalid http2 response"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testHTTP2ClientByteStreamTreatsEndStreamAndResetAsEOF() async throws {
        let endStream = http2Frame(type: 0x00, flags: 0x01, streamID: 1, payload: Data())
        let reset = http2Frame(type: 0x03, flags: 0x00, streamID: 1, payload: Data([0x00, 0x00, 0x00, 0x00]))

        for frame in [endStream, reset] {
            let underlying = RecordingTransportByteStream(reads: [frame, nil])
            let stream = HTTP2ClientByteStream(underlying: underlying, authority: "edge.example.com", path: "/ray")
            try await stream.start()

            let data = try await stream.read(maxLength: 64)

            XCTAssertNil(data)
        }
    }
}

private struct HTTP2Frame: Equatable {
    let type: UInt8
    let flags: UInt8
    let streamID: UInt32
    let payload: Data
}

private func http2Frame(type: UInt8, flags: UInt8, streamID: UInt32, payload: Data) -> Data {
    var frame = Data([
        UInt8((payload.count >> 16) & 0xff),
        UInt8((payload.count >> 8) & 0xff),
        UInt8(payload.count & 0xff),
        type,
        flags,
        UInt8((streamID >> 24) & 0x7f),
        UInt8((streamID >> 16) & 0xff),
        UInt8((streamID >> 8) & 0xff),
        UInt8(streamID & 0xff)
    ])
    frame.append(payload)
    return frame
}

private func http2Frames(in data: Data.SubSequence) -> [HTTP2Frame] {
    var frames: [HTTP2Frame] = []
    let preface = Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)
    var cursor = data.starts(with: preface) ? data.index(data.startIndex, offsetBy: preface.count) : data.startIndex
    while data.distance(from: cursor, to: data.endIndex) >= 9 {
        let length = Int(data[cursor]) << 16 | Int(data[data.index(cursor, offsetBy: 1)]) << 8 | Int(data[data.index(cursor, offsetBy: 2)])
        guard data.distance(from: cursor, to: data.endIndex) >= 9 + length else { break }
        let type = data[data.index(cursor, offsetBy: 3)]
        let flags = data[data.index(cursor, offsetBy: 4)]
        let streamID = (UInt32(data[data.index(cursor, offsetBy: 5)] & 0x7f) << 24)
            | (UInt32(data[data.index(cursor, offsetBy: 6)]) << 16)
            | (UInt32(data[data.index(cursor, offsetBy: 7)]) << 8)
            | UInt32(data[data.index(cursor, offsetBy: 8)])
        let payloadStart = data.index(cursor, offsetBy: 9)
        let payloadEnd = data.index(payloadStart, offsetBy: length)
        frames.append(HTTP2Frame(type: type, flags: flags, streamID: streamID, payload: Data(data[payloadStart..<payloadEnd])))
        cursor = payloadEnd
    }
    return frames
}

private func http2DataFrames(in writes: [Data]) -> [HTTP2Frame] {
    writes.flatMap { http2Frames(in: $0) }.filter { $0.type == 0x00 && $0.streamID == 1 && !$0.payload.isEmpty }
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

private struct QUICDialRequest: Equatable {
    let host: String
    let port: Int
    let metadata: [String: String]
    let initialPayload: Data?
}

private final class RecordingQUICDialer: QUICDialer, @unchecked Sendable {
    private let lock = NSLock()
    private let connectionHost: String
    private var storedRequests: [QUICDialRequest] = []

    init(connectionHost: String = "example.com") {
        self.connectionHost = connectionHost
    }

    var requests: [QUICDialRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func open(host: String, port: Int, metadata: [String: String], initialPayload: Data?) async throws -> QUICDialResult {
        record(host: host, port: port, metadata: metadata, initialPayload: initialPayload)
        return QUICDialResult(host: connectionHost, port: port)
    }

    private func record(host: String, port: Int, metadata: [String: String], initialPayload: Data?) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(QUICDialRequest(host: host, port: port, metadata: metadata, initialPayload: initialPayload))
    }
}

private struct FailingQUICDialer: QUICDialer {
    let error: TransportError

    func open(host: String, port: Int, metadata: [String: String], initialPayload: Data?) async throws -> QUICDialResult {
        throw error
    }
}

private struct QUICStreamDialRequest: Equatable {
    let host: String
    let port: Int
    let tls: TLSOptions?
    let metadata: [String: String]
    let initialPayload: Data?
}

private final class RecordingQUICStreamDialer: QUICStreamDialer, @unchecked Sendable {
    private let stream: RecordingTransportByteStream
    private var storedRequests: [QUICStreamDialRequest] = []

    init(stream: RecordingTransportByteStream) {
        self.stream = stream
    }

    var requests: [QUICStreamDialRequest] { storedRequests }

    func openBidirectionalStream(host: String, port: Int, tls: TLSOptions?, metadata: [String: String], initialPayload: Data?) async throws -> any TransportByteStream {
        storedRequests.append(QUICStreamDialRequest(host: host, port: port, tls: tls, metadata: metadata, initialPayload: initialPayload))
        return stream
    }
}

private final class RecordingTransportByteStream: TransportByteStream, @unchecked Sendable {
    private let queue = DispatchQueue(label: "RecordingTransportByteStream")
    private var reads: [Data?]
    private var storedWrites: [Data] = []
    private var closeWriteCalled = false
    private var closeCalled = false

    init(reads: [Data?]) {
        self.reads = reads
    }

    var writes: [Data] {
        queue.sync { storedWrites }
    }

    var didCloseWrite: Bool {
        queue.sync { closeWriteCalled }
    }

    var didClose: Bool {
        queue.sync { closeCalled }
    }

    func read(maxLength: Int) async throws -> Data? {
        queue.sync {
            guard !reads.isEmpty else { return nil }
            return reads.removeFirst()
        }
    }

    func write(_ data: Data) async throws {
        queue.sync {
            storedWrites.append(data)
        }
    }

    func closeWrite() async {
        queue.sync {
            closeWriteCalled = true
        }
    }

    func close() async {
        queue.sync {
            closeCalled = true
        }
    }
}

private final class ControllableTransportByteStream: TransportByteStream, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ControllableTransportByteStream")
    private var reads: [Data?]
    private var readWaiters: [CheckedContinuation<Data?, Never>] = []
    private var writeWaiters: [(Int, CheckedContinuation<[Data], Never>)] = []
    private var storedWrites: [Data] = []
    private var closeCalled = false

    init(reads: [Data] = []) {
        self.reads = reads.map { Optional($0) }
    }

    var writes: [Data] {
        queue.sync { storedWrites }
    }

    func enqueueRead(_ data: Data?) {
        let waiter = queue.sync { () -> CheckedContinuation<Data?, Never>? in
            if readWaiters.isEmpty {
                reads.append(data)
                return nil
            }
            return readWaiters.removeFirst()
        }
        waiter?.resume(returning: data)
    }

    func read(maxLength: Int) async throws -> Data? {
        let queued = queue.sync { () -> (available: Bool, data: Data?) in
            guard !reads.isEmpty else { return (false, nil) }
            return (true, reads.removeFirst())
        }
        if queued.available {
            return queued.data
        }
        return await withCheckedContinuation { continuation in
            queue.sync {
                readWaiters.append(continuation)
            }
        }
    }

    func write(_ data: Data) async throws {
        let ready = queue.sync { () -> [(CheckedContinuation<[Data], Never>, [Data])] in
            storedWrites.append(data)
            let readyWaiters = writeWaiters.filter { storedWrites.count >= $0.0 }
            writeWaiters.removeAll { storedWrites.count >= $0.0 }
            let writes = storedWrites
            return readyWaiters.map { ($0.1, writes) }
        }
        for (waiter, writes) in ready {
            waiter.resume(returning: writes)
        }
    }

    func waitForWriteCount(_ count: Int) async -> [Data] {
        let current = queue.sync { storedWrites.count >= count ? storedWrites : nil }
        if let current {
            return current
        }
        return await withCheckedContinuation { continuation in
            queue.sync {
                writeWaiters.append((count, continuation))
            }
        }
    }

    func closeWrite() async {}

    func close() async {
        let waiters = queue.sync { () -> [CheckedContinuation<Data?, Never>] in
            closeCalled = true
            let waiters = readWaiters
            readWaiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
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
