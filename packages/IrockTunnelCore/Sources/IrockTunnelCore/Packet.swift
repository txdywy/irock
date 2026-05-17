import Darwin

public struct Packet: Equatable, Hashable, Sendable {
    public let id: String
    public let bytes: [UInt8]

    public init(id: String, bytes: [UInt8]) {
        self.id = id
        self.bytes = bytes
    }
}

public enum IPAddress: Equatable, Hashable, Sendable {
    case v4(UInt8, UInt8, UInt8, UInt8)
    case v6(String)

    public var stringValue: String {
        switch self {
        case let .v4(a, b, c, d):
            return "\(a).\(b).\(c).\(d)"
        case let .v6(address):
            return address
        }
    }
}

public enum TransportProtocol: UInt8, Equatable, Hashable, Sendable {
    case tcp = 6
    case udp = 17
}

public struct ParsedPacket: Equatable, Hashable, Sendable {
    public let packet: Packet
    public let sourceIP: IPAddress
    public let destinationIP: IPAddress
    public let transportProtocol: TransportProtocol
    public let sourcePort: Int
    public let destinationPort: Int
    public let isDNSCandidate: Bool
    public let udpPayload: [UInt8]
    public let transportPayload: [UInt8]

    public init(packet: Packet, sourceIP: IPAddress, destinationIP: IPAddress, transportProtocol: TransportProtocol, sourcePort: Int, destinationPort: Int, isDNSCandidate: Bool, udpPayload: [UInt8] = [], transportPayload: [UInt8] = []) {
        self.packet = packet
        self.sourceIP = sourceIP
        self.destinationIP = destinationIP
        self.transportProtocol = transportProtocol
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.isDNSCandidate = isDNSCandidate
        self.udpPayload = udpPayload
        self.transportPayload = transportPayload
    }
}

public extension Packet {
    static func ipv4TCP(id: String, source: IPAddress, destination: IPAddress, sourcePort: Int, destinationPort: Int, payload: [UInt8] = []) -> Packet {
        ipv4Packet(id: id, source: source, destination: destination, transportProtocol: .tcp, sourcePort: sourcePort, destinationPort: destinationPort, payload: payload)
    }

    static func ipv4UDP(id: String, source: IPAddress, destination: IPAddress, sourcePort: Int, destinationPort: Int, payload: [UInt8] = []) -> Packet {
        ipv4Packet(id: id, source: source, destination: destination, transportProtocol: .udp, sourcePort: sourcePort, destinationPort: destinationPort, payload: payload)
    }

    static func ipv6UDP(id: String, source: IPAddress, destination: IPAddress, sourcePort: Int, destinationPort: Int, payload: [UInt8] = []) -> Packet {
        ipv6Packet(id: id, source: source, destination: destination, transportProtocol: .udp, sourcePort: sourcePort, destinationPort: destinationPort, payload: payload)
    }

    static func udpResponse(id: String, request: ParsedPacket, payload: [UInt8]) -> Packet {
        switch (request.destinationIP, request.sourceIP) {
        case (.v4, .v4):
            return ipv4UDP(id: id, source: request.destinationIP, destination: request.sourceIP, sourcePort: request.destinationPort, destinationPort: request.sourcePort, payload: payload)
        case (.v6, .v6):
            return ipv6UDP(id: id, source: request.destinationIP, destination: request.sourceIP, sourcePort: request.destinationPort, destinationPort: request.sourcePort, payload: payload)
        default:
            return Packet(id: id, bytes: [])
        }
    }

    static func ipv4UDPResponse(id: String, request: ParsedPacket, payload: [UInt8]) -> Packet {
        udpResponse(id: id, request: request, payload: payload)
    }

    private static func ipv4Packet(id: String, source: IPAddress, destination: IPAddress, transportProtocol: TransportProtocol, sourcePort: Int, destinationPort: Int, payload: [UInt8] = []) -> Packet {
        guard case let .v4(sourceA, sourceB, sourceC, sourceD) = source,
              case let .v4(destinationA, destinationB, destinationC, destinationD) = destination else {
            return Packet(id: id, bytes: [])
        }

        let transportHeaderLength = transportProtocol == .udp ? 8 : 20
        let totalLength = 20 + transportHeaderLength + payload.count
        var bytes = [UInt8](repeating: 0, count: totalLength)
        bytes[0] = 0x45
        bytes[2] = UInt8((totalLength >> 8) & 0xff)
        bytes[3] = UInt8(totalLength & 0xff)
        bytes[8] = 64
        bytes[9] = transportProtocol.rawValue
        bytes[12] = sourceA
        bytes[13] = sourceB
        bytes[14] = sourceC
        bytes[15] = sourceD
        bytes[16] = destinationA
        bytes[17] = destinationB
        bytes[18] = destinationC
        bytes[19] = destinationD
        writeUInt16(sourcePort, into: &bytes, at: 20)
        writeUInt16(destinationPort, into: &bytes, at: 22)
        if transportProtocol == .udp {
            writeUInt16(transportHeaderLength + payload.count, into: &bytes, at: 24)
        } else {
            bytes[32] = 0x50
        }
        if !payload.isEmpty {
            let payloadOffset = 20 + transportHeaderLength
            bytes.replaceSubrange(payloadOffset..<payloadOffset + payload.count, with: payload)
        }
        writeUInt16(Int(ipv4HeaderChecksum(bytes)), into: &bytes, at: 10)
        return Packet(id: id, bytes: bytes)
    }

    private static func ipv6Packet(id: String, source: IPAddress, destination: IPAddress, transportProtocol: TransportProtocol, sourcePort: Int, destinationPort: Int, payload: [UInt8] = []) -> Packet {
        guard case let .v6(sourceAddress) = source,
              case let .v6(destinationAddress) = destination,
              let sourceBytes = ipv6AddressBytes(sourceAddress),
              let destinationBytes = ipv6AddressBytes(destinationAddress) else {
            return Packet(id: id, bytes: [])
        }

        let transportHeaderLength = transportProtocol == .udp ? 8 : 20
        let payloadLength = transportHeaderLength + payload.count
        var bytes = [UInt8](repeating: 0, count: 40 + payloadLength)
        bytes[0] = 0x60
        writeUInt16(payloadLength, into: &bytes, at: 4)
        bytes[6] = transportProtocol.rawValue
        bytes[7] = 64
        bytes.replaceSubrange(8..<24, with: sourceBytes)
        bytes.replaceSubrange(24..<40, with: destinationBytes)
        writeUInt16(sourcePort, into: &bytes, at: 40)
        writeUInt16(destinationPort, into: &bytes, at: 42)
        if transportProtocol == .udp {
            writeUInt16(payloadLength, into: &bytes, at: 44)
        } else {
            bytes[52] = 0x50
        }
        if !payload.isEmpty {
            let payloadOffset = 40 + transportHeaderLength
            bytes.replaceSubrange(payloadOffset..<payloadOffset + payload.count, with: payload)
        }
        return Packet(id: id, bytes: bytes)
    }

    private static func ipv4HeaderChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum = 0
        for index in stride(from: 0, to: 20, by: 2) {
            sum += (Int(bytes[index]) << 8) | Int(bytes[index + 1])
            while sum > 0xffff {
                sum = (sum & 0xffff) + (sum >> 16)
            }
        }
        return UInt16((~sum) & 0xffff)
    }

    private static func ipv6AddressBytes(_ address: String) -> [UInt8]? {
        var storage = in6_addr()
        guard address.withCString({ inet_pton(AF_INET6, $0, &storage) }) == 1 else { return nil }
        return withUnsafeBytes(of: storage) { Array($0) }
    }

    private static func ipv6AddressString(_ bytes: ArraySlice<UInt8>) -> String? {
        guard bytes.count == 16 else { return nil }
        var storage = in6_addr()
        withUnsafeMutableBytes(of: &storage) { storageBytes in
            for (index, byte) in bytes.enumerated() {
                storageBytes[index] = byte
            }
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &storage, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buffer)
    }

    static func parseIPv6AddressString(_ bytes: ArraySlice<UInt8>) -> String? {
        ipv6AddressString(bytes)
    }

    private static func writeUInt16(_ value: Int, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xff)
        bytes[offset + 1] = UInt8(value & 0xff)
    }
}
