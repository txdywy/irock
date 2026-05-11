import XCTest
import IrockCore
import IrockProtocols
import IrockRouting
import IrockStorage
import IrockTransport
@testable import IrockTunnelCore

final class RuntimeProxyStackTests: XCTestCase {
    func testShadowsocksTCPConfigurationWiresStackIntoPacketTunnelRuntime() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let reader = InMemoryPacketReader(packets: [Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)])
        let writer = InMemoryPacketWriter()
        let configuration = TunnelRuntimeConfiguration.shadowsocksTCP(
            snapshot: snapshot(tls: .disabled),
            routingEngine: RoutingEngine(rules: [.final(.proxy)]),
            plain: plain,
            tls: tlsChild,
            credentialResolver: TestShadowsocksCredentialResolver(),
            batchLimit: 16,
            flowLimit: 32
        )
        let runtime = PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration)

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.dropCount, 0)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(tlsChild.requests, [])
        XCTAssertEqual(writer.writtenResults.count, 1)
    }

    func testShadowsocksTCPConfigurationPublishesFailureWhenTLSChildFails() async throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = FailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("secret tls refused"))
        let reader = InMemoryPacketReader(packets: [Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)])
        let writer = InMemoryPacketWriter()
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let configuration = TunnelRuntimeConfiguration.shadowsocksTCP(
            snapshot: snapshot(tls: tls),
            routingEngine: RoutingEngine(rules: [.final(.proxy)]),
            plain: plain,
            tls: tlsChild,
            credentialResolver: TestShadowsocksCredentialResolver(),
            batchLimit: 16,
            flowLimit: 32
        )
        let runtime = PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected mapped TLS failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tlsHandshakeFailed("transport tls handshake failed"))
            XCTAssertEqual(plain.requests, [])
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Proxy adapter failed: TLS handshake failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Proxy adapter failed: TLS handshake failed"])
            XCTAssertEqual(writer.writtenResults, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksTCPStackRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tlsChild, credentialResolver: TestShadowsocksCredentialResolver())
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let outbound = ProxyOutbound(node: makeNode(tls: tls), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection?.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.host, "example.com")
        XCTAssertEqual(tlsChild.requests.first?.port, 443)
        XCTAssertEqual(tlsChild.requests.first?.transport, .tcp)
        XCTAssertEqual(tlsChild.requests.first?.tls, tls)
        XCTAssertEqual(tlsChild.requests.first?.metadata["packetID"], "tcp-1")
        XCTAssertEqual(tlsChild.requests.first?.metadata["transportProtocol"], "tcp")
        XCTAssertEqual(tlsChild.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(tlsChild.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
    }

    func testShadowsocksTCPStackRoutesDisabledTLSToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tlsChild, credentialResolver: TestShadowsocksCredentialResolver())
        let outbound = ProxyOutbound(node: makeNode(tls: .disabled), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection?.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(plain.requests.first?.host, "example.com")
        XCTAssertEqual(plain.requests.first?.port, 443)
        XCTAssertEqual(plain.requests.first?.transport, .tcp)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["packetID"], "tcp-1")
        XCTAssertEqual(plain.requests.first?.metadata["transportProtocol"], "tcp")
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(plain.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testVMessTCPStackRoutesDisabledTLSToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.vmessTCP(plain: plain, tls: tlsChild)
        let outbound = ProxyOutbound(node: makeVMessNode(tls: .disabled), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "vmess")
        XCTAssertEqual(plain.requests.first?.metadata["vmessUserIDPresent"], "true")
        XCTAssertNil(plain.requests.first?.metadata["vmessUserID"])
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testVMessTCPStackRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.vmessTCP(plain: plain, tls: tlsChild)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let outbound = ProxyOutbound(node: makeVMessNode(tls: tls), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.tls, tls)
        XCTAssertEqual(tlsChild.requests.first?.metadata["proxyProtocol"], "vmess")
        XCTAssertEqual(tlsChild.requests.first?.metadata["vmessUserIDPresent"], "true")
        XCTAssertNil(tlsChild.requests.first?.metadata["vmessUserID"])
    }

    func testVLESSTCPStackRoutesDisabledTLSToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.vlessTCP(plain: plain, tls: tlsChild)
        let outbound = ProxyOutbound(node: makeVLESSNode(tls: .disabled), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "vless")
        XCTAssertEqual(plain.requests.first?.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(plain.requests.first?.metadata["vlessUserID"])
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testVLESSTCPStackRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.vlessTCP(plain: plain, tls: tlsChild)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let outbound = ProxyOutbound(node: makeVLESSNode(tls: tls), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.tls, tls)
        XCTAssertEqual(tlsChild.requests.first?.metadata["proxyProtocol"], "vless")
        XCTAssertEqual(tlsChild.requests.first?.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(tlsChild.requests.first?.metadata["vlessUserID"])
    }

    func testVLESSRealityTCPStackRoutesThroughRealityAdapter() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let reality = RealityOptions(publicKey: "reality-public-key", shortID: "abc123", spiderX: "/")
        let tls = TLSOptions(enabled: true, serverName: "reality.example.com", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: reality)
        let registry = RuntimeProxyStack.vlessRealityTCP(plain: plain)
        let outbound = ProxyOutbound(node: makeVLESSNode(tls: tls), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "vless")
        XCTAssertEqual(plain.requests.first?.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(plain.requests.first?.metadata["vlessUserID"])
        XCTAssertEqual(plain.requests.first?.metadata["realityServerName"], "reality.example.com")
        XCTAssertEqual(plain.requests.first?.metadata["realityPublicKeyPresent"], "true")
        XCTAssertEqual(plain.requests.first?.metadata["realityShortIDPresent"], "true")
        let payload = plain.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(String(data: payload, encoding: .utf8)?.hasPrefix("reality-foundation:reality.example.com:public-key-present:true:/\n") == true)
        XCTAssertFalse(payload.contains(Data("reality-public-key".utf8)))
        XCTAssertFalse(payload.contains(Data("00000000-0000-0000-0000-000000000002".utf8)))
    }

    func testHysteria2QUICStackRoutesThroughQUICTransport() async throws {
        let quic = RecordingTransportAdapter(transport: .quic)
        let registry = RuntimeProxyStack.hysteria2QUIC(quic: quic)
        let outbound = ProxyOutbound(node: makeHysteria2Node(), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(quic.requests.count, 1)
        XCTAssertEqual(quic.requests.first?.transport, .quic)
        XCTAssertEqual(quic.requests.first?.metadata["proxyProtocol"], "hysteria2")
        XCTAssertEqual(quic.requests.first?.metadata["hysteria2AuthPresent"], "true")
        XCTAssertEqual(quic.requests.first?.metadata["hysteria2Destination"], "ipv4:93.184.216.34:443")
        let payload = quic.requests.first?.initialPayload ?? Data()
        XCTAssertFalse(payload.contains(Data("hysteria-secret".utf8)))
    }

    func testTUICQUICStackRoutesThroughQUICTransport() async throws {
        let quic = RecordingTransportAdapter(transport: .quic)
        let registry = RuntimeProxyStack.tuicQUIC(quic: quic)
        let outbound = ProxyOutbound(node: makeTUICNode(), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(quic.requests.count, 1)
        XCTAssertEqual(quic.requests.first?.transport, .quic)
        XCTAssertEqual(quic.requests.first?.metadata["proxyProtocol"], "tuic")
        XCTAssertEqual(quic.requests.first?.metadata["tuicUUIDPresent"], "true")
        XCTAssertEqual(quic.requests.first?.metadata["tuicPasswordPresent"], "true")
        XCTAssertEqual(quic.requests.first?.metadata["tuicDestination"], "ipv4:93.184.216.34:443")
        let payload = quic.requests.first?.initialPayload ?? Data()
        XCTAssertFalse(payload.contains(Data("00000000-0000-0000-0000-000000000003".utf8)))
        XCTAssertFalse(payload.contains(Data("tuic-password".utf8)))
    }

    func testTrojanTCPStackRoutesDisabledTLSToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.trojanTCP(plain: plain, tls: tlsChild)
        let outbound = ProxyOutbound(node: makeTrojanNode(tls: .disabled), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "trojan")
        XCTAssertEqual(plain.requests.first?.metadata["trojanPasswordPresent"], "true")
        XCTAssertNil(plain.requests.first?.metadata["trojanPassword"])
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testTrojanTCPStackRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.trojanTCP(plain: plain, tls: tlsChild)
        let tls = TLSOptions(enabled: true, serverName: "trojan.example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let outbound = ProxyOutbound(node: makeTrojanNode(tls: tls), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.tls, tls)
        XCTAssertEqual(tlsChild.requests.first?.metadata["proxyProtocol"], "trojan")
        XCTAssertEqual(tlsChild.requests.first?.metadata["trojanPasswordPresent"], "true")
        XCTAssertNil(tlsChild.requests.first?.metadata["trojanPassword"])
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

private func proxyResult(packetID: String) -> PacketProcessingResult {
    var processor = PacketProcessor(configuration: TunnelRuntimeConfiguration(snapshot: snapshot(tls: .disabled), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32))
    let packet = Packet.ipv4TCP(id: packetID, source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
    return processor.process(packet)
}

private func snapshot(tls: TLSOptions) -> RuntimeSnapshot {
    RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: makeNode(tls: tls), routeMode: .globalProxy, logLevel: .user)
}

private func makeNode(tls: TLSOptions) -> ProxyNode {
    ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .shadowsocks, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "aes-256-gcm:pass"), transport: .tcp, tls: tls, udpPolicy: .disabled)
}

private func makeVMessNode(tls: TLSOptions) -> ProxyNode {
    ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .vmess, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "00000000-0000-0000-0000-000000000001"), transport: .tcp, tls: tls, udpPolicy: .disabled)
}

private func makeVLESSNode(tls: TLSOptions) -> ProxyNode {
    ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .vless, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "00000000-0000-0000-0000-000000000002"), transport: .tcp, tls: tls, udpPolicy: .disabled)
}

private func makeTrojanNode(tls: TLSOptions) -> ProxyNode {
    ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "secret-password"), transport: .tcp, tls: tls, udpPolicy: .disabled)
}

private func makeHysteria2Node() -> ProxyNode {
    let tls = TLSOptions(enabled: true, serverName: "hysteria.example.com", allowInsecure: false, alpn: ["h3"], fingerprint: nil, reality: nil)
    return ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .hysteria2, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "hysteria-secret"), transport: .quic, tls: tls, udpPolicy: .disabled)
}

private func makeTUICNode() -> ProxyNode {
    let tls = TLSOptions(enabled: true, serverName: "tuic.example.com", allowInsecure: false, alpn: ["h3"], fingerprint: nil, reality: nil)
    return ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .tuic, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "00000000-0000-0000-0000-000000000003:tuic-password"), transport: .quic, tls: tls, udpPolicy: .disabled)
}
