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

    func testRuntimeSummaryRecordsBatchPerformanceEvidence() async throws {
        let packets = (0..<4_096).map { index in
            Packet.ipv4TCP(
                id: "tcp-\(index)",
                source: .v4(10, 0, 0, UInt8(index % 255)),
                destination: .v4(93, 184, 216, 34),
                sourcePort: 40_000 + (index % 1_000),
                destinationPort: 443
            )
        }
        let reader = InMemoryPacketReader(packets: packets)
        let writer = InMemoryPacketWriter()
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(
                snapshot: snapshot(routeMode: .direct),
                routingEngine: RoutingEngine(rules: [.final(.direct)]),
                batchLimit: packets.count,
                flowLimit: packets.count
            )
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.performanceEvidence.packetCount, 4_096)
        XCTAssertEqual(summary.performanceEvidence.writtenCount, 4_096)
        XCTAssertEqual(summary.performanceEvidence.dropCount, 0)
        XCTAssertGreaterThan(summary.performanceEvidence.elapsedNanoseconds, 0)
        XCTAssertGreaterThan(summary.performanceEvidence.packetsPerSecond, 1_000)
        XCTAssertLessThan(summary.performanceEvidence.averageNanosecondsPerPacket, 2_000_000)
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

    func testRuntimeWritesProxyInitialResponseBytesForMatchingFlow() async throws {
        let adapter = RuntimeRecordingProxyAdapter(protocolType: .trojan, initialResponseBytes: [0x45, 0x00, 0x00, 0x28])
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [packet])
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
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(writer.writtenResults.first?.responsePacketBytes, [0x45, 0x00, 0x00, 0x28])
    }

    func testRuntimeAttachesProxyInitialResponseBytesOnlyToConnectedResult() async throws {
        let adapter = RuntimeRecordingProxyAdapter(protocolType: .trojan, initialResponseBytes: [0x45, 0x00, 0x00, 0x28])
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
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(writer.writtenResults.map(\.responsePacketBytes), [[0x45, 0x00, 0x00, 0x28], nil])
    }

    func testRuntimeRelaysTCPPayloadBytesThroughProxyConnection() async throws {
        let connection = RuntimeRecordingProxyConnection(responseBytes: [0x45, 0x00, 0x00, 0x28])
        let adapter = RuntimeConnectionProxyAdapter(protocolType: .trojan, connection: connection)
        let packet = Packet.ipv4TCP(
            id: "tcp-payload",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0xde, 0xad, 0xbe, 0xef]
        )
        let reader = InMemoryPacketReader(packets: [packet])
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
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(connection.writtenPayloads, [[0xde, 0xad, 0xbe, 0xef]])
        XCTAssertEqual(writer.writtenResults.first?.responsePacketBytes, [0x45, 0x00, 0x00, 0x28])
    }

    func testRuntimeRelaysMultipleTCPPayloadsOnSameFlowThroughOneProxyConnection() async throws {
        let connection = RuntimeRecordingProxyConnection(responseBytes: nil)
        let adapter = RuntimeConnectionProxyAdapter(protocolType: .trojan, connection: connection)
        let firstPacket = Packet.ipv4TCP(
            id: "tcp-payload-1",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x01, 0x02]
        )
        let secondPacket = Packet.ipv4TCP(
            id: "tcp-payload-2",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x03, 0x04]
        )
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
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(adapter.connectCount, 1)
        XCTAssertEqual(connection.writtenPayloads, [[0x01, 0x02], [0x03, 0x04]])
    }

    func testRuntimeReusesTCPProxyConnectionAcrossBatchesForSameFlow() async throws {
        let connection = RuntimeRecordingProxyConnection(responseBytes: nil)
        let adapter = RuntimeConnectionProxyAdapter(protocolType: .trojan, connection: connection)
        let firstPacket = Packet.ipv4TCP(
            id: "tcp-batch-1",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x01]
        )
        let secondPacket = Packet.ipv4TCP(
            id: "tcp-batch-2",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x02]
        )
        let reader = RuntimeSequentialPacketReader(batches: [[firstPacket], [secondPacket]])
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

        let firstSummary = try await runtime.runOnce()
        let secondSummary = try await runtime.runOnce()

        XCTAssertEqual(firstSummary.proxyConnectCount, 1)
        XCTAssertEqual(secondSummary.proxyConnectCount, 0)
        XCTAssertEqual(adapter.connectCount, 1)
        XCTAssertEqual(connection.writtenPayloads, [[0x01], [0x02]])
        XCTAssertEqual(writer.writtenResults.count, 2)
    }

    func testRuntimeClosesTCPProxyConnectionsOnShutdown() async throws {
        let connection = RuntimeRecordingProxyConnection(responseBytes: nil)
        let adapter = RuntimeConnectionProxyAdapter(protocolType: .trojan, connection: connection)
        let packet = Packet.ipv4TCP(
            id: "tcp-shutdown",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x01]
        )
        let reader = RuntimeSequentialPacketReader(batches: [[packet]])
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

        _ = try await runtime.runOnce()
        await runtime.closeProxyConnections()

        XCTAssertEqual(connection.closeCount, 1)
    }

    func testRuntimeEvictsAndClosesOldTCPProxyConnectionsAtFlowLimit() async throws {
        let firstConnection = RuntimeRecordingProxyConnection(responseBytes: nil)
        let secondConnection = RuntimeRecordingProxyConnection(responseBytes: nil)
        let thirdConnection = RuntimeRecordingProxyConnection(responseBytes: nil)
        let adapter = RuntimeSequencedProxyAdapter(protocolType: .trojan, connections: [firstConnection, secondConnection, thirdConnection])
        let firstFlowPacket = Packet.ipv4TCP(
            id: "tcp-flow-1-a",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x01]
        )
        let secondFlowPacket = Packet.ipv4TCP(
            id: "tcp-flow-2",
            source: .v4(10, 0, 0, 3),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_235,
            destinationPort: 443,
            payload: [0x02]
        )
        let firstFlowAgainPacket = Packet.ipv4TCP(
            id: "tcp-flow-1-b",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x03]
        )
        let reader = RuntimeSequentialPacketReader(batches: [[firstFlowPacket], [secondFlowPacket], [firstFlowAgainPacket]])
        let writer = InMemoryPacketWriter()
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(
                snapshot: snapshot(routeMode: .globalProxy),
                routingEngine: RoutingEngine(rules: [.final(.proxy)]),
                proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [adapter]),
                batchLimit: 16,
                flowLimit: 1
            )
        )

        _ = try await runtime.runOnce()
        _ = try await runtime.runOnce()
        _ = try await runtime.runOnce()

        XCTAssertEqual(adapter.connectCount, 3)
        XCTAssertEqual(firstConnection.closeCount, 1)
        XCTAssertEqual(secondConnection.closeCount, 1)
        XCTAssertEqual(thirdConnection.closeCount, 0)
        XCTAssertEqual(firstConnection.writtenPayloads, [[0x01]])
        XCTAssertEqual(secondConnection.writtenPayloads, [[0x02]])
        XCTAssertEqual(thirdConnection.writtenPayloads, [[0x03]])
        XCTAssertEqual(writer.writtenResults.count, 3)
    }

    func testRuntimeRemovesAndClosesTCPProxyConnectionWhenPayloadWriteFails() async throws {
        let failingConnection = RuntimeFailingProxyConnection()
        let recoveredConnection = RuntimeRecordingProxyConnection(responseBytes: nil)
        let adapter = RuntimeSequencedProxyAdapter(protocolType: .trojan, connections: [failingConnection, recoveredConnection])
        let packet = Packet.ipv4TCP(
            id: "tcp-write-fails",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x01]
        )
        let retryPacket = Packet.ipv4TCP(
            id: "tcp-write-recovers",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0x02]
        )
        let reader = RuntimeSequentialPacketReader(batches: [[packet], [retryPacket]])
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

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected write failure")
        } catch PacketRuntimeTestError.failed {
            XCTAssertEqual(failingConnection.closeCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        _ = try await runtime.runOnce()

        XCTAssertEqual(adapter.connectCount, 2)
        XCTAssertEqual(recoveredConnection.writtenPayloads, [[0x02]])
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

    func testRuntimeForwardsDirectUDPDatagramAndWritesSynthesizedResponsePacket() async throws {
        let udpPacket = Packet.ipv4UDP(
            id: "udp-direct",
            source: .v4(10, 0, 0, 2),
            destination: .v4(1, 1, 1, 1),
            sourcePort: 55_555,
            destinationPort: 53,
            payload: [0x01, 0x02]
        )
        let forwarder = RuntimeRecordingUDPDatagramForwarder(responsePayload: [0x03, 0x04, 0x05])
        let reader = InMemoryPacketReader(packets: [udpPacket])
        let writer = InMemoryPacketWriter()
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(
                snapshot: snapshot(routeMode: .direct),
                routingEngine: RoutingEngine(rules: [.final(.direct)]),
                udpDatagramForwarder: forwarder,
                batchLimit: 16,
                flowLimit: 32
            )
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.proxyConnectCount, 0)
        XCTAssertEqual(forwarder.requests.count, 1)
        XCTAssertEqual(forwarder.requests.first?.mode, .direct)
        XCTAssertEqual(forwarder.requests.first?.payload, [0x01, 0x02])
        let responseBytes = try XCTUnwrap(writer.writtenResults.first?.responsePacketBytes)
        let response = try PacketParser().parse(Packet(id: "udp-response", bytes: responseBytes))
        XCTAssertEqual(response.sourceIP, .v4(1, 1, 1, 1))
        XCTAssertEqual(response.destinationIP, .v4(10, 0, 0, 2))
        XCTAssertEqual(response.sourcePort, 53)
        XCTAssertEqual(response.destinationPort, 55_555)
        XCTAssertEqual(response.udpPayload, [0x03, 0x04, 0x05])
    }

    func testRuntimeForwardsProxyUDPDatagramWithoutOpeningStreamConnection() async throws {
        let udpPacket = Packet.ipv4UDP(
            id: "udp-proxy",
            source: .v4(10, 0, 0, 2),
            destination: .v4(1, 1, 1, 1),
            sourcePort: 55_555,
            destinationPort: 53,
            payload: [0x0a, 0x0b]
        )
        let adapter = RuntimeRecordingProxyAdapter(protocolType: .trojan)
        let forwarder = RuntimeRecordingUDPDatagramForwarder(responsePayload: [0x0c, 0x0d])
        let reader = InMemoryPacketReader(packets: [udpPacket])
        let writer = InMemoryPacketWriter()
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(
                snapshot: snapshot(routeMode: .globalProxy, udpPolicy: .enabled),
                routingEngine: RoutingEngine(rules: [.final(.proxy)]),
                proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [adapter]),
                udpDatagramForwarder: forwarder,
                batchLimit: 16,
                flowLimit: 32
            )
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.proxyConnectCount, 0)
        XCTAssertEqual(adapter.connectCount, 0)
        XCTAssertEqual(forwarder.requests.count, 1)
        XCTAssertEqual(forwarder.requests.first?.mode, .proxy)
        XCTAssertEqual(forwarder.requests.first?.payload, [0x0a, 0x0b])
        let responseBytes = try XCTUnwrap(writer.writtenResults.first?.responsePacketBytes)
        let response = try PacketParser().parse(Packet(id: "udp-response", bytes: responseBytes))
        XCTAssertEqual(response.udpPayload, [0x0c, 0x0d])
    }

    func testRuntimePublishesFailedStatusAndLogWhenUDPProxyIsUnsupported() async throws {
        let udpPacket = Packet.ipv4UDP(id: "udp-unsupported", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 55_555, destinationPort: 53)
        let reader = InMemoryPacketReader(packets: [udpPacket])
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
                proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [RuntimeRecordingProxyAdapter(protocolType: .trojan)]),
                batchLimit: 16,
                flowLimit: 32
            ),
            reporter: reporter
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected UDP unsupported")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .udpUnsupported)
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
            XCTAssertEqual(status.selectedNodeName, "Demo")
            XCTAssertEqual(status.message, "Proxy adapter failed: UDP unsupported")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Proxy adapter failed: UDP unsupported"])
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

    private func snapshot(routeMode: RouteMode, udpPolicy: UDPPolicy = .disabled) -> RuntimeSnapshot {
        RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: udpPolicy),
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

private final class RuntimeSequentialPacketReader: PacketReader, @unchecked Sendable {
    private let queue = DispatchQueue(label: "RuntimeSequentialPacketReader")
    private var remainingBatches: [[Packet]]

    init(batches: [[Packet]]) {
        self.remainingBatches = batches
    }

    func readBatch() async throws -> [Packet] {
        queue.sync {
            guard !remainingBatches.isEmpty else { return [] }
            return remainingBatches.removeFirst()
        }
    }
}

private struct ThrowingPacketWriter: PacketWriter {
    func write(_ results: [PacketProcessingResult]) async throws {
        throw PacketRuntimeTestError.failed
    }
}

private final class RuntimeConnectionProxyAdapter: ProxyAdapter, @unchecked Sendable {
    let supportedProtocol: ProxyProtocolType
    private let connection: any ProxyConnection
    private let queue = DispatchQueue(label: "RuntimeConnectionProxyAdapter")
    private var connectCountValue = 0

    var connectCount: Int {
        queue.sync { connectCountValue }
    }

    init(protocolType: ProxyProtocolType, connection: any ProxyConnection) {
        self.supportedProtocol = protocolType
        self.connection = connection
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        queue.sync { connectCountValue += 1 }
        return connection
    }
}

private final class RuntimeSequencedProxyAdapter: ProxyAdapter, @unchecked Sendable {
    let supportedProtocol: ProxyProtocolType
    private let queue = DispatchQueue(label: "RuntimeSequencedProxyAdapter")
    private var connections: [any ProxyConnection]
    private var connectCountValue = 0

    var connectCount: Int {
        queue.sync { connectCountValue }
    }

    init(protocolType: ProxyProtocolType, connections: [any ProxyConnection]) {
        self.supportedProtocol = protocolType
        self.connections = connections
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        queue.sync {
            connectCountValue += 1
            return connections.removeFirst()
        }
    }
}

private final class RuntimeRecordingProxyConnection: ProxyConnection, @unchecked Sendable {
    let nodeID = NodeID(rawValue: "node-1")
    let destination = ProxyDestination.ipv4("93.184.216.34", port: 443)
    let initialResponseBytes: [UInt8]? = nil
    private let responseBytes: [UInt8]?
    private let queue = DispatchQueue(label: "RuntimeRecordingProxyConnection")
    private var payloadValues: [[UInt8]] = []
    private var closeCountValue = 0

    var writtenPayloads: [[UInt8]] {
        queue.sync { payloadValues }
    }

    var closeCount: Int {
        queue.sync { closeCountValue }
    }

    init(responseBytes: [UInt8]?) {
        self.responseBytes = responseBytes
    }

    func writePayload(_ payload: [UInt8]) async throws -> [UInt8]? {
        queue.sync { payloadValues.append(payload) }
        return responseBytes
    }

    func close() async {
        queue.sync { closeCountValue += 1 }
    }
}

private final class RuntimeFailingProxyConnection: ProxyConnection, @unchecked Sendable {
    let nodeID = NodeID(rawValue: "node-1")
    let destination = ProxyDestination.ipv4("93.184.216.34", port: 443)
    let initialResponseBytes: [UInt8]? = nil
    private let queue = DispatchQueue(label: "RuntimeFailingProxyConnection")
    private var closeCountValue = 0

    var closeCount: Int {
        queue.sync { closeCountValue }
    }

    func writePayload(_ payload: [UInt8]) async throws -> [UInt8]? {
        throw PacketRuntimeTestError.failed
    }

    func close() async {
        queue.sync { closeCountValue += 1 }
    }
}

private final class RuntimeRecordingProxyAdapter: ProxyAdapter, @unchecked Sendable {
    let supportedProtocol: ProxyProtocolType
    private let initialResponseBytes: [UInt8]?
    private let lock = NSLock()
    private var connectCountValue = 0

    var connectCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return connectCountValue
    }

    init(protocolType: ProxyProtocolType, initialResponseBytes: [UInt8]? = nil) {
        self.supportedProtocol = protocolType
        self.initialResponseBytes = initialResponseBytes
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        recordConnection()
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination, initialResponseBytes: initialResponseBytes)
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

private final class RuntimeRecordingUDPDatagramForwarder: UDPDatagramForwarder, @unchecked Sendable {
    private let responsePayload: [UInt8]
    private let queue = DispatchQueue(label: "RuntimeRecordingUDPDatagramForwarder")
    private var requestValues: [UDPDatagramForwardingRequest] = []

    var requests: [UDPDatagramForwardingRequest] {
        queue.sync { requestValues }
    }

    init(responsePayload: [UInt8]) {
        self.responsePayload = responsePayload
    }

    func forward(_ request: UDPDatagramForwardingRequest) async throws -> [UInt8]? {
        queue.sync { requestValues.append(request) }
        return responsePayload
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
