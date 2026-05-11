import XCTest
import IrockCore
import IrockProtocols
import IrockRouting
@testable import IrockTunnelCore

final class ProxyOutboundTests: XCTestCase {
    func testConnectBuildsIPv4ProxyRequestFromProxyResult() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let outbound = ProxyOutbound(node: makeNode(protocolType: .trojan), registry: ProxyAdapterRegistry(adapters: [adapter]))
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let result = processor.process(packet)

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection?.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(adapter.requests.map(\.node.id), [NodeID(rawValue: "node-1")])
        XCTAssertEqual(adapter.requests.map(\.destination), [.ipv4("93.184.216.34", port: 443)])
        XCTAssertEqual(adapter.requests.first?.metadata["packetID"], "tcp-1")
        XCTAssertEqual(adapter.requests.first?.metadata["transportProtocol"], "tcp")
    }

    func testConnectBuildsIPv6ProxyRequestFromParsedProxyResult() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let outbound = ProxyOutbound(node: makeNode(protocolType: .trojan), registry: ProxyAdapterRegistry(adapters: [adapter]))
        let packet = Packet(id: "tcp-6", bytes: [])
        let parsed = ParsedPacket(
            packet: packet,
            sourceIP: .v6("2001:db8::1"),
            destinationIP: .v6("2606:2800:220:1:248:1893:25c8:1946"),
            transportProtocol: .tcp,
            sourcePort: 51_234,
            destinationPort: 443,
            isDNSCandidate: false
        )
        let flowKey = FlowKey(sourceIP: parsed.sourceIP, sourcePort: parsed.sourcePort, destinationIP: parsed.destinationIP, destinationPort: parsed.destinationPort, transportProtocol: parsed.transportProtocol)
        let result = PacketProcessingResult(packet: packet, parsedPacket: parsed, flowKey: flowKey, action: .proxy(flowKey))

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.destination, .ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443))
        XCTAssertEqual(adapter.requests.map(\.destination), [.ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443)])
    }

    func testConnectThrowsUDPUunsupportedWhenNodeDisablesUDPWithoutCallingAdapter() async {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let outbound = ProxyOutbound(node: makeNode(protocolType: .trojan), registry: ProxyAdapterRegistry(adapters: [adapter]))
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy))
        let packet = Packet.ipv4UDP(id: "udp-1", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 55_555, destinationPort: 53)
        let result = processor.process(packet)

        do {
            _ = try await outbound.connect(result: result)
            XCTFail("Expected UDP unsupported")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .udpUnsupported)
            XCTAssertEqual(adapter.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectReturnsNilForNonProxyResults() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let outbound = ProxyOutbound(node: makeNode(protocolType: .trojan), registry: ProxyAdapterRegistry(adapters: [adapter]))
        var processor = PacketProcessor(configuration: configuration(routeMode: .direct))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let result = processor.process(packet)

        let connection = try await outbound.connect(result: result)

        XCTAssertNil(connection)
        XCTAssertEqual(adapter.requests, [])
    }

    private func configuration(routeMode: RouteMode) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(snapshot: RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: makeNode(protocolType: .trojan), routeMode: routeMode, logLevel: .user), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32)
    }

    private func makeNode(protocolType: ProxyProtocolType) -> ProxyNode {
        ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: protocolType, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled)
    }
}

private final class RecordingProxyAdapter: ProxyAdapter, @unchecked Sendable {
    let supportedProtocol: ProxyProtocolType
    private let lock = NSLock()
    private var storedRequests: [ProxyRequest] = []

    var requests: [ProxyRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    init(protocolType: ProxyProtocolType) {
        self.supportedProtocol = protocolType
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        record(request)
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func record(_ request: ProxyRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(request)
    }
}
