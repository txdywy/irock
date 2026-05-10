public struct InMemoryPacketReader: PacketReader {
    private let packets: [Packet]

    public init(packets: [Packet]) {
        self.packets = packets
    }

    public func readBatch() async throws -> [Packet] {
        packets
    }
}

public final class InMemoryPacketWriter: PacketWriter, @unchecked Sendable {
    public private(set) var writtenResults: [PacketProcessingResult]

    public init(writtenResults: [PacketProcessingResult] = []) {
        self.writtenResults = writtenResults
    }

    public func write(_ results: [PacketProcessingResult]) async throws {
        writtenResults.append(contentsOf: results)
    }
}
