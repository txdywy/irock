import XCTest
import IrockCore
import IrockStorage
import IrockTransport
@testable import IrockTunnelCore

final class TunnelRuntimeControllerTests: XCTestCase {
    func testRunShadowsocksTCPBatchIgnoresReporterFailuresWhenSnapshotIsMissing() async throws {
        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: InMemoryRuntimeSnapshotStore(),
                flow: ControllerRecordingPacketFlowIO(packets: []),
                statusStore: ControllerFailingRuntimeStatusStore(),
                logStore: ControllerFailingRuntimeLogStore(),
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                credentialResolver: TestShadowsocksCredentialResolver(),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected missing runtime snapshot")
        } catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
        } catch {
            XCTFail("Expected missing runtime snapshot, got \(error)")
        }
    }

    func testRunShadowsocksTCPBatchPropagatesInvalidRoutingManifest() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: nil, action: .direct)]
        )
        try snapshotStore.save(controllerSnapshot(tls: .disabled, routingRuleManifest: manifest))
        let flow = ControllerRecordingPacketFlowIO(packets: [])

        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: snapshotStore,
                flow: flow,
                statusStore: InMemoryRuntimeStatusStore(),
                logStore: InMemoryRuntimeLogStore(),
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                credentialResolver: TestShadowsocksCredentialResolver(),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected invalid routing manifest")
        } catch let error as RuntimeRoutingRuleAdapterError {
            XCTAssertEqual(error, .missingValue(kind: .domainSuffix))
            XCTAssertEqual(flow.readLimits, [])
            XCTAssertEqual(flow.writtenResults, [])
        } catch {
            XCTFail("Expected invalid routing manifest, got \(error)")
        }
    }

    func testRunShadowsocksTCPBatchPropagatesPacketFlowReadFailure() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerSnapshot(tls: .disabled))
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()

        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: snapshotStore,
                flow: ControllerFailingReadPacketFlowIO(error: ControllerPacketFlowTestError.readFailed),
                statusStore: statusStore,
                logStore: logStore,
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                credentialResolver: TestShadowsocksCredentialResolver(),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected packet flow read failure")
        } catch ControllerPacketFlowTestError.readFailed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet flow read failure, got \(error)")
        }
    }

    func testRunShadowsocksTCPBatchPropagatesPacketFlowWriteFailure() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerSnapshot(tls: .disabled))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()

        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: snapshotStore,
                flow: ControllerFailingWritePacketFlowIO(packets: [packet], error: ControllerPacketFlowTestError.writeFailed),
                statusStore: statusStore,
                logStore: logStore,
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                credentialResolver: TestShadowsocksCredentialResolver(),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected packet flow write failure")
        } catch ControllerPacketFlowTestError.writeFailed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet flow write failure, got \(error)")
        }
    }

    func testRunShadowsocksTCPBatchReportsMissingSnapshot() async throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()

        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: InMemoryRuntimeSnapshotStore(),
                flow: ControllerRecordingPacketFlowIO(packets: []),
                statusStore: statusStore,
                logStore: logStore,
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                credentialResolver: TestShadowsocksCredentialResolver(),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected missing runtime snapshot")
        } catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertNil(status.selectedNodeID)
            XCTAssertNil(status.selectedNodeName)
            XCTAssertEqual(status.message, "Runtime snapshot unavailable")
            let logs = try logStore.loadRecent()
            XCTAssertEqual(logs.map(\.message), ["Runtime snapshot unavailable"])
            XCTAssertEqual(logs.map(\.level), [.user])
            XCTAssertEqual(logs.map(\.nodeID), [nil])
            XCTAssertEqual(logs.map(\.phase), [.failed])
        } catch {
            XCTFail("Expected missing runtime snapshot, got \(error)")
        }
    }

    func testRunShadowsocksTCPBatchLoadsSnapshotAndRunsPacketFlowBatch() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerSnapshot(tls: .disabled))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = ControllerRecordingPacketFlowIO(packets: [packet])
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let plain = ControllerRecordingTransportAdapter(transport: .tcp)
        let tlsChild = ControllerRecordingTransportAdapter(transport: .tcp)

        let summary = try await TunnelRuntimeController.runShadowsocksTCPBatch(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tlsChild,
            credentialResolver: TestShadowsocksCredentialResolver(),
            batchLimit: 16,
            flowLimit: 32
        )

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
        XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(status.selectedNodeName, "Demo")
        XCTAssertEqual(status.message, "Packet batch processed")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
    }
}

private final class ControllerRecordingPacketFlowIO: PacketFlowIO, @unchecked Sendable {
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

private final class ControllerRecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
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

private enum ControllerPacketFlowTestError: Error {
    case readFailed
    case writeFailed
}

private enum ControllerRuntimeStoreError: Error {
    case failed
}

private struct ControllerFailingReadPacketFlowIO: PacketFlowIO {
    let error: ControllerPacketFlowTestError

    func readPackets(limit: Int) async throws -> [Packet] {
        throw error
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {}
}

private struct ControllerFailingWritePacketFlowIO: PacketFlowIO {
    let packets: [Packet]
    let error: ControllerPacketFlowTestError

    func readPackets(limit: Int) async throws -> [Packet] {
        Array(packets.prefix(limit))
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        throw error
    }
}

private final class ControllerFailingRuntimeStatusStore: RuntimeStatusStore, @unchecked Sendable {
    func save(_ status: RuntimeConnectionStatus) throws {
        throw ControllerRuntimeStoreError.failed
    }

    func load() throws -> RuntimeConnectionStatus? {
        nil
    }
}

private final class ControllerFailingRuntimeLogStore: RuntimeLogStore, @unchecked Sendable {
    func append(_ entry: RuntimeLogEntry) throws {
        throw ControllerRuntimeStoreError.failed
    }

    func loadRecent() throws -> [RuntimeLogEntry] {
        []
    }

    func clear() throws {}
}

private func controllerSnapshot(tls: TLSOptions, routingRuleManifest: RuntimeRoutingRuleManifest = RuntimeRoutingRuleManifest(version: 1, rules: [RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)])) -> RuntimeSnapshot {
    RuntimeSnapshot(
        id: SnapshotID(rawValue: "snapshot-1"),
        selectedNode: ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo",
            protocolType: .shadowsocks,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "aes-256-gcm:pass"),
            transport: .tcp,
            tls: tls,
            udpPolicy: .disabled
        ),
        routeMode: .globalProxy,
        logLevel: .user,
        routingRuleManifest: routingRuleManifest
    )
}
