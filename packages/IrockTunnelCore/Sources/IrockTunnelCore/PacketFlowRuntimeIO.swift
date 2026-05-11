public protocol PacketFlowIO: Sendable {
    func readPackets(limit: Int) async throws -> [Packet]
    func writePackets(_ results: [PacketProcessingResult]) async throws
}

public struct PacketFlowRuntimeIO<Flow: PacketFlowIO>: PacketReader, PacketWriter {
    private let flow: Flow
    private let batchLimit: Int

    public init(flow: Flow, batchLimit: Int) {
        self.flow = flow
        self.batchLimit = batchLimit
    }

    public func readBatch() async throws -> [Packet] {
        try await flow.readPackets(limit: batchLimit)
    }

    public func write(_ results: [PacketProcessingResult]) async throws {
        try await flow.writePackets(results)
    }
}
