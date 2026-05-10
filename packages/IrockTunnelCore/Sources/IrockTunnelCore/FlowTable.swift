public struct FlowKey: Equatable, Hashable, Sendable {
    public let sourceIP: IPAddress
    public let sourcePort: Int
    public let destinationIP: IPAddress
    public let destinationPort: Int
    public let transportProtocol: TransportProtocol

    public init(sourceIP: IPAddress, sourcePort: Int, destinationIP: IPAddress, destinationPort: Int, transportProtocol: TransportProtocol) {
        self.sourceIP = sourceIP
        self.sourcePort = sourcePort
        self.destinationIP = destinationIP
        self.destinationPort = destinationPort
        self.transportProtocol = transportProtocol
    }

    public init(_ packet: ParsedPacket) {
        self.init(
            sourceIP: packet.sourceIP,
            sourcePort: packet.sourcePort,
            destinationIP: packet.destinationIP,
            destinationPort: packet.destinationPort,
            transportProtocol: packet.transportProtocol
        )
    }
}

public struct FlowRecord: Equatable, Sendable {
    public let key: FlowKey
    public let packetCount: Int
    public let lastSeenSequence: Int

    public init(key: FlowKey, packetCount: Int, lastSeenSequence: Int) {
        self.key = key
        self.packetCount = packetCount
        self.lastSeenSequence = lastSeenSequence
    }
}

public struct FlowTable: Equatable, Sendable {
    public private(set) var records: [FlowRecord]
    public let capacity: Int
    private var sequence: Int

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.records = []
        self.sequence = 0
    }

    public func record(for key: FlowKey) -> FlowRecord? {
        records.first { $0.key == key }
    }

    public mutating func record(_ packet: ParsedPacket) -> FlowRecord {
        let key = FlowKey(packet)
        sequence += 1

        if let index = records.firstIndex(where: { $0.key == key }) {
            let updated = FlowRecord(key: key, packetCount: records[index].packetCount + 1, lastSeenSequence: sequence)
            records[index] = updated
            return updated
        }

        let inserted = FlowRecord(key: key, packetCount: 1, lastSeenSequence: sequence)
        guard capacity > 0 else { return inserted }

        records.append(inserted)
        if records.count > capacity,
           let evictionIndex = records.indices.min(by: { records[$0].lastSeenSequence < records[$1].lastSeenSequence }) {
            records.remove(at: evictionIndex)
        }
        return inserted
    }
}
