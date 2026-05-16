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
    private var recordIndexByKey: [FlowKey: Int]

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.records = []
        self.sequence = 0
        self.recordIndexByKey = [:]
    }

    public func record(for key: FlowKey) -> FlowRecord? {
        guard let index = recordIndexByKey[key] else { return nil }
        return records[index]
    }

    public mutating func record(_ packet: ParsedPacket) -> FlowRecord {
        let key = FlowKey(packet)
        sequence += 1

        if let index = recordIndexByKey[key] {
            let updated = FlowRecord(key: key, packetCount: records[index].packetCount + 1, lastSeenSequence: sequence)
            records[index] = updated
            return updated
        }

        let inserted = FlowRecord(key: key, packetCount: 1, lastSeenSequence: sequence)
        guard capacity > 0 else { return inserted }

        records.append(inserted)
        recordIndexByKey[key] = records.count - 1
        if records.count > capacity,
           let evictionIndex = records.indices.min(by: { records[$0].lastSeenSequence < records[$1].lastSeenSequence }) {
            let evictedKey = records[evictionIndex].key
            records.remove(at: evictionIndex)
            recordIndexByKey.removeValue(forKey: evictedKey)
            rebuildRecordIndexes(startingAt: evictionIndex)
        }
        return inserted
    }

    private mutating func rebuildRecordIndexes(startingAt startIndex: Int) {
        for index in startIndex..<records.count {
            recordIndexByKey[records[index].key] = index
        }
    }
}
