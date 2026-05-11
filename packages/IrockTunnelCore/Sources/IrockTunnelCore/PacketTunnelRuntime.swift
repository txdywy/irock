import Foundation
import IrockCore
import IrockProtocols

public protocol PacketReader: Sendable {
    func readBatch() async throws -> [Packet]
}

public protocol PacketWriter: Sendable {
    func write(_ results: [PacketProcessingResult]) async throws
}

public struct PacketTunnelRuntimeSummary: Equatable, Sendable {
    public let readCount: Int
    public let writtenCount: Int
    public let dropCount: Int
    public let proxyConnectCount: Int

    public init(readCount: Int, writtenCount: Int, dropCount: Int, proxyConnectCount: Int = 0) {
        self.readCount = readCount
        self.writtenCount = writtenCount
        self.dropCount = dropCount
        self.proxyConnectCount = proxyConnectCount
    }
}

public struct PacketTunnelRuntime<Reader: PacketReader, Writer: PacketWriter>: Sendable {
    private let reader: Reader
    private let writer: Writer
    private let configuration: TunnelRuntimeConfiguration
    private let reporter: TunnelRuntimeReporter?

    public init(reader: Reader, writer: Writer, configuration: TunnelRuntimeConfiguration, reporter: TunnelRuntimeReporter? = nil) {
        self.reader = reader
        self.writer = writer
        self.configuration = configuration
        self.reporter = reporter
    }

    public func runOnce() async throws -> PacketTunnelRuntimeSummary {
        publish(.preparing, message: "Preparing packet batch")
        appendLog(message: "Tunnel runtime preparing", phase: .preparing)

        let packets: [Packet]
        let results: [PacketProcessingResult]
        let proxyConnectionSummary: ProxyConnectionSummary
        do {
            packets = try await reader.readBatch()
            var processor = PacketProcessor(configuration: configuration)
            results = processor.process(packets)
            proxyConnectionSummary = try await connectProxyResults(results)
            let writableResults = results.enumerated().map { index, result in
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

        return PacketTunnelRuntimeSummary(
            readCount: packets.count,
            writtenCount: results.count,
            dropCount: results.filter { result in
                if case .drop = result.action {
                    return true
                }
                return false
            }.count,
            proxyConnectCount: proxyConnectionSummary.connectCount
        )
    }

    private struct ProxyConnectionSummary {
        let connectCount: Int
        let responseBytesByResultIndex: [Int: [UInt8]]
    }

    private func connectProxyResults(_ results: [PacketProcessingResult]) async throws -> ProxyConnectionSummary {
        let outbound = ProxyOutbound(node: configuration.snapshot.selectedNode, registry: configuration.proxyAdapterRegistry)
        var connectedFlows: Set<FlowKey> = []
        var connectCount = 0
        var responseBytesByResultIndex: [Int: [UInt8]] = [:]
        for (index, result) in results.enumerated() {
            guard let flowKey = result.flowKey, connectedFlows.insert(flowKey).inserted else {
                continue
            }
            if let connection = try await outbound.connect(result: result) {
                connectCount += 1
                if let responseBytes = connection.initialResponseBytes, !responseBytes.isEmpty {
                    responseBytesByResultIndex[index] = responseBytes
                }
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
