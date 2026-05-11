import XCTest
import IrockCore
import IrockProtocols
import IrockStorage
import IrockTransport
@testable import IrockTunnelCore

final class PacketFlowRuntimeIOTests: XCTestCase {
    func testBootstrappedRuntimePublishesFailureWhenPacketFlowReadFails() async throws {
        let io = PacketFlowRuntimeIO(flow: FailingReadPacketFlowIO(error: PacketFlowTestError.readFailed), batchLimit: 16)
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: packetFlowSnapshot(tls: .disabled),
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: PacketFlowRecordingTransportAdapter(transport: .tcp),
            tls: PacketFlowRecordingTransportAdapter(transport: .tcp),
            batchLimit: 16,
            flowLimit: 32
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected packet flow read failure")
        } catch PacketFlowTestError.readFailed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet flow read failure, got \(error)")
        }
    }

    func testBootstrappedRuntimePublishesFailureWhenPacketFlowWriteFails() async throws {
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = FailingWritePacketFlowIO(packets: [packet], error: PacketFlowTestError.writeFailed)
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: 16)
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: packetFlowSnapshot(tls: .disabled),
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: PacketFlowRecordingTransportAdapter(transport: .tcp),
            tls: PacketFlowRecordingTransportAdapter(transport: .tcp),
            batchLimit: 16,
            flowLimit: 32
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected packet flow write failure")
        } catch PacketFlowTestError.writeFailed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet flow write failure, got \(error)")
        }
    }

    func testBootstrappedRuntimeUsesPacketFlowIOForReadAndWrite() async throws {
        let plain = PacketFlowRecordingTransportAdapter(transport: .tcp)
        let tlsChild = PacketFlowRecordingTransportAdapter(transport: .tcp)
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = RecordingPacketFlowIO(packets: [packet])
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: 16)
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: packetFlowSnapshot(tls: .disabled),
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tlsChild,
            batchLimit: 16,
            flowLimit: 32
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.dropCount, 0)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(flow.readLimits, [16])
        XCTAssertEqual(flow.writtenResults.count, 1)
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(tlsChild.requests, [])
        let status = try XCTUnwrap(statusStore.load())
        XCTAssertEqual(status.phase, .connected)
        XCTAssertEqual(status.message, "Packet batch processed")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
    }

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

private final class PacketFlowRecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
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
    }

    private func record(_ request: TransportRequest) -> any TransportConnection {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(request)
        return EstablishedTransportConnection(host: request.host, port: request.port, transport: request.transport)
    }
}

private enum PacketFlowTestError: Error {
    case readFailed
    case writeFailed
}

private struct FailingReadPacketFlowIO: PacketFlowIO {
    let error: PacketFlowTestError

    func readPackets(limit: Int) async throws -> [Packet] {
        throw error
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {}
}

private struct FailingWritePacketFlowIO: PacketFlowIO {
    let packets: [Packet]
    let error: PacketFlowTestError

    func readPackets(limit: Int) async throws -> [Packet] {
        Array(packets.prefix(limit))
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        throw error
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
