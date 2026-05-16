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
            credentialResolver: TestShadowsocksCredentialResolver(credential: "aes-256-gcm:pass"),
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

    func testTUICQUICConfigurationWiresInjectedSessionDialerIntoPacketTunnelRuntime() async throws {
        let token = Data((0..<32).map(UInt8.init))
        let uniStream = RecordingRuntimeByteStream()
        let bidiStream = RecordingRuntimeByteStream()
        let session = RecordingRuntimeTUICQUICSession(exportedToken: token, bidirectionalStream: bidiStream, unidirectionalStream: uniStream)
        let dialer = RecordingRuntimeTUICQUICSessionDialer(session: session)
        let reader = InMemoryPacketReader(packets: [Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)])
        let writer = InMemoryPacketWriter()
        let configuration = TunnelRuntimeConfiguration.tuicQUIC(
            snapshot: RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: makeTUICNode(), routeMode: .globalProxy, logLevel: .user),
            routingEngine: RoutingEngine(rules: [.final(.proxy)]),
            sessionDialer: dialer,
            credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000003:tuic-password"),
            batchLimit: 16,
            flowLimit: 32
        )
        let runtime = PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration)

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(dialer.requests.count, 1)
        XCTAssertEqual(session.exports.count, 1)
        XCTAssertEqual(uniStream.writes, [Data([0x05, 0x00]) + Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3]) + token])
        XCTAssertEqual(bidiStream.writes, [Data([0x05, 0x01, 0x01, 93, 184, 216, 34, 0x01, 0xbb])])
        XCTAssertEqual(writer.writtenResults.count, 1)
    }

    func testVMessGRPCConfigurationWiresStackIntoPacketTunnelRuntime() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let reader = InMemoryPacketReader(packets: [Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)])
        let writer = InMemoryPacketWriter()
        let configuration = TunnelRuntimeConfiguration.vmessGRPC(
            snapshot: RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: makeVMessGRPCNode(), routeMode: .globalProxy, logLevel: .user),
            routingEngine: RoutingEngine(rules: [.final(.proxy)]),
            plain: plain,
            tls: tlsChild,
            credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000001"),
            batchLimit: 16,
            flowLimit: 32
        )
        let runtime = PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration)

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.transport, .tcp)
        XCTAssertEqual(tlsChild.requests.first?.metadata["grpcProtocol"], "vmess")
        XCTAssertEqual(tlsChild.requests.first?.metadata["grpcService"], "/TunnelService/Connect")
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
            credentialResolver: TestShadowsocksCredentialResolver(credential: "aes-256-gcm:pass"),
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
        let registry = RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tlsChild, credentialResolver: TestShadowsocksCredentialResolver(credential: "aes-256-gcm:pass"))
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
        let registry = RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tlsChild, credentialResolver: TestShadowsocksCredentialResolver(credential: "aes-256-gcm:pass"))
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
        let registry = RuntimeProxyStack.vmessTCP(plain: plain, tls: tlsChild, credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000001"))
        let outbound = ProxyOutbound(node: makeVMessNode(tls: .disabled), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "vmess")
        XCTAssertEqual(plain.requests.first?.metadata["vmessUserIDPresent"], "true")
        XCTAssertNil(plain.requests.first?.metadata["vmessUserID"])
        XCTAssertFalse(plain.requests.first?.metadata.values.contains("node-1") == true)
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testVMessTCPStackRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.vmessTCP(plain: plain, tls: tlsChild, credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000001"))
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
        XCTAssertFalse(tlsChild.requests.first?.metadata.values.contains("node-1") == true)
    }

    func testVMessGRPCStackRoutesThroughGRPCTransportOverTLS() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.vmessGRPC(plain: plain, tls: tlsChild, credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000001"))
        let outbound = ProxyOutbound(node: makeVMessGRPCNode(), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection?.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(connection?.initialResponseBytes, nil)
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.host, "example.com")
        XCTAssertEqual(tlsChild.requests.first?.port, 443)
        XCTAssertEqual(tlsChild.requests.first?.transport, .tcp)
        XCTAssertEqual(tlsChild.requests.first?.tls, makeVMessGRPCNode().tls)
        XCTAssertEqual(tlsChild.requests.first?.metadata["grpcAuthority"], "edge.example.com")
        XCTAssertEqual(tlsChild.requests.first?.metadata["grpcService"], "/TunnelService/Connect")
        XCTAssertEqual(tlsChild.requests.first?.metadata["grpcProtocol"], "vmess")
        XCTAssertEqual(tlsChild.requests.first?.metadata["grpcUpgrade"], "true")
        let opened = tlsChild.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(opened.starts(with: Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("grpc-authority:edge.example.com\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("grpc-service:/TunnelService/Connect\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data("grpc-protocol:vmess\n".utf8)))
        XCTAssertNotNil(opened.range(of: Data([0x00, 0x00, 0x00, 0x00])))
        XCTAssertFalse(opened.contains(Data("00000000-0000-0000-0000-000000000001".utf8)))
        XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("grpc-foundation") == true)
    }

    func testVMessGRPCStreamStackRetainsStreamForRuntimePayloadWrites() async throws {
        let stream = RecordingRuntimeByteStream()
        let streamAdapter = RecordingRuntimeTransportStreamAdapter(transport: .tcp, stream: stream)
        let registry = RuntimeProxyStack.vmessGRPC(stream: streamAdapter, credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000001"))
        let outbound = ProxyOutbound(node: makeVMessGRPCNode(), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)
        _ = try await connection?.writePayload([0xde, 0xad])

        XCTAssertEqual(streamAdapter.requests.count, 1)
        XCTAssertEqual(streamAdapter.requests.first?.transport, .tcp)
        XCTAssertEqual(streamAdapter.requests.first?.tls, makeVMessGRPCNode().tls)
        XCTAssertTrue(stream.writes.reduce(Data(), +).contains(Data([0x00, 0x00, 0x00, 0x00, 0x02, 0xde, 0xad])))
    }

    func testVLESSTCPStackRoutesDisabledTLSToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.vlessTCP(plain: plain, tls: tlsChild, credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000002"))
        let outbound = ProxyOutbound(node: makeVLESSNode(tls: .disabled), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "vless")
        XCTAssertEqual(plain.requests.first?.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(plain.requests.first?.metadata["vlessUserID"])
        XCTAssertFalse(plain.requests.first?.metadata.values.contains("node-1") == true)
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testVLESSTCPStackRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.vlessTCP(plain: plain, tls: tlsChild, credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000002"))
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
        XCTAssertFalse(tlsChild.requests.first?.metadata.values.contains("node-1") == true)
    }

    func testVLESSRealityTCPStackRoutesThroughRealityAdapter() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let publicKey = "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"
        let reality = RealityOptions(publicKey: publicKey, shortID: "abc123", spiderX: "/")
        let tls = TLSOptions(enabled: true, serverName: "reality.example.com", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: reality)
        let registry = RuntimeProxyStack.vlessRealityTCP(plain: plain, credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000002"))
        let outbound = ProxyOutbound(node: makeVLESSNode(tls: tls), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "vless")
        XCTAssertEqual(plain.requests.first?.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(plain.requests.first?.metadata["vlessUserID"])
        XCTAssertFalse(plain.requests.first?.metadata.values.contains("node-1") == true)
        XCTAssertEqual(plain.requests.first?.metadata["realityServerName"], "reality.example.com")
        XCTAssertEqual(plain.requests.first?.metadata["realityPublicKeyPresent"], "true")
        XCTAssertEqual(plain.requests.first?.metadata["realityShortIDPresent"], "true")
        let payload = plain.requests.first?.initialPayload ?? Data()
        XCTAssertTrue(payload.starts(with: Data([0x49, 0x52, 0x4c, 0x52, 0x01])))
        XCTAssertNotNil(payload.range(of: Data([0x01, UInt8("reality.example.com".utf8.count)]) + Data("reality.example.com".utf8)))
        XCTAssertNotNil(payload.range(of: Data([0x02, 0x01, 0x01])))
        XCTAssertFalse(String(data: payload, encoding: .utf8)?.contains("reality-foundation") == true)
        XCTAssertFalse(payload.contains(Data(publicKey.utf8)))
        XCTAssertFalse(payload.contains(Data("00000000-0000-0000-0000-000000000002".utf8)))
    }

    func testHysteria2QUICStackRoutesThroughQUICTransport() async throws {
        let quic = RecordingTransportAdapter(transport: .quic)
        let registry = RuntimeProxyStack.hysteria2QUIC(quic: quic, credentialResolver: TestProxyCredentialResolver(credential: "hysteria-secret"))
        let outbound = ProxyOutbound(node: makeHysteria2Node(), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(quic.requests.count, 1)
        XCTAssertEqual(quic.requests.first?.transport, .quic)
        XCTAssertEqual(quic.requests.first?.metadata["proxyProtocol"], "hysteria2")
        XCTAssertEqual(quic.requests.first?.metadata["hysteria2AuthPresent"], "true")
        XCTAssertEqual(quic.requests.first?.metadata["hysteria2Destination"], "ipv4:93.184.216.34:443")
        XCTAssertFalse(quic.requests.first?.metadata.values.contains("node-1") == true)
        let payload = quic.requests.first?.initialPayload ?? Data()
        XCTAssertFalse(payload.contains(Data("hysteria-secret".utf8)))
    }

    func testTUICQUICStackRejectsConnectUntilRuntimeSessionDialerIsInjected() async throws {
        let quic = RecordingTransportAdapter(transport: .quic)
        let registry = RuntimeProxyStack.tuicQUIC(quic: quic, credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000003:tuic-password"))
        let outbound = ProxyOutbound(node: makeTUICNode(), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        do {
            _ = try await outbound.connect(result: result)
            XCTFail("Expected TUIC exporter authentication failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("tuic tls exporter authentication unavailable"))
            XCTAssertEqual(quic.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTUICQUICStackRoutesThroughInjectedSessionDialer() async throws {
        let token = Data((0..<32).map(UInt8.init))
        let uniStream = RecordingRuntimeByteStream()
        let bidiStream = RecordingRuntimeByteStream()
        let session = RecordingRuntimeTUICQUICSession(exportedToken: token, bidirectionalStream: bidiStream, unidirectionalStream: uniStream)
        let dialer = RecordingRuntimeTUICQUICSessionDialer(session: session)
        let registry = RuntimeProxyStack.tuicQUIC(sessionDialer: dialer, credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000003:tuic-password"))
        let outbound = ProxyOutbound(node: makeTUICNode(), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection?.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(dialer.requests.count, 1)
        XCTAssertEqual(dialer.requests.first?.host, "example.com")
        XCTAssertEqual(dialer.requests.first?.port, 443)
        XCTAssertEqual(dialer.requests.first?.tls, makeTUICNode().tls)
        XCTAssertEqual(dialer.requests.first?.metadata["packetID"], "tcp-1")
        XCTAssertEqual(dialer.requests.first?.metadata["proxyProtocol"], "tuic")
        XCTAssertEqual(dialer.requests.first?.metadata["quicServerName"], "tuic.example.com")
        XCTAssertEqual(dialer.requests.first?.metadata["quicProtocol"], "tuic")
        XCTAssertEqual(dialer.requests.first?.metadata["quicALPN"], "h3")
        XCTAssertFalse(dialer.requests.first?.metadata.values.contains("tuic-password") == true)
        XCTAssertEqual(session.exports.count, 1)
        XCTAssertEqual(session.exports.first?.label, Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3]))
        XCTAssertEqual(session.exports.first?.context, Data("tuic-password".utf8))
        XCTAssertEqual(session.exports.first?.length, 32)
        XCTAssertEqual(session.unidirectionalPayloads, [Data()])
        XCTAssertEqual(session.bidirectionalPayloads, [Data()])
        XCTAssertEqual(uniStream.writes, [Data([0x05, 0x00]) + Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3]) + token])
        XCTAssertEqual(bidiStream.writes, [Data([0x05, 0x01, 0x01, 93, 184, 216, 34, 0x01, 0xbb])])
    }

    func testTrojanTCPStackRoutesDisabledTLSToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.trojanTCP(plain: plain, tls: tlsChild, credentialResolver: TestProxyCredentialResolver(credential: "secret-password"))
        let outbound = ProxyOutbound(node: makeTrojanNode(tls: .disabled), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "trojan")
        XCTAssertEqual(plain.requests.first?.metadata["trojanPasswordPresent"], "true")
        XCTAssertNil(plain.requests.first?.metadata["trojanPassword"])
        XCTAssertFalse(plain.requests.first?.metadata.values.contains("node-1") == true)
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testTrojanTCPStackRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.trojanTCP(plain: plain, tls: tlsChild, credentialResolver: TestProxyCredentialResolver(credential: "secret-password"))
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
        XCTAssertFalse(tlsChild.requests.first?.metadata.values.contains("node-1") == true)
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

private final class RecordingRuntimeTransportStreamAdapter: TransportStreamAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    private let stream: RecordingRuntimeByteStream
    private var storedRequests: [TransportRequest] = []

    init(transport: TransportType, stream: RecordingRuntimeByteStream) {
        self.supportedTransport = transport
        self.stream = stream
    }

    var requests: [TransportRequest] { storedRequests }

    func openStream(request: TransportRequest) async throws -> any TransportByteStream {
        storedRequests.append(request)
        return stream
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

private struct RuntimeTUICExporterRequest: Equatable {
    let label: Data
    let context: Data
    let length: Int
}

private struct RuntimeTUICSessionDialRequest: Equatable {
    let host: String
    let port: Int
    let tls: TLSOptions?
    let metadata: [String: String]
}

private final class RecordingRuntimeTUICQUICSessionDialer: TUICQUICSessionDialer, @unchecked Sendable {
    private let session: RecordingRuntimeTUICQUICSession
    private var storedRequests: [RuntimeTUICSessionDialRequest] = []

    init(session: RecordingRuntimeTUICQUICSession) {
        self.session = session
    }

    var requests: [RuntimeTUICSessionDialRequest] { storedRequests }

    func openSession(host: String, port: Int, tls: TLSOptions?, metadata: [String: String]) async throws -> any TUICQUICSession {
        storedRequests.append(RuntimeTUICSessionDialRequest(host: host, port: port, tls: tls, metadata: metadata))
        return session
    }
}

private final class RecordingRuntimeTUICQUICSession: TUICQUICSession, @unchecked Sendable {
    private let exportedToken: Data
    private let bidirectionalStream: RecordingRuntimeByteStream
    private let unidirectionalStream: RecordingRuntimeByteStream
    private var storedExports: [RuntimeTUICExporterRequest] = []
    private var storedBidirectionalPayloads: [Data] = []
    private var storedUnidirectionalPayloads: [Data] = []

    init(exportedToken: Data, bidirectionalStream: RecordingRuntimeByteStream, unidirectionalStream: RecordingRuntimeByteStream) {
        self.exportedToken = exportedToken
        self.bidirectionalStream = bidirectionalStream
        self.unidirectionalStream = unidirectionalStream
    }

    var exports: [RuntimeTUICExporterRequest] { storedExports }
    var bidirectionalPayloads: [Data] { storedBidirectionalPayloads }
    var unidirectionalPayloads: [Data] { storedUnidirectionalPayloads }

    func exportKeyingMaterial(label: Data, context: Data, length: Int) async throws -> Data {
        storedExports.append(RuntimeTUICExporterRequest(label: label, context: context, length: length))
        return exportedToken
    }

    func openUnidirectionalStream(initialPayload: Data) async throws -> any TransportByteStream {
        storedUnidirectionalPayloads.append(initialPayload)
        return unidirectionalStream
    }

    func openBidirectionalStream(initialPayload: Data) async throws -> any TransportByteStream {
        storedBidirectionalPayloads.append(initialPayload)
        return bidirectionalStream
    }
}

private final class RecordingRuntimeByteStream: TransportByteStream, @unchecked Sendable {
    private var storedWrites: [Data] = []

    var writes: [Data] { storedWrites }

    func read(maxLength: Int) async throws -> Data? { nil }

    func write(_ data: Data) async throws {
        storedWrites.append(data)
    }

    func closeWrite() async {}
    func close() async {}
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
    ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .shadowsocks, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: tls, udpPolicy: .disabled)
}

private func makeVMessNode(tls: TLSOptions) -> ProxyNode {
    ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .vmess, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: tls, udpPolicy: .disabled)
}

private func makeVMessGRPCNode() -> ProxyNode {
    let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
    return ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .vmess, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .grpc, transportOptions: TransportOptions(grpc: GRPCTransportOptions(authority: "edge.example.com", service: "/TunnelService/Connect")), tls: tls, udpPolicy: .disabled)
}

private func makeVLESSNode(tls: TLSOptions) -> ProxyNode {
    ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .vless, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: tls, udpPolicy: .disabled)
}

private func makeTrojanNode(tls: TLSOptions) -> ProxyNode {
    ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: tls, udpPolicy: .disabled)
}

private func makeHysteria2Node() -> ProxyNode {
    let tls = TLSOptions(enabled: true, serverName: "hysteria.example.com", allowInsecure: false, alpn: ["h3"], fingerprint: nil, reality: nil)
    return ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .hysteria2, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .quic, tls: tls, udpPolicy: .disabled)
}

private func makeTUICNode() -> ProxyNode {
    let tls = TLSOptions(enabled: true, serverName: "tuic.example.com", allowInsecure: false, alpn: ["h3"], fingerprint: nil, reality: nil)
    return ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .tuic, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .quic, tls: tls, udpPolicy: .disabled)
}
