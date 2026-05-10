import XCTest
import IrockCore
import IrockRouting
import IrockStorage
@testable import IrockTunnelCore

final class PacketTunnelRuntimeTests: XCTestCase {
    func testRuntimeReadsProcessesAndWritesBatch() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let malformedPacket = Packet(id: "bad", bytes: [0x45])
        let reader = InMemoryPacketReader(packets: [validPacket, malformedPacket])
        let writer = InMemoryPacketWriter()
        let runtime = PacketTunnelRuntime(reader: reader, writer: writer, configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32))

        let summary = try await runtime.runOnce()

        let flowKey = FlowKey(sourceIP: .v4(10, 0, 0, 2), sourcePort: 51_234, destinationIP: .v4(93, 184, 216, 34), destinationPort: 443, transportProtocol: .tcp)
        XCTAssertEqual(summary.readCount, 2)
        XCTAssertEqual(summary.writtenCount, 2)
        XCTAssertEqual(summary.dropCount, 1)
        XCTAssertEqual(writer.writtenResults.map(\.action), [.proxy(flowKey), .drop(.parseFailed(.tooShort))])
    }

    func testRuntimePublishesPreparingAndConnectedStatus() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
        let writer = InMemoryPacketWriter()
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32),
            reporter: reporter
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        let status = try XCTUnwrap(statusStore.load())
        XCTAssertEqual(status.phase, .connected)
        XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(status.selectedNodeName, "Demo")
        XCTAssertEqual(status.message, "Packet batch processed")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
    }

    private func snapshot(routeMode: RouteMode) -> RuntimeSnapshot {
        RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled),
            routeMode: routeMode,
            logLevel: .user
        )
    }
}
