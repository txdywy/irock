import XCTest
import IrockCore
import IrockRouting
@testable import IrockTunnelCore

final class PacketProcessorTests: XCTestCase {
    func testGlobalProxyModeReturnsProxyAction() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.reject)]))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)

        let result = processor.process(packet)

        XCTAssertEqual(result.action, .proxy(FlowKey(sourceIP: .v4(10, 0, 0, 2), sourcePort: 51_234, destinationIP: .v4(93, 184, 216, 34), destinationPort: 443, transportProtocol: .tcp)))
    }

    func testDirectModeReturnsDirectAction() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .direct, rules: [.final(.reject)]))
        let packet = Packet.ipv4UDP(id: "udp-1", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 55_555, destinationPort: 53)

        let result = processor.process(packet)

        XCTAssertEqual(result.action, .direct(udpFlowKey()))
        XCTAssertEqual(result.parsedPacket?.isDNSCandidate, true)
    }

    func testRuleBasedModeReturnsRejectFromRoutingEngine() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .ruleBased, rules: [.final(.reject)]))
        let packet = Packet.ipv4TCP(id: "tcp-2", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)

        let result = processor.process(packet)

        XCTAssertEqual(result.action, .reject(FlowKey(sourceIP: .v4(10, 0, 0, 2), sourcePort: 51_234, destinationIP: .v4(93, 184, 216, 34), destinationPort: 443, transportProtocol: .tcp)))
    }

    func testUDPForwardingDecisionReturnsDirectForUDPDirectResult() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .direct, rules: [.final(.reject)]))
        let packet = Packet.ipv4UDP(id: "udp-direct", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 55_555, destinationPort: 53)

        let result = processor.process(packet)

        XCTAssertEqual(result.udpForwardingDecision(udpPolicy: .disabled), .direct(udpFlowKey()))
    }

    func testUDPForwardingDecisionReturnsProxyForUDPProxyResultWhenPolicyIsEnabled() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.reject)]))
        let packet = Packet.ipv4UDP(id: "udp-proxy", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 55_555, destinationPort: 53)

        let result = processor.process(packet)

        XCTAssertEqual(result.udpForwardingDecision(udpPolicy: .enabled), .proxy(udpFlowKey()))
    }

    func testUDPForwardingDecisionReturnsUnsupportedForUDPProxyResultWhenPolicyIsDisabled() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.reject)]))
        let packet = Packet.ipv4UDP(id: "udp-unsupported", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 55_555, destinationPort: 53)

        let result = processor.process(packet)

        XCTAssertEqual(result.udpForwardingDecision(udpPolicy: .disabled), .unsupported(udpFlowKey()))
    }

    func testUDPForwardingDecisionReturnsRejectForUDPRejectResult() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .ruleBased, rules: [.final(.reject)]))
        let packet = Packet.ipv4UDP(id: "udp-reject", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 55_555, destinationPort: 53)

        let result = processor.process(packet)

        XCTAssertEqual(result.udpForwardingDecision(udpPolicy: .enabled), .reject(udpFlowKey()))
    }

    func testUDPForwardingDecisionReturnsDropForMalformedPacket() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.proxy)]))

        let result = processor.process(Packet(id: "bad-udp", bytes: [0x45]))

        XCTAssertEqual(result.udpForwardingDecision(udpPolicy: .enabled), .drop(.parseFailed(.tooShort)))
    }

    func testUDPForwardingDecisionReturnsNilForTCPResult() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.reject)]))
        let packet = Packet.ipv4TCP(id: "tcp-no-udp", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)

        let result = processor.process(packet)

        XCTAssertNil(result.udpForwardingDecision(udpPolicy: .enabled))
    }

    func testPacketProcessingPerformanceEvidenceRecordsHotPathThroughput() {
        let packets = (0..<4_096).map { index in
            Packet.ipv4UDP(
                id: "udp-\(index)",
                source: .v4(10, 0, 0, UInt8(index % 255)),
                destination: .v4(1, 1, 1, 1),
                sourcePort: 50_000 + (index % 1_000),
                destinationPort: 53,
                payload: [0x01, 0x02, 0x03, 0x04]
            )
        }
        let evidence = PacketProcessingPerformanceEvidence.measure(
            packets: packets,
            configuration: configuration(routeMode: .direct, rules: [.final(.direct)], batchLimit: packets.count)
        )

        XCTAssertEqual(evidence.packetCount, 4_096)
        XCTAssertEqual(evidence.dropCount, 0)
        XCTAssertGreaterThan(evidence.packetsPerSecond, 10_000)
        XCTAssertLessThan(evidence.averageNanosecondsPerPacket, 1_000_000)
    }

    func testMalformedPacketDropsWithParseFailedReason() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.proxy)]))

        let result = processor.process(Packet(id: "bad", bytes: [0x45]))

        XCTAssertEqual(result.action, .drop(.parseFailed(.tooShort)))
    }

    func testUnsupportedProtocolDropsWithUnsupportedProtocolReason() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.proxy)]))
        var bytes = Packet.ipv4TCP(id: "icmp", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 1_000, destinationPort: 443).bytes
        bytes[9] = 1

        let result = processor.process(Packet(id: "icmp", bytes: bytes))

        XCTAssertEqual(result.action, .drop(.unsupportedProtocol))
    }

    private func udpFlowKey() -> FlowKey {
        FlowKey(sourceIP: .v4(10, 0, 0, 2), sourcePort: 55_555, destinationIP: .v4(1, 1, 1, 1), destinationPort: 53, transportProtocol: .udp)
    }

    private func configuration(routeMode: RouteMode, rules: [RoutingRule], batchLimit: Int = 16) -> TunnelRuntimeConfiguration {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled),
            routeMode: routeMode,
            logLevel: .user
        )
        return TunnelRuntimeConfiguration(snapshot: snapshot, routingEngine: RoutingEngine(rules: rules), batchLimit: batchLimit, flowLimit: batchLimit)
    }
}
