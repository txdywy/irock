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

    public init(reader: Reader, writer: Writer, configuration: TunnelRuntimeConfiguration) {
        self.reader = reader
        self.writer = writer
        self.configuration = configuration
    }

    public func runOnce() async throws -> PacketTunnelRuntimeSummary {
        let packets = try await reader.readBatch()
        var processor = PacketProcessor(configuration: configuration)
        let results = processor.process(packets)

        try await writer.write(results)

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
}
