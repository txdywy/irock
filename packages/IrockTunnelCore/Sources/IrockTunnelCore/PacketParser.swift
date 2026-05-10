public enum PacketParseError: Error, Equatable, Sendable {
    case tooShort
    case unsupportedIPVersion
    case unsupportedTransportProtocol
    case truncatedHeader
}

public struct PacketParser: Sendable {
    public init() {}

    public func parse(_ packet: Packet) throws -> ParsedPacket {
        let bytes = packet.bytes
        guard bytes.count >= 20 else { throw PacketParseError.tooShort }

        let version = bytes[0] >> 4
        guard version == 4 else { throw PacketParseError.unsupportedIPVersion }

        let headerLength = Int(bytes[0] & 0x0f) * 4
        guard headerLength >= 20 else { throw PacketParseError.truncatedHeader }
        guard bytes.count >= headerLength else { throw PacketParseError.truncatedHeader }
        guard bytes.count >= headerLength + 4 else { throw PacketParseError.truncatedHeader }

        guard let transportProtocol = TransportProtocol(rawValue: bytes[9]) else {
            throw PacketParseError.unsupportedTransportProtocol
        }

        let sourceIP = IPAddress.v4(bytes[12], bytes[13], bytes[14], bytes[15])
        let destinationIP = IPAddress.v4(bytes[16], bytes[17], bytes[18], bytes[19])
        let sourcePort = readUInt16(bytes, at: headerLength)
        let destinationPort = readUInt16(bytes, at: headerLength + 2)

        return ParsedPacket(
            packet: packet,
            sourceIP: sourceIP,
            destinationIP: destinationIP,
            transportProtocol: transportProtocol,
            sourcePort: sourcePort,
            destinationPort: destinationPort,
            isDNSCandidate: transportProtocol == .udp && destinationPort == 53
        )
    }

    private func readUInt16(_ bytes: [UInt8], at offset: Int) -> Int {
        (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
    }
}
