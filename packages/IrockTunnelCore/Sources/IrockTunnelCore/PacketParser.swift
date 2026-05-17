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

        switch bytes[0] >> 4 {
        case 4:
            return try parseIPv4(packet, bytes: bytes)
        case 6:
            return try parseIPv6(packet, bytes: bytes)
        default:
            throw PacketParseError.unsupportedIPVersion
        }
    }

    private func parseIPv4(_ packet: Packet, bytes: [UInt8]) throws -> ParsedPacket {
        let headerLength = Int(bytes[0] & 0x0f) * 4
        guard headerLength >= 20 else { throw PacketParseError.truncatedHeader }
        guard bytes.count >= headerLength else { throw PacketParseError.truncatedHeader }
        guard bytes.count >= headerLength + 4 else { throw PacketParseError.truncatedHeader }

        guard let transportProtocol = TransportProtocol(rawValue: bytes[9]) else {
            throw PacketParseError.unsupportedTransportProtocol
        }
        guard transportProtocol != .udp || bytes.count >= headerLength + 8 else { throw PacketParseError.truncatedHeader }

        let sourceIP = IPAddress.v4(bytes[12], bytes[13], bytes[14], bytes[15])
        let destinationIP = IPAddress.v4(bytes[16], bytes[17], bytes[18], bytes[19])
        return try parsedPacket(packet, bytes: bytes, headerLength: headerLength, sourceIP: sourceIP, destinationIP: destinationIP, transportProtocol: transportProtocol)
    }

    private func parseIPv6(_ packet: Packet, bytes: [UInt8]) throws -> ParsedPacket {
        let headerLength = 40
        guard bytes.count >= headerLength else { throw PacketParseError.truncatedHeader }
        let payloadLength = readUInt16(bytes, at: 4)
        guard bytes.count >= headerLength + payloadLength else { throw PacketParseError.truncatedHeader }
        guard bytes.count >= headerLength + 4 else { throw PacketParseError.truncatedHeader }

        guard let transportProtocol = TransportProtocol(rawValue: bytes[6]) else {
            throw PacketParseError.unsupportedTransportProtocol
        }
        guard transportProtocol != .udp || bytes.count >= headerLength + 8 else { throw PacketParseError.truncatedHeader }
        guard let sourceAddress = Packet.parseIPv6AddressString(bytes[8..<24]), let destinationAddress = Packet.parseIPv6AddressString(bytes[24..<40]) else {
            throw PacketParseError.truncatedHeader
        }

        return try parsedPacket(packet, bytes: bytes, headerLength: headerLength, sourceIP: .v6(sourceAddress), destinationIP: .v6(destinationAddress), transportProtocol: transportProtocol)
    }

    private func parsedPacket(_ packet: Packet, bytes: [UInt8], headerLength: Int, sourceIP: IPAddress, destinationIP: IPAddress, transportProtocol: TransportProtocol) throws -> ParsedPacket {
        let sourcePort = readUInt16(bytes, at: headerLength)
        let destinationPort = readUInt16(bytes, at: headerLength + 2)
        let udpPayload = try udpPayload(bytes: bytes, headerLength: headerLength, transportProtocol: transportProtocol)
        let transportPayload = try transportPayload(bytes: bytes, headerLength: headerLength, transportProtocol: transportProtocol)

        return ParsedPacket(
            packet: packet,
            sourceIP: sourceIP,
            destinationIP: destinationIP,
            transportProtocol: transportProtocol,
            sourcePort: sourcePort,
            destinationPort: destinationPort,
            isDNSCandidate: transportProtocol == .udp && destinationPort == 53,
            udpPayload: udpPayload,
            transportPayload: transportPayload
        )
    }

    private func udpPayload(bytes: [UInt8], headerLength: Int, transportProtocol: TransportProtocol) throws -> [UInt8] {
        guard transportProtocol == .udp else { return [] }
        let udpLength = readUInt16(bytes, at: headerLength + 4)
        guard udpLength >= 8 else { throw PacketParseError.truncatedHeader }
        let udpEnd = headerLength + udpLength
        guard bytes.count >= udpEnd else { throw PacketParseError.truncatedHeader }
        return Array(bytes[(headerLength + 8)..<udpEnd])
    }

    private func transportPayload(bytes: [UInt8], headerLength: Int, transportProtocol: TransportProtocol) throws -> [UInt8] {
        switch transportProtocol {
        case .tcp:
            guard bytes.count >= headerLength + 20 else { throw PacketParseError.truncatedHeader }
            let tcpHeaderLength = Int(bytes[headerLength + 12] >> 4) * 4
            guard tcpHeaderLength >= 20 else { throw PacketParseError.truncatedHeader }
            let payloadOffset = headerLength + tcpHeaderLength
            guard bytes.count >= payloadOffset else { throw PacketParseError.truncatedHeader }
            return Array(bytes[payloadOffset..<bytes.count])
        case .udp:
            return try udpPayload(bytes: bytes, headerLength: headerLength, transportProtocol: transportProtocol)
        }
    }

    private func readUInt16(_ bytes: [UInt8], at offset: Int) -> Int {
        (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
    }
}
