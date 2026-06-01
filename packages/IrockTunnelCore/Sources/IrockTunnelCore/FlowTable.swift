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
        let ancount = (Int(payload[6]) << 8) | Int(payload[7])
        
        // Parse DNS query to extract domain name
        var offset = 12
        var queryName = ""
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
            if !queryName.isEmpty { queryName += "." }
            let label = String(decoding: payload[offset..<offset+length], as: UTF8.self)
            queryName += label
            offset += length
        }
        guard !queryName.isEmpty else { return nil }
        
        // If this is a DNS response (source port 53) and has answers, extract IP
        if packet.sourcePort == 53 && ancount > 0 {
            // Skip question section
            let qtype = (Int(payload[offset]) << 8) | Int(payload[offset + 1])
            let qclass = (Int(payload[offset + 2]) << 8) | Int(payload[offset + 3])
            offset += 4
            
            // Parse answer section
            for _ in 0..<ancount {
                guard offset + 12 <= payload.count else { break }
                
                // Skip name (handle compression)
                if payload[offset] & 0xc0 == 0xc0 {
                    offset += 2
                } else {
                    while offset < payload.count && payload[offset] != 0 {
                        offset += Int(payload[offset]) + 1
                    }
                    offset += 1
                }
                
                let atype = (Int(payload[offset]) << 8) | Int(payload[offset + 1])
                let aclass = (Int(payload[offset + 2]) << 8) | Int(payload[offset + 3])
                let ttl = (Int(payload[offset + 4]) << 24) | (Int(payload[offset + 5]) << 16) | (Int(payload[offset + 6]) << 8) | Int(payload[offset + 7])
                let rdlength = (Int(payload[offset + 8]) << 8) | Int(payload[offset + 9])
                offset += 10
                
                guard offset + rdlength <= payload.count else { break }
                
                // Type A record (IPv4)
                if atype == 1 && rdlength == 4 && aclass == 1 {
                    let ip = IPAddress.v4(payload[offset], payload[offset + 1], payload[offset + 2], payload[offset + 3])
                    return (ip: ip, host: queryName)
                }
                
                // Type AAAA record (IPv6)
                if atype == 28 && rdlength == 16 && aclass == 1 {
                    guard let ipv6Address = Packet.parseIPv6AddressString(payload[offset..<offset+16]) else {
                        offset += rdlength
                        continue
                    }
                    return (ip: .v6(ipv6Address), host: queryName)
                }
                
                offset += rdlength
            }
        }
        
        return nil
    }
}
