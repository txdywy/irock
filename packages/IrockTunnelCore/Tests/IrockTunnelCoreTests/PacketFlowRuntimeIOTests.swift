import XCTest
import IrockCore
import IrockProtocols
import IrockStorage
import IrockTransport
@testable import IrockTunnelCore

final class PacketFlowRuntimeIOTests: XCTestCase {
    func testReadBatchDelegatesToFlowWithConfiguredLimit() async throws {
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = RecordingPacketFlowIO(packets: [packet])
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: 7)

        let packets = try await io.readBatch()

        XCTAssertEqual(packets, [packet])
        XCTAssertEqual(flow.readLimits, [7])
    }

    func testWriteDelegatesResultsToFlow() async throws {
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        var processor = PacketProcessor(configuration: try TunnelRuntimeConfiguration(snapshot: packetFlowSnapshot(tls: .disabled), batchLimit: 16, flowLimit: 32))
        let result = processor.process(packet)
        let flow = RecordingPacketFlowIO(packets: [])
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: 7)

        try await io.write([result])

        XCTAssertEqual(flow.writtenResults, [result])
        XCTAssertEqual(flow.readLimits, [])
    }
}

private final class RecordingPacketFlowIO: PacketFlowIO, @unchecked Sendable {
    private let lock = NSLock()
    private let packets: [Packet]
    private var storedReadLimits: [Int] = []
    private var storedWrittenResults: [PacketProcessingResult] = []

    var readLimits: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storedReadLimits
    }

    var writtenResults: [PacketProcessingResult] {
        lock.lock()
        defer { lock.unlock() }
        return storedWrittenResults
    }

    init(packets: [Packet]) {
        self.packets = packets
    }

    func readPackets(limit: Int) async throws -> [Packet] {
        recordRead(limit: limit)
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        recordWrite(results)
    }

    private func recordRead(limit: Int) -> [Packet] {
        lock.lock()
        defer { lock.unlock() }
        storedReadLimits.append(limit)
        return Array(packets.prefix(limit))
    }

    private func recordWrite(_ results: [PacketProcessingResult]) {
        lock.lock()
        defer { lock.unlock() }
        storedWrittenResults.append(contentsOf: results)
    }
}

private func packetFlowSnapshot(tls: TLSOptions, routingRuleManifest: RuntimeRoutingRuleManifest = RuntimeRoutingRuleManifest(version: 1, rules: [RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)])) -> RuntimeSnapshot {
    RuntimeSnapshot(
        id: SnapshotID(rawValue: "snapshot-1"),
        selectedNode: ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo",
            protocolType: .shadowsocks,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: tls,
            udpPolicy: .disabled
        ),
        routeMode: .globalProxy,
        logLevel: .user,
        routingRuleManifest: routingRuleManifest
    )
}
