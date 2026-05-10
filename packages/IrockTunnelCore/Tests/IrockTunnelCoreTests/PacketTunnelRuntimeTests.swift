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

    func testRuntimeIgnoresReporterFailuresBeforePacketProcessing() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
        let writer = InMemoryPacketWriter()
        let reporter = TunnelRuntimeReporter(statusStore: FailingRuntimeStatusStore(), logStore: FailingRuntimeLogStore())
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32),
            reporter: reporter
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(writer.writtenResults.count, 1)
    }

    func testRuntimeIgnoresReporterFailuresAfterPacketWrite() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
        let writer = InMemoryPacketWriter()
        let reporter = TunnelRuntimeReporter(statusStore: FailingAfterFirstSaveRuntimeStatusStore(), logStore: FailingAfterFirstAppendRuntimeLogStore())
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32),
            reporter: reporter
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(writer.writtenResults.count, 1)
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

private enum FailingRuntimeStoreError: Error {
    case failed
}

private final class FailingRuntimeStatusStore: RuntimeStatusStore, @unchecked Sendable {
    func save(_ status: RuntimeConnectionStatus) throws {
        throw FailingRuntimeStoreError.failed
    }

    func load() throws -> RuntimeConnectionStatus? {
        nil
    }
}

private final class FailingRuntimeLogStore: RuntimeLogStore, @unchecked Sendable {
    func append(_ entry: RuntimeLogEntry) throws {
        throw FailingRuntimeStoreError.failed
    }

    func loadRecent() throws -> [RuntimeLogEntry] {
        []
    }

    func clear() throws {}
}

private final class FailingAfterFirstSaveRuntimeStatusStore: RuntimeStatusStore, @unchecked Sendable {
    private let lock = NSLock()
    private var saveCount = 0

    func save(_ status: RuntimeConnectionStatus) throws {
        lock.lock()
        defer { lock.unlock() }

        saveCount += 1
        if saveCount > 1 {
            throw FailingRuntimeStoreError.failed
        }
    }

    func load() throws -> RuntimeConnectionStatus? {
        nil
    }
}

private final class FailingAfterFirstAppendRuntimeLogStore: RuntimeLogStore, @unchecked Sendable {
    private let lock = NSLock()
    private var appendCount = 0

    func append(_ entry: RuntimeLogEntry) throws {
        lock.lock()
        defer { lock.unlock() }

        appendCount += 1
        if appendCount > 1 {
            throw FailingRuntimeStoreError.failed
        }
    }

    func loadRecent() throws -> [RuntimeLogEntry] {
        []
    }

    func clear() throws {}
}
