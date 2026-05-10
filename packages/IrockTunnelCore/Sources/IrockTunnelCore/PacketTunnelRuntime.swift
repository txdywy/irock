import Foundation
import IrockCore

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

    public init(readCount: Int, writtenCount: Int, dropCount: Int) {
        self.readCount = readCount
        self.writtenCount = writtenCount
        self.dropCount = dropCount
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
        do {
            packets = try await reader.readBatch()
            var processor = PacketProcessor(configuration: configuration)
            results = processor.process(packets)

            try await writer.write(results)
        } catch {
            publish(.failed, message: "Packet batch failed")
            appendLog(message: "Tunnel runtime failed", phase: .failed)
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
            }.count
        )
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
