import Foundation
import IrockCore
import IrockProtocols

public protocol PacketReader: Sendable {
    func readBatch() async throws -> [Packet]
}

public protocol PacketWriter: Sendable {
    func write(_ results: [PacketProcessingResult]) async throws
}

public struct PacketTunnelRuntimePerformanceEvidence: Equatable, Sendable {
    public let packetCount: Int
    public let writtenCount: Int
    public let dropCount: Int
    public let elapsedNanoseconds: UInt64

    public var averageNanosecondsPerPacket: UInt64 {
        guard packetCount > 0 else { return 0 }
        return elapsedNanoseconds / UInt64(packetCount)
    }

    public var packetsPerSecond: UInt64 {
        guard elapsedNanoseconds > 0 else { return UInt64(packetCount) }
        return UInt64(packetCount) * 1_000_000_000 / elapsedNanoseconds
    }

    public init(packetCount: Int, writtenCount: Int, dropCount: Int, elapsedNanoseconds: UInt64) {
        self.packetCount = packetCount
        self.writtenCount = writtenCount
        self.dropCount = dropCount
        self.elapsedNanoseconds = elapsedNanoseconds
    }
}

public struct PacketTunnelRuntimeSummary: Equatable, Sendable {
    public let readCount: Int
    public let writtenCount: Int
    public let dropCount: Int
    public let proxyConnectCount: Int
    public let performanceEvidence: PacketTunnelRuntimePerformanceEvidence

    public init(readCount: Int, writtenCount: Int, dropCount: Int, proxyConnectCount: Int = 0, performanceEvidence: PacketTunnelRuntimePerformanceEvidence? = nil) {
        self.readCount = readCount
        self.writtenCount = writtenCount
        self.dropCount = dropCount
        self.proxyConnectCount = proxyConnectCount
        self.performanceEvidence = performanceEvidence ?? PacketTunnelRuntimePerformanceEvidence(packetCount: readCount, writtenCount: writtenCount, dropCount: dropCount, elapsedNanoseconds: 0)
    }
}

public struct PacketTunnelRuntime<Reader: PacketReader, Writer: PacketWriter>: Sendable {
    private let reader: Reader
    private let writer: Writer
    private let configuration: TunnelRuntimeConfiguration
    private let reporter: TunnelRuntimeReporter?
    private let proxyConnections = ProxyConnectionStore()

    public init(reader: Reader, writer: Writer, configuration: TunnelRuntimeConfiguration, reporter: TunnelRuntimeReporter? = nil) {
        self.reader = reader
        self.writer = writer
        self.configuration = configuration
        self.reporter = reporter
    }

    public func closeProxyConnections() async {
        let connections = proxyConnections.removeAllConnections()
        for connection in connections {
            await connection.close()
        }
    }

    public func runOnce() async throws -> PacketTunnelRuntimeSummary {
        publish(.preparing, message: "Preparing packet batch")
        appendLog(message: "Tunnel runtime preparing", phase: .preparing)
        let startNanoseconds = DispatchTime.now().uptimeNanoseconds

        let packets: [Packet]
        let results: [PacketProcessingResult]
        let proxyConnectionSummary: ProxyConnectionSummary
        do {
            packets = try await reader.readBatch()
            var processor = PacketProcessor(configuration: configuration)
            results = processor.process(packets)
            let udpResponseBytesByResultIndex = try await forwardUDPDatagrams(results)
            proxyConnectionSummary = try await connectProxyResults(results)
            let writableResults = results.enumerated().map { index, result in
                if let responseBytes = udpResponseBytesByResultIndex[index] {
                    return result.withResponsePacketBytes(responseBytes)
                }
                guard let responseBytes = proxyConnectionSummary.responseBytesByResultIndex[index] else {
                    return result
                }
                return result.withResponsePacketBytes(responseBytes)
            }

            try await writer.write(writableResults)
        } catch {
            let message = failureMessage(for: error)
            publish(.failed, message: message)
            appendLog(message: message, phase: .failed)
            throw error
        }

        publish(.connected, message: "Packet batch processed")
        appendLog(message: "Tunnel runtime connected", phase: .connected)

        let dropCount = results.filter { result in
            if case .drop = result.action {
                return true
            }
            return false
        }.count
        return PacketTunnelRuntimeSummary(
            readCount: packets.count,
            writtenCount: results.count,
            dropCount: dropCount,
            proxyConnectCount: proxyConnectionSummary.connectCount,
            performanceEvidence: PacketTunnelRuntimePerformanceEvidence(
                packetCount: packets.count,
                writtenCount: results.count,
                dropCount: dropCount,
                elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - startNanoseconds
            )
        )
    }

    private struct ProxyConnectionSummary {
        let connectCount: Int
        let responseBytesByResultIndex: [Int: [UInt8]]
    }

    private final class ProxyConnectionStore: @unchecked Sendable {
        private let lock = NSLock()
        private var connectionsByFlowKey: [FlowKey: any ProxyConnection] = [:]
        private var flowKeysByRecency: [FlowKey] = []

        func connection(for flowKey: FlowKey) -> (any ProxyConnection)? {
            lock.lock()
            defer { lock.unlock() }
            guard let connection = connectionsByFlowKey[flowKey] else { return nil }
            markRecentlyUsed(flowKey)
            return connection
        }

        func setConnection(_ connection: any ProxyConnection, for flowKey: FlowKey, limit: Int) -> [any ProxyConnection] {
            lock.lock()
            defer { lock.unlock() }
            connectionsByFlowKey[flowKey] = connection
            markRecentlyUsed(flowKey)
            guard limit > 0 else {
                let evicted = Array(connectionsByFlowKey.values)
                connectionsByFlowKey.removeAll()
                flowKeysByRecency.removeAll()
                return evicted
            }
            var evictedConnections: [any ProxyConnection] = []
            while connectionsByFlowKey.count > limit, let evictedFlowKey = flowKeysByRecency.first {
                flowKeysByRecency.removeFirst()
                if let evictedConnection = connectionsByFlowKey.removeValue(forKey: evictedFlowKey) {
                    evictedConnections.append(evictedConnection)
                }
            }
            return evictedConnections
        }

        func removeConnection(for flowKey: FlowKey) -> (any ProxyConnection)? {
            lock.lock()
            defer { lock.unlock() }
            flowKeysByRecency.removeAll { $0 == flowKey }
            return connectionsByFlowKey.removeValue(forKey: flowKey)
        }

        func removeAllConnections() -> [any ProxyConnection] {
            lock.lock()
            defer { lock.unlock() }
            let connections = Array(connectionsByFlowKey.values)
            connectionsByFlowKey.removeAll()
            flowKeysByRecency.removeAll()
            return connections
        }

        private func markRecentlyUsed(_ flowKey: FlowKey) {
            flowKeysByRecency.removeAll { $0 == flowKey }
            flowKeysByRecency.append(flowKey)
        }
    }

    private func forwardUDPDatagrams(_ results: [PacketProcessingResult]) async throws -> [Int: [UInt8]] {
        try await withThrowingTaskGroup(of: (Int, [UInt8]?).self) { group in
            for (index, result) in results.enumerated() {
                guard let request = try udpForwardingRequest(for: result) else {
                    continue
                }
                group.addTask {
                    guard let payload = try await configuration.udpDatagramForwarder.forward(request) else {
                        return (index, nil)
                    }
                    return (index, Packet.ipv4UDPResponse(id: "\(result.packet.id)-udp-response", request: request.parsedPacket, payload: payload).bytes)
                }
            }

            var responseBytesByResultIndex: [Int: [UInt8]] = [:]
            for try await (index, responseBytes) in group {
                if let responseBytes {
                    responseBytesByResultIndex[index] = responseBytes
                }
            }
            return responseBytesByResultIndex
        }
    }

    private func udpForwardingRequest(for result: PacketProcessingResult) throws -> UDPDatagramForwardingRequest? {
        guard let parsedPacket = result.parsedPacket else { return nil }
        switch result.udpForwardingDecision(udpPolicy: configuration.snapshot.selectedNode.udpPolicy) {
        case let .direct(flowKey):
            return UDPDatagramForwardingRequest(mode: .direct, node: configuration.snapshot.selectedNode, flowKey: flowKey, parsedPacket: parsedPacket, payload: parsedPacket.udpPayload)
        case let .proxy(flowKey):
            return UDPDatagramForwardingRequest(mode: .proxy, node: configuration.snapshot.selectedNode, flowKey: flowKey, parsedPacket: parsedPacket, payload: parsedPacket.udpPayload)
        case .unsupported:
            throw ProxyProtocolError.udpUnsupported
        case .reject, .drop, .none:
            return nil
        }
    }

    private func connectProxyResults(_ results: [PacketProcessingResult]) async throws -> ProxyConnectionSummary {
        let outbound = ProxyOutbound(node: configuration.snapshot.selectedNode, registry: configuration.proxyAdapterRegistry)
        var connectCount = 0
        var responseBytesByResultIndex: [Int: [UInt8]] = [:]
        for (index, result) in results.enumerated() {
            guard result.parsedPacket?.transportProtocol != .udp else {
                continue
            }
            guard let flowKey = result.flowKey else {
                continue
            }
            let connection: (any ProxyConnection)?
            let didConnect: Bool
            if let existingConnection = proxyConnections.connection(for: flowKey) {
                connection = existingConnection
                didConnect = false
            } else if let newConnection = try await outbound.connect(result: result) {
                let evictedConnections = proxyConnections.setConnection(newConnection, for: flowKey, limit: configuration.flowLimit)
                for evictedConnection in evictedConnections {
                    await evictedConnection.close()
                }
                connectCount += 1
                connection = newConnection
                didConnect = true
            } else {
                connection = nil
                didConnect = false
            }
            guard let connection else { continue }
            do {
                if let responseBytes = try await connection.writePayload(result.parsedPacket?.transportPayload ?? []), !responseBytes.isEmpty {
                    responseBytesByResultIndex[index] = responseBytes
                } else if didConnect, let responseBytes = connection.initialResponseBytes, !responseBytes.isEmpty {
                    responseBytesByResultIndex[index] = responseBytes
                }
            } catch {
                await proxyConnections.removeConnection(for: flowKey)?.close()
                throw error
            }
        }
        return ProxyConnectionSummary(connectCount: connectCount, responseBytesByResultIndex: responseBytesByResultIndex)
    }

    private func failureMessage(for error: Error) -> String {
        if let protocolError = error as? ProxyProtocolError {
            return "Proxy adapter failed: \(protocolError.description)"
        }
        return "Packet batch failed"
    }

    private func publish(_ phase: RuntimeConnectionPhase, message: String) {
        try? reporter?.publishStatus(RuntimeConnectionStatus(
            phase: phase,
            selectedNodeID: configuration.snapshot.selectedNode.id,
            selectedNodeName: configuration.snapshot.selectedNode.name,
            updatedAt: Date(),
            message: message
        ))
    }

    private func appendLog(message: String, phase: RuntimeConnectionPhase) {
        try? reporter?.appendLog(RuntimeLogEntry(
            id: "log-\(UUID().uuidString)",
            timestamp: Date(),
            level: .user,
            message: message,
            nodeID: configuration.snapshot.selectedNode.id,
            phase: phase
        ))
    }
}
