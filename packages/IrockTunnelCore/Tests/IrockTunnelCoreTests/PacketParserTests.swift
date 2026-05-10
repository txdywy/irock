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

    func testRejectsTruncatedTransportHeader() {
        let packet = Packet(id: "truncated", bytes: Array(Packet.ipv4UDP(id: "udp", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 1_000, destinationPort: 53).bytes.prefix(22)))

        XCTAssertThrowsError(try PacketParser().parse(packet)) { error in
            XCTAssertEqual(error as? PacketParseError, .truncatedHeader)
        }
    }
}
