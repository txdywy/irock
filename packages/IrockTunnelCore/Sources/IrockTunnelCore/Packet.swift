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

    public init(packet: Packet, sourceIP: IPAddress, destinationIP: IPAddress, transportProtocol: TransportProtocol, sourcePort: Int, destinationPort: Int, isDNSCandidate: Bool) {
        self.packet = packet
        self.sourceIP = sourceIP
        self.destinationIP = destinationIP
        self.transportProtocol = transportProtocol
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.isDNSCandidate = isDNSCandidate
    }
}

public extension Packet {
    static func ipv4TCP(id: String, source: IPAddress, destination: IPAddress, sourcePort: Int, destinationPort: Int) -> Packet {
        ipv4Packet(id: id, source: source, destination: destination, transportProtocol: .tcp, sourcePort: sourcePort, destinationPort: destinationPort)
    }

    static func ipv4UDP(id: String, source: IPAddress, destination: IPAddress, sourcePort: Int, destinationPort: Int) -> Packet {
        ipv4Packet(id: id, source: source, destination: destination, transportProtocol: .udp, sourcePort: sourcePort, destinationPort: destinationPort)
    }

    private static func ipv4Packet(id: String, source: IPAddress, destination: IPAddress, transportProtocol: TransportProtocol, sourcePort: Int, destinationPort: Int) -> Packet {
        guard case let .v4(sourceA, sourceB, sourceC, sourceD) = source,
              case let .v4(destinationA, destinationB, destinationC, destinationD) = destination else {
            return Packet(id: id, bytes: [])
        }

        var bytes = [UInt8](repeating: 0, count: 28)
        bytes[0] = 0x45
        bytes[2] = 0
        bytes[3] = UInt8(bytes.count)
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
        return Packet(id: id, bytes: bytes)
    }

    private static func writeUInt16(_ value: Int, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xff)
        bytes[offset + 1] = UInt8(value & 0xff)
    }
}
