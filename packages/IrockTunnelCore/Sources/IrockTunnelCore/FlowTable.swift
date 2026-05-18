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
    public let host: String?

    public init(key: FlowKey, packetCount: Int, lastSeenSequence: Int, host: String? = nil) {
        self.key = key
        self.packetCount = packetCount
        self.lastSeenSequence = lastSeenSequence
        self.host = host
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

    public mutating func record(_ packet: ParsedPacket, host: String? = nil) -> FlowRecord {
        let key = FlowKey(packet)
        sequence += 1

        if let index = recordIndexByKey[key] {
            let updated = FlowRecord(key: key, packetCount: records[index].packetCount + 1, lastSeenSequence: sequence, host: host ?? records[index].host)
            records[index] = updated
            return updated
        }

        let inserted = FlowRecord(key: key, packetCount: 1, lastSeenSequence: sequence, host: host)
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

public struct DNSSniffer {
    public static func sniff(packet: ParsedPacket) -> (ip: IPAddress, host: String)? {
        guard packet.isDNSCandidate else { return nil }
        let payload = packet.udpPayload
        guard payload.count > 12 else { return nil }
        
        let qdcount = (Int(payload[4]) << 8) | Int(payload[5])
        guard qdcount > 0 else { return nil }
        
        var offset = 12
        var name = ""
        while offset < payload.count {
            let length = Int(payload[offset])
            if length == 0 {
                offset += 1
                break
            }
            if length & 0xc0 == 0xc0 {
                offset += 2
                break
            }
            offset += 1
            guard offset + length <= payload.count else { return nil }
            if !name.isEmpty { name += "." }
            let label = String(decoding: payload[offset..<offset+length], as: UTF8.self)
            name += label
            offset += length
        }
        guard !name.isEmpty else { return nil }
        // Simple sniffer just to associate the query name with the DNS request flow
        // In a real implementation, you'd parse the DNS response to associate the IP.
        // For a local tunnel, often the destination IP is tracked if we implement a fake IP pool,
        // or we sniff DNS responses.
        return nil // Placeholder since we need DNS responses, not requests, to map IP -> Host
    }
}
