import XCTest
@testable import IrockTunnelCore

final class PacketParserTests: XCTestCase {
    func testParsesIPv4TCPPacketEndpointFields() throws {
        let packet = Packet.ipv4TCP(
            id: "tcp-1",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443
        )

        let parsed = try PacketParser().parse(packet)

        XCTAssertEqual(parsed.packet.id, "tcp-1")
        XCTAssertEqual(parsed.sourceIP, .v4(10, 0, 0, 2))
        XCTAssertEqual(parsed.destinationIP, .v4(93, 184, 216, 34))
        XCTAssertEqual(parsed.transportProtocol, .tcp)
        XCTAssertEqual(parsed.sourcePort, 51_234)
        XCTAssertEqual(parsed.destinationPort, 443)
        XCTAssertFalse(parsed.isDNSCandidate)
    }

    func testParsesIPv4TCPPayloadAfterTCPHeader() throws {
        let packet = Packet.ipv4TCP(
            id: "tcp-payload",
            source: .v4(10, 0, 0, 2),
            destination: .v4(93, 184, 216, 34),
            sourcePort: 51_234,
            destinationPort: 443,
            payload: [0xde, 0xad, 0xbe, 0xef]
        )

        let parsed = try PacketParser().parse(packet)

        XCTAssertEqual(packet.bytes[32] >> 4, 5)
        XCTAssertEqual(parsed.transportPayload, [0xde, 0xad, 0xbe, 0xef])
    }

    func testParsesIPv4UDPDNSCandidate() throws {
        let packet = Packet.ipv4UDP(
            id: "dns-1",
            source: .v4(10, 0, 0, 2),
            destination: .v4(1, 1, 1, 1),
            sourcePort: 55_555,
            destinationPort: 53
        )

        let parsed = try PacketParser().parse(packet)

        XCTAssertEqual(parsed.transportProtocol, .udp)
        XCTAssertEqual(parsed.destinationPort, 53)
        XCTAssertTrue(parsed.isDNSCandidate)
    }

    func testParsesIPv4UDPPayloadBytes() throws {
        let packet = Packet.ipv4UDP(
            id: "udp-1",
            source: .v4(10, 0, 0, 2),
            destination: .v4(1, 1, 1, 1),
            sourcePort: 55_555,
            destinationPort: 53,
            payload: [0xde, 0xad, 0xbe, 0xef]
        )

        let parsed = try PacketParser().parse(packet)

        XCTAssertEqual(parsed.udpPayload, [0xde, 0xad, 0xbe, 0xef])
    }

    func testRejectsIPv4UDPWhenDeclaredLengthExceedsPacketBytes() {
        var bytes = Packet.ipv4UDP(
            id: "udp-bad-length",
            source: .v4(10, 0, 0, 2),
            destination: .v4(1, 1, 1, 1),
            sourcePort: 55_555,
            destinationPort: 53,
            payload: [0xde, 0xad]
        ).bytes
        bytes[24] = 0
        bytes[25] = 16

        XCTAssertThrowsError(try PacketParser().parse(Packet(id: "udp-bad-length", bytes: bytes))) { error in
            XCTAssertEqual(error as? PacketParseError, .truncatedHeader)
        }
    }

    func testBuildsIPv4UDPResponsePacketFromParsedRequest() throws {
        let request = Packet.ipv4UDP(
            id: "udp-request",
            source: .v4(10, 0, 0, 2),
            destination: .v4(1, 1, 1, 1),
            sourcePort: 55_555,
            destinationPort: 53,
            payload: [0x01, 0x02]
        )
        let parsed = try PacketParser().parse(request)

        let response = Packet.ipv4UDPResponse(id: "udp-response", request: parsed, payload: [0x03, 0x04, 0x05])
        let responseParsed = try PacketParser().parse(response)

        XCTAssertEqual(responseParsed.sourceIP, .v4(1, 1, 1, 1))
        XCTAssertEqual(responseParsed.destinationIP, .v4(10, 0, 0, 2))
        XCTAssertEqual(responseParsed.sourcePort, 53)
        XCTAssertEqual(responseParsed.destinationPort, 55_555)
        XCTAssertEqual(responseParsed.udpPayload, [0x03, 0x04, 0x05])
        XCTAssertEqual(ipv4HeaderChecksum(response.bytes), 0)
        XCTAssertNotEqual(response.bytes[10...11], [0, 0])
    }

    func testRejectsTooShortPacket() {
        let packet = Packet(id: "short", bytes: [0x45, 0x00])

        XCTAssertThrowsError(try PacketParser().parse(packet)) { error in
            XCTAssertEqual(error as? PacketParseError, .tooShort)
        }
    }

    func testRejectsUnsupportedIPVersion() {
        var bytes = Packet.ipv4TCP(id: "bad-version", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 1_000, destinationPort: 443).bytes
        bytes[0] = 0x60

        XCTAssertThrowsError(try PacketParser().parse(Packet(id: "bad-version", bytes: bytes))) { error in
            XCTAssertEqual(error as? PacketParseError, .unsupportedIPVersion)
        }
    }

    func testRejectsUnsupportedTransportProtocol() {
        var bytes = Packet.ipv4TCP(id: "icmp", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 1_000, destinationPort: 443).bytes
        bytes[9] = 1

        XCTAssertThrowsError(try PacketParser().parse(Packet(id: "icmp", bytes: bytes))) { error in
            XCTAssertEqual(error as? PacketParseError, .unsupportedTransportProtocol)
        }
    }

    func testRejectsInvalidIPv4HeaderLength() {
        var bytes = Packet.ipv4TCP(id: "invalid-ihl", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 1_000, destinationPort: 443).bytes
        bytes[0] = 0x44

        XCTAssertThrowsError(try PacketParser().parse(Packet(id: "invalid-ihl", bytes: bytes))) { error in
            XCTAssertEqual(error as? PacketParseError, .truncatedHeader)
        }
    }

    func testRejectsTruncatedTransportHeader() {
        let packet = Packet(id: "truncated", bytes: Array(Packet.ipv4UDP(id: "udp", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 1_000, destinationPort: 53).bytes.prefix(22)))

        XCTAssertThrowsError(try PacketParser().parse(packet)) { error in
            XCTAssertEqual(error as? PacketParseError, .truncatedHeader)
        }
    }

    private func ipv4HeaderChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum = 0
        for index in stride(from: 0, to: 20, by: 2) {
            sum += (Int(bytes[index]) << 8) | Int(bytes[index + 1])
            while sum > 0xffff {
                sum = (sum & 0xffff) + (sum >> 16)
            }
        }
        return UInt16((~sum) & 0xffff)
    }
}
