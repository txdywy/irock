import XCTest
import IrockCore
import IrockProtocols
import IrockRouting
import IrockStorage
import IrockTransport
@testable import IrockTunnelCore

final class RuntimeProxyStackTests: XCTestCase {
    func testShadowsocksTCPStackRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tlsChild)
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
        let registry = RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tlsChild)
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
