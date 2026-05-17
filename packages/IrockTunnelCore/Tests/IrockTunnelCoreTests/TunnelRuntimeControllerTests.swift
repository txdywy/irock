import XCTest
import IrockCore
import IrockProtocols
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

    func testRunShadowsocksTCPBatchReportsRuntimeStoreFailureWhenSnapshotLoadThrows() async throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()

        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: ControllerFailingLoadRuntimeSnapshotStore(),
                flow: ControllerRecordingPacketFlowIO(packets: []),
                statusStore: statusStore,
                logStore: logStore,
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                credentialResolver: TestShadowsocksCredentialResolver(),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected runtime store failure")
        } catch ControllerRuntimeStoreError.failed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertNil(status.selectedNodeID)
            XCTAssertNil(status.selectedNodeName)
            XCTAssertEqual(status.message, "Runtime store unavailable")
            let logs = try logStore.loadRecent()
            XCTAssertEqual(logs.map(\.message), ["Runtime store unavailable"])
            XCTAssertEqual(logs.map(\.phase), [.failed])
        } catch {
            XCTFail("Expected runtime store failure, got \(error)")
        }
    }

    func testRunVMessGRPCBatchLoadsSnapshotAndRunsPacketFlowBatch() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerVMessGRPCSnapshot())
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = ControllerRecordingPacketFlowIO(packets: [packet])
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let plain = ControllerRecordingTransportAdapter(transport: .tcp)
        let tlsChild = ControllerRecordingTransportAdapter(transport: .tcp)

        let summary = try await TunnelRuntimeController.runVMessGRPCBatch(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tlsChild,
            credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000001"),
            batchLimit: 16,
            flowLimit: 32
        )

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(flow.readLimits, [16])
        XCTAssertEqual(flow.writtenResults.count, 1)
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.metadata["grpcAuthority"], "edge.example.com")
        XCTAssertEqual(tlsChild.requests.first?.metadata["grpcService"], "/TunnelService/Connect")
        XCTAssertEqual(tlsChild.requests.first?.metadata["grpcProtocol"], "vmess")
        let status = try XCTUnwrap(statusStore.load())
        XCTAssertEqual(status.phase, .connected)
        XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(status.selectedNodeName, "VMess gRPC")
        XCTAssertEqual(status.message, "Packet batch processed")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
    }

    func testRunVMessGRPCBatchWithStreamAdapterUsesRetainedGRPCStream() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerVMessGRPCSnapshot())
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = ControllerRecordingPacketFlowIO(packets: [packet])
        let stream = ControllerRecordingByteStream()
        let streamAdapter = ControllerRecordingTransportStreamAdapter(transport: .tcp, stream: stream)

        let summary = try await TunnelRuntimeController.runVMessGRPCBatch(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: InMemoryRuntimeStatusStore(),
            logStore: InMemoryRuntimeLogStore(),
            stream: streamAdapter,
            credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000001"),
            batchLimit: 16,
            flowLimit: 32
        )

        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(streamAdapter.requests.count, 1)
        XCTAssertEqual(streamAdapter.requests.first?.transport, .tcp)
        XCTAssertEqual(streamAdapter.requests.first?.tls, controllerVMessGRPCSnapshot().selectedNode.tls)
        XCTAssertTrue(stream.writes.reduce(Data(), +).starts(with: Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))
    }

    func testRunTrustTunnelHTTP2BatchWithStreamAdapterUsesRetainedConnectStream() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerTrustTunnelHTTP2Snapshot())
        let packet = Packet.ipv4TCP(id: "tcp-tt", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = ControllerRecordingPacketFlowIO(packets: [packet])
        let responseHeaders = controllerHTTP2Frame(type: 0x01, flags: 0x04, streamID: 1, payload: Data([0x88]))
        let stream = ControllerRecordingByteStream(reads: [responseHeaders, nil])
        let streamAdapter = ControllerRecordingTransportStreamAdapter(transport: .tcp, stream: stream)
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()

        let summary = try await TunnelRuntimeController.runTrustTunnelHTTP2Batch(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            stream: streamAdapter,
            credentialResolver: TestProxyCredentialResolver(credential: "admin:trust-secret"),
            batchLimit: 16,
            flowLimit: 32
        )

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(streamAdapter.requests.count, 1)
        XCTAssertEqual(streamAdapter.requests.first?.transport, .tcp)
        XCTAssertEqual(streamAdapter.requests.first?.tls, controllerTrustTunnelHTTP2Snapshot().selectedNode.tls)
        let written = stream.writes.reduce(Data(), +)
        XCTAssertTrue(written.contains(Data("93.184.216.34:443".utf8)))
        XCTAssertTrue(written.contains(Data("Basic YWRtaW46dHJ1c3Qtc2VjcmV0".utf8)))
        let status = try XCTUnwrap(statusStore.load())
        XCTAssertEqual(status.phase, .connected)
        XCTAssertEqual(status.selectedNodeName, "TrustTunnel")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
    }

    func testRunTUICQUICBatchLoadsSnapshotAndRunsPacketFlowBatch() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerTUICSnapshot())
        let token = Data((0..<32).map(UInt8.init))
        let uniStream = ControllerRecordingByteStream()
        let bidiStream = ControllerRecordingByteStream()
        let session = ControllerRecordingTUICQUICSession(exportedToken: token, bidirectionalStream: bidiStream, unidirectionalStream: uniStream)
        let dialer = ControllerRecordingTUICQUICSessionDialer(session: session)
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = ControllerRecordingPacketFlowIO(packets: [packet])
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()

        let summary = try await TunnelRuntimeController.runTUICQUICBatch(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            sessionDialer: dialer,
            credentialResolver: TestProxyCredentialResolver(credential: "00000000-0000-0000-0000-000000000003:tuic-password"),
            batchLimit: 16,
            flowLimit: 32
        )

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(flow.readLimits, [16])
        XCTAssertEqual(flow.writtenResults.count, 1)
        XCTAssertEqual(dialer.requests.count, 1)
        XCTAssertEqual(session.exports.count, 1)
        XCTAssertEqual(uniStream.writes, [Data([0x05, 0x00]) + Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3]) + token])
        XCTAssertEqual(bidiStream.writes, [Data([0x05, 0x01, 0x01, 93, 184, 216, 34, 0x01, 0xbb])])
        let status = try XCTUnwrap(statusStore.load())
        XCTAssertEqual(status.phase, .connected)
        XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(status.selectedNodeName, "TUIC")
        XCTAssertEqual(status.message, "Packet batch processed")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
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

    func testShadowsocksTCPSessionReusesProxyConnectionAcrossBatches() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerSnapshot(tls: .disabled))
        let firstPacket = Packet.ipv4TCP(
            id: "tcp-session-1",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x01]
        )
        let secondPacket = Packet.ipv4TCP(
            id: "tcp-session-2",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x02]
        )
        let flow = ControllerSequentialPacketFlowIO(batches: [[firstPacket], [secondPacket]])
        let plain = ControllerRecordingTransportAdapter(transport: .tcp)
        let session = try TunnelRuntimeController.makeShadowsocksTCPSession(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: InMemoryRuntimeStatusStore(),
            logStore: InMemoryRuntimeLogStore(),
            plain: plain,
            tls: ControllerRecordingTransportAdapter(transport: .tcp),
            credentialResolver: TestShadowsocksCredentialResolver(),
            batchLimit: 16,
            flowLimit: 32
        )

        let firstSummary = try await session.runOnce()
        let secondSummary = try await session.runOnce()

        XCTAssertEqual(firstSummary.proxyConnectCount, 1)
        XCTAssertEqual(secondSummary.proxyConnectCount, 0)
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(flow.readLimits, [16, 16])
        XCTAssertEqual(flow.writtenResults.count, 2)
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

private final class ControllerSequentialPacketFlowIO: PacketFlowIO, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ControllerSequentialPacketFlowIO")
    private var batches: [[Packet]]
    private var storedReadLimits: [Int] = []
    private var storedWrittenResults: [PacketProcessingResult] = []

    var readLimits: [Int] {
        queue.sync { storedReadLimits }
    }

    var writtenResults: [PacketProcessingResult] {
        queue.sync { storedWrittenResults }
    }

    init(batches: [[Packet]]) {
        self.batches = batches
    }

    func readPackets(limit: Int) async throws -> [Packet] {
        queue.sync {
            storedReadLimits.append(limit)
            guard !batches.isEmpty else { return [] }
            return Array(batches.removeFirst().prefix(limit))
        }
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        queue.sync {
            storedWrittenResults.append(contentsOf: results)
        }
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

private final class ControllerRecordingTransportStreamAdapter: TransportStreamAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    private let stream: ControllerRecordingByteStream
    private let queue = DispatchQueue(label: "ControllerRecordingTransportStreamAdapter")
    private var storedRequests: [TransportRequest] = []

    var requests: [TransportRequest] {
        queue.sync { storedRequests }
    }

    init(transport: TransportType, stream: ControllerRecordingByteStream) {
        self.supportedTransport = transport
        self.stream = stream
    }

    func openStream(request: TransportRequest) async throws -> any TransportByteStream {
        queue.sync {
            storedRequests.append(request)
        }
        return stream
    }
}

private struct ControllerTUICExporterRequest: Equatable {
    let label: Data
    let context: Data
    let length: Int
}

private struct ControllerTUICSessionDialRequest: Equatable {
    let host: String
    let port: Int
    let tls: TLSOptions?
    let metadata: [String: String]
}

private final class ControllerRecordingTUICQUICSessionDialer: TUICQUICSessionDialer, @unchecked Sendable {
    private let session: ControllerRecordingTUICQUICSession
    private var storedRequests: [ControllerTUICSessionDialRequest] = []

    init(session: ControllerRecordingTUICQUICSession) {
        self.session = session
    }

    var requests: [ControllerTUICSessionDialRequest] { storedRequests }

    func openSession(host: String, port: Int, tls: TLSOptions?, metadata: [String: String]) async throws -> any TUICQUICSession {
        storedRequests.append(ControllerTUICSessionDialRequest(host: host, port: port, tls: tls, metadata: metadata))
        return session
    }
}

private final class ControllerRecordingTUICQUICSession: TUICQUICSession, @unchecked Sendable {
    private let exportedToken: Data
    private let bidirectionalStream: ControllerRecordingByteStream
    private let unidirectionalStream: ControllerRecordingByteStream
    private var storedExports: [ControllerTUICExporterRequest] = []

    init(exportedToken: Data, bidirectionalStream: ControllerRecordingByteStream, unidirectionalStream: ControllerRecordingByteStream) {
        self.exportedToken = exportedToken
        self.bidirectionalStream = bidirectionalStream
        self.unidirectionalStream = unidirectionalStream
    }

    var exports: [ControllerTUICExporterRequest] { storedExports }

    func exportKeyingMaterial(label: Data, context: Data, length: Int) async throws -> Data {
        storedExports.append(ControllerTUICExporterRequest(label: label, context: context, length: length))
        return exportedToken
    }

    func openUnidirectionalStream(initialPayload: Data) async throws -> any TransportByteStream {
        unidirectionalStream.initialPayloads.append(initialPayload)
        return unidirectionalStream
    }

    func openBidirectionalStream(initialPayload: Data) async throws -> any TransportByteStream {
        bidirectionalStream.initialPayloads.append(initialPayload)
        return bidirectionalStream
    }

    func sendDatagram(_ payload: Data) async throws -> Data? { nil }
}

private final class ControllerRecordingByteStream: TransportByteStream, @unchecked Sendable {
    private var reads: [Data?]
    var initialPayloads: [Data] = []
    var writes: [Data] = []

    init(reads: [Data?] = []) {
        self.reads = reads
    }

    func read(maxLength: Int) async throws -> Data? {
        reads.isEmpty ? nil : reads.removeFirst()
    }

    func write(_ data: Data) async throws { writes.append(data) }
    func closeWrite() async {}
    func close() async {}
}

private func controllerHTTP2Frame(type: UInt8, flags: UInt8, streamID: UInt32, payload: Data) -> Data {
    var frame = Data()
    frame.append(UInt8((payload.count >> 16) & 0xff))
    frame.append(UInt8((payload.count >> 8) & 0xff))
    frame.append(UInt8(payload.count & 0xff))
    frame.append(type)
    frame.append(flags)
    frame.append(UInt8((streamID >> 24) & 0x7f))
    frame.append(UInt8((streamID >> 16) & 0xff))
    frame.append(UInt8((streamID >> 8) & 0xff))
    frame.append(UInt8(streamID & 0xff))
    frame.append(payload)
    return frame
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

private final class ControllerFailingLoadRuntimeSnapshotStore: RuntimeSnapshotStore, @unchecked Sendable {
    func save(_ snapshot: RuntimeSnapshot) throws {}

    func load() throws -> RuntimeSnapshot? {
        throw ControllerRuntimeStoreError.failed
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

private func controllerVMessGRPCSnapshot() -> RuntimeSnapshot {
    RuntimeSnapshot(
        id: SnapshotID(rawValue: "snapshot-1"),
        selectedNode: ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "VMess gRPC",
            protocolType: .vmess,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "vmess-credential"),
            transport: .grpc,
            transportOptions: TransportOptions(grpc: GRPCTransportOptions(authority: "edge.example.com", service: "/TunnelService/Connect")),
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil),
            udpPolicy: .disabled
        ),
        routeMode: .globalProxy,
        logLevel: .user,
        routingRuleManifest: RuntimeRoutingRuleManifest(version: 1, rules: [RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)])
    )
}

private func controllerTrustTunnelHTTP2Snapshot() -> RuntimeSnapshot {
    RuntimeSnapshot(
        id: SnapshotID(rawValue: "snapshot-1"),
        selectedNode: ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "TrustTunnel",
            protocolType: .trustTunnel,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "trust-credential"),
            transport: .http2,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: true, alpn: ["h2"], fingerprint: nil, reality: nil),
            udpPolicy: .enabled
        ),
        routeMode: .globalProxy,
        logLevel: .user,
        routingRuleManifest: RuntimeRoutingRuleManifest(version: 1, rules: [RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)])
    )
}

private func controllerTUICSnapshot() -> RuntimeSnapshot {
    RuntimeSnapshot(
        id: SnapshotID(rawValue: "snapshot-1"),
        selectedNode: ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "TUIC",
            protocolType: .tuic,
            serverHost: "tuic.example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "tuic-credential"),
            transport: .quic,
            tls: TLSOptions(enabled: true, serverName: "tuic.example.com", allowInsecure: false, alpn: ["h3"], fingerprint: nil, reality: nil),
            udpPolicy: .disabled
        ),
        routeMode: .globalProxy,
        logLevel: .user,
        routingRuleManifest: RuntimeRoutingRuleManifest(version: 1, rules: [RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)])
    )
}
