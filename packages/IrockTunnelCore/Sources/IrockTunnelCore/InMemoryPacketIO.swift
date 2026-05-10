import Foundation

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
    private let lock = NSLock()
    private var storage: [PacketProcessingResult]

    public var writtenResults: [PacketProcessingResult] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public init(writtenResults: [PacketProcessingResult] = []) {
        self.storage = writtenResults
    }

    public func write(_ results: [PacketProcessingResult]) async throws {
        append(results)
    }

    private func append(_ results: [PacketProcessingResult]) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(contentsOf: results)
    }
}
