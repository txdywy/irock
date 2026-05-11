import XCTest
import IrockCore
import IrockProtocols
import IrockRouting
import IrockStorage
@testable import IrockTunnelCore

final class PacketTunnelRuntimeTests: XCTestCase {
    func testRuntimeReadsProcessesAndWritesBatch() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let malformedPacket = Packet(id: "bad", bytes: [0x45])
        let reader = InMemoryPacketReader(packets: [validPacket, malformedPacket])
        let writer = InMemoryPacketWriter()
        let runtime = PacketTunnelRuntime(reader: reader, writer: writer, configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [RuntimeRecordingProxyAdapter(protocolType: .trojan)]), batchLimit: 16, flowLimit: 32))

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
            configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [RuntimeRecordingProxyAdapter(protocolType: .trojan)]), batchLimit: 16, flowLimit: 32),
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
            configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [RuntimeRecordingProxyAdapter(protocolType: .trojan)]), batchLimit: 16, flowLimit: 32),
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
            configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [RuntimeRecordingProxyAdapter(protocolType: .trojan)]), batchLimit: 16, flowLimit: 32),
            reporter: reporter
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(writer.writtenResults.count, 1)
    }

    func testRuntimePublishesFailedStatusAndLogWhenReaderThrows() async throws {
        let reader = ThrowingPacketReader()
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

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected packet reader error")
        } catch PacketRuntimeTestError.failed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
            XCTAssertEqual(status.selectedNodeName, "Demo")
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet reader error, got \(error)")
        }
    }

    func testRuntimePublishesFailedStatusAndLogWhenWriterThrows() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
        let writer = ThrowingPacketWriter()
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [RuntimeRecordingProxyAdapter(protocolType: .trojan)]), batchLimit: 16, flowLimit: 32),
            reporter: reporter
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected packet writer error")
        } catch PacketRuntimeTestError.failed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
            XCTAssertEqual(status.selectedNodeName, "Demo")
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet writer error, got \(error)")
        }
    }

    func testRuntimeConnectsProxyResultsOncePerFlowBeforeWritingBatch() async throws {
        let adapter = RuntimeRecordingProxyAdapter(protocolType: .trojan)
        let firstPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let secondPacket = Packet.ipv4TCP(id: "tcp-2", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [firstPacket, secondPacket])
        let writer = InMemoryPacketWriter()
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(
                snapshot: snapshot(routeMode: .globalProxy),
                routingEngine: RoutingEngine(rules: [.final(.proxy)]),
                proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [adapter]),
                batchLimit: 16,
                flowLimit: 32
            )
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 2)
        XCTAssertEqual(summary.writtenCount, 2)
        XCTAssertEqual(summary.dropCount, 0)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(adapter.connectCount, 1)
        XCTAssertEqual(writer.writtenResults.count, 2)
    }

    func testRuntimeConnectsProxyResultsBeforeWritingBatch() async throws {
        let adapter = RuntimeRecordingProxyAdapter(protocolType: .trojan)
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
        let writer = InMemoryPacketWriter()
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(
                snapshot: snapshot(routeMode: .globalProxy),
                routingEngine: RoutingEngine(rules: [.final(.proxy)]),
                proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [adapter]),
                batchLimit: 16,
                flowLimit: 32
            )
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.dropCount, 0)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(adapter.connectCount, 1)
        XCTAssertEqual(writer.writtenResults.count, 1)
    }

    func testRuntimePublishesFailedStatusAndLogWhenProxyAdapterIsUnsupported() async throws {
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

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
            XCTAssertEqual(status.selectedNodeName, "Demo")
            XCTAssertEqual(status.message, "Proxy adapter failed: Unsupported protocol: trojan")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Proxy adapter failed: Unsupported protocol: trojan"])
            XCTAssertEqual(writer.writtenResults, [])
        } catch {
            XCTFail("Expected proxy protocol error, got \(error)")
        }
    }

    func testRuntimePublishesFailedStatusAndLogWhenProxyAdapterThrows() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
        let writer = InMemoryPacketWriter()
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(
                snapshot: snapshot(routeMode: .globalProxy),
                routingEngine: RoutingEngine(rules: [.final(.proxy)]),
                proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [FailingProxyAdapter(protocolType: .trojan)]),
                batchLimit: 16,
                flowLimit: 32
            ),
            reporter: reporter
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected protocol failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tcpConnectFailed("secret connection refused"))
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Proxy adapter failed: TCP connect failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Proxy adapter failed: TCP connect failed"])
            XCTAssertEqual(writer.writtenResults, [])
        } catch {
            XCTFail("Expected proxy protocol error, got \(error)")
        }
    }

    func testConfigurationStoresProxyAdapterRegistry() async throws {
        let adapter = RuntimeRecordingProxyAdapter(protocolType: .trojan)
        let registry = ProxyAdapterRegistry(adapters: [adapter])
        let configuration = TunnelRuntimeConfiguration(
            snapshot: snapshot(routeMode: .globalProxy),
            routingEngine: RoutingEngine(rules: [.final(.proxy)]),
            proxyAdapterRegistry: registry,
            batchLimit: 16,
            flowLimit: 32
        )

        let selected = configuration.proxyAdapterRegistry.adapter(for: .trojan)
        let connection = try await selected.connect(request: ProxyRequest(node: snapshot(routeMode: .globalProxy).selectedNode, destination: .ipv4("93.184.216.34", port: 443)))

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
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

private enum PacketRuntimeTestError: Error {
    case failed
}

private enum FailingRuntimeStoreError: Error {
    case failed
}

private struct ThrowingPacketReader: PacketReader {
    func readBatch() async throws -> [Packet] {
        throw PacketRuntimeTestError.failed
    }
}

private struct ThrowingPacketWriter: PacketWriter {
    func write(_ results: [PacketProcessingResult]) async throws {
        throw PacketRuntimeTestError.failed
    }
}

private final class RuntimeRecordingProxyAdapter: ProxyAdapter, @unchecked Sendable {
    let supportedProtocol: ProxyProtocolType
    private let lock = NSLock()
    private var connectCountValue = 0

    var connectCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return connectCountValue
    }

    init(protocolType: ProxyProtocolType) {
        self.supportedProtocol = protocolType
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        recordConnection()
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func recordConnection() {
        lock.lock()
        defer { lock.unlock() }
        connectCountValue += 1
    }
}

private struct FailingProxyAdapter: ProxyAdapter {
    let supportedProtocol: ProxyProtocolType

    init(protocolType: ProxyProtocolType) {
        self.supportedProtocol = protocolType
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        throw ProxyProtocolError.tcpConnectFailed("secret connection refused")
    }
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
