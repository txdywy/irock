import XCTest
import IrockCore
import IrockTransport
@testable import IrockProtocols

final class IrockProtocolsTests: XCTestCase {
    func testProxyDestinationEquatableCases() {
        XCTAssertEqual(ProxyDestination.host("apple.com", port: 443), .host("apple.com", port: 443))
        XCTAssertEqual(ProxyDestination.ipv4("93.184.216.34", port: 443), .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(ProxyDestination.ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443), .ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443))
        XCTAssertNotEqual(ProxyDestination.host("apple.com", port: 443), .host("apple.com", port: 80))
    }

    func testProxyRequestStoresNodeDestinationAndMetadata() {
        let node = makeNode(protocolType: .trojan, transport: .tcp)
        let request = ProxyRequest(
            node: node,
            destination: .host("apple.com", port: 443),
            metadata: ["source": "unit-test"]
        )

        XCTAssertEqual(request.node.protocolType, .trojan)
        XCTAssertEqual(request.destination, .host("apple.com", port: 443))
        XCTAssertEqual(request.metadata, ["source": "unit-test"])
    }

    func testProxyRequestDefaultsMetadataToEmpty() {
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp), destination: .ipv4("1.1.1.1", port: 53))

        XCTAssertEqual(request.metadata, [:])
    }

    func testEstablishedProxyConnectionStoresNodeIDAndDestination() {
        let connection = EstablishedProxyConnection(
            nodeID: NodeID(rawValue: "node-1"),
            destination: .host("apple.com", port: 443)
        )

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
    }

    func testUnsupportedProxyAdapterFailsWithRequestedProtocol() async {
        let node = makeNode(protocolType: .tuic, transport: .quic)
        let adapter = UnsupportedProxyAdapter(protocolType: .tuic)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.tuic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNoopProxyAdapterRemainsUnsupportedAlias() async {
        let node = makeNode(protocolType: .hysteria2, transport: .quic)
        let adapter = NoopProxyAdapter()
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.hysteria2))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProxyProtocolErrorDescriptionsAreStableAndCredentialSafe() {
        let errors: [(ProxyProtocolError, String)] = [
            (.invalidConfiguration("missing server host"), "Invalid configuration"),
            (.dnsFailed("example.com"), "DNS failed"),
            (.tcpConnectFailed("connection refused"), "TCP connect failed"),
            (.tlsHandshakeFailed("certificate rejected"), "TLS handshake failed"),
            (.authenticationFailed("method rejected"), "Authentication failed"),
            (.unsupportedTransport(.quic), "Unsupported transport: quic"),
            (.unsupportedProtocol(.tuic), "Unsupported protocol: tuic"),
            (.protocolHandshakeFailed("bad response"), "Protocol handshake failed"),
            (.quicHandshakeFailed("timeout"), "QUIC handshake failed"),
            (.udpUnsupported, "UDP unsupported"),
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

    func testProxyProtocolErrorDescriptionsRedactSensitiveAssociatedStrings() {
        let errors: [ProxyProtocolError] = [
            .invalidConfiguration("uri=ss://password=secret-token@example.com"),
            .dnsFailed("password=secret-token"),
            .tcpConnectFailed("token=secret-token"),
            .tlsHandshakeFailed("password=secret-token"),
            .authenticationFailed("password=secret-token"),
            .protocolHandshakeFailed("password=secret-token"),
            .quicHandshakeFailed("password=secret-token")
        ]

        for error in errors {
            XCTAssertFalse(error.description.contains("password"))
            XCTAssertFalse(error.description.contains("secret"))
            XCTAssertFalse(error.description.contains("token"))
        }
    }

    func testProxyAdapterRegistryReturnsRegisteredAdapter() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let registry = ProxyAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .trojan)
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        let connection = try await selected.connect(request: request)

        XCTAssertEqual(selected.supportedProtocol, .trojan)
        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
    }

    func testProxyAdapterRegistryFallsBackToUnsupportedAdapter() async {
        let registry = ProxyAdapterRegistry(adapters: [])
        let selected = registry.adapter(for: .vless)
        let request = ProxyRequest(node: makeNode(protocolType: .vless, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await selected.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vless))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProxyAdapterRegistryUsesLastRegisteredAdapterForDuplicates() async throws {
        let first = RecordingProxyAdapter(protocolType: .vmess, connectionNodeID: NodeID(rawValue: "first"))
        let second = RecordingProxyAdapter(protocolType: .vmess, connectionNodeID: NodeID(rawValue: "second"))
        let registry = ProxyAdapterRegistry(adapters: [first, second])
        let selected = registry.adapter(for: .vmess)
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        let connection = try await selected.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "second"))
    }

    func testTransportBackedProxyAdapterOpensNodeTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .grpc)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .trojan, transport: .grpc)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .grpc)
        XCTAssertEqual(transport.requests.first?.tls?.enabled, true)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "trojan")
        XCTAssertEqual(transport.requests.first?.metadata["destination"], "host:apple.com:443")
    }

    func testTransportBackedProxyAdapterRejectsProtocolMismatchBeforeOpeningTransport() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vmess))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportBackedProxyAdapterOmitsDisabledTLS() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp, tls: .disabled), destination: .ipv4("93.184.216.34", port: 443))

        _ = try await adapter.connect(request: request)

        XCTAssertNil(transport.requests.first?.tls)
        XCTAssertEqual(transport.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
    }

    func testShadowsocksProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsEmptyServerHostBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, serverHost: "   "), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("missing shadowsocks server host"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsInvalidServerPortBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, serverPort: 0), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("invalid shadowsocks server port"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsEmptyCredentialAccountBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, credentialAccount: "   "), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("missing shadowsocks credential account"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsNonTCPTransportBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .grpc)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .grpc), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterReportsSupportedProtocol() {
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: []))

        XCTAssertEqual(adapter.supportedProtocol, .shadowsocks)
    }

    func testShadowsocksProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "shadowsocks")
    }

    func testTransportBackedProxyAdapterMapsTransportErrorsToProtocolErrors() async {
        let cases: [(TransportError, ProxyProtocolError)] = [
            (.invalidConfiguration("secret invalid"), .invalidConfiguration("transport invalid")),
            (.dnsFailed("secret host"), .dnsFailed("transport dns failed")),
            (.tcpConnectFailed("password refused"), .tcpConnectFailed("transport tcp connect failed")),
            (.tlsHandshakeFailed("token rejected"), .tlsHandshakeFailed("transport tls handshake failed")),
            (.unsupportedTransport(.quic), .unsupportedTransport(.quic)),
            (.quicHandshakeFailed("secret timeout"), .quicHandshakeFailed("transport quic handshake failed")),
            (.remoteClosed, .remoteClosed),
            (.timeout, .timeout)
        ]

        for (transportError, expectedProtocolError) in cases {
            let adapter = TransportBackedProxyAdapter(
                protocolType: .trojan,
                transportRegistry: TransportAdapterRegistry(adapters: [FailingTransportAdapter(transport: .tcp, error: transportError)])
            )
            let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

            do {
                _ = try await adapter.connect(request: request)
                XCTFail("Expected protocol error")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedProtocolError)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeNode(
        protocolType: ProxyProtocolType,
        transport: TransportType,
        tls: TLSOptions = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
        serverHost: String = "example.com",
        serverPort: Int = 443,
        credentialAccount: String = "node-1"
    ) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo Node",
            protocolType: protocolType,
            serverHost: serverHost,
            serverPort: serverPort,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: credentialAccount),
            transport: transport,
            tls: tls,
            udpPolicy: .disabled
        )
    }

    private struct RecordingProxyAdapter: ProxyAdapter {
        let supportedProtocol: ProxyProtocolType
        let connectionNodeID: NodeID

        init(protocolType: ProxyProtocolType, connectionNodeID: NodeID = NodeID(rawValue: "node-1")) {
            self.supportedProtocol = protocolType
            self.connectionNodeID = connectionNodeID
        }

        func connect(request: ProxyRequest) async throws -> any ProxyConnection {
            EstablishedProxyConnection(nodeID: connectionNodeID, destination: request.destination)
        }
    }
}

private final class RecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    private let lock = NSLock()
    private var storedRequests: [TransportRequest] = []

    var requests: [TransportRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    init(transport: TransportType) {
        self.supportedTransport = transport
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        record(request)
        return EstablishedTransportConnection(host: request.host, port: request.port, transport: request.transport)
    }

    private func record(_ request: TransportRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(request)
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
