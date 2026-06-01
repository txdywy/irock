import XCTest
@testable import IrockTunnelCore

final class FlowTableTests: XCTestCase {
    func testFlowKeyUsesFiveTuple() throws {
        let packet = try PacketParser().parse(.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443))

        let key = FlowKey(packet)

        XCTAssertEqual(key.sourceIP, .v4(10, 0, 0, 2))
        XCTAssertEqual(key.sourcePort, 51_234)
        XCTAssertEqual(key.destinationIP, .v4(93, 184, 216, 34))
        XCTAssertEqual(key.destinationPort, 443)
        XCTAssertEqual(key.transportProtocol, .tcp)
    }

    func testRecordingSameFlowIncrementsPacketCount() throws {
        var table = FlowTable(capacity: 10)
        let packet = try PacketParser().parse(.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443))

        _ = table.record(packet)
        let record = table.record(packet)

        XCTAssertEqual(record.packetCount, 2)
        XCTAssertEqual(table.records.count, 1)
    }

    func testCapacityEvictsOldestFlow() throws {
        var table = FlowTable(capacity: 2)
        let first = try PacketParser().parse(.ipv4TCP(id: "first", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 1_001, destinationPort: 443))
        let second = try PacketParser().parse(.ipv4TCP(id: "second", source: .v4(10, 0, 0, 2), destination: .v4(2, 2, 2, 2), sourcePort: 1_002, destinationPort: 443))
        let third = try PacketParser().parse(.ipv4TCP(id: "third", source: .v4(10, 0, 0, 2), destination: .v4(3, 3, 3, 3), sourcePort: 1_003, destinationPort: 443))

        _ = table.record(first)
        _ = table.record(second)
        _ = table.record(third)

        XCTAssertNil(table.record(for: FlowKey(first)))
        XCTAssertNotNil(table.record(for: FlowKey(second)))
        XCTAssertNotNil(table.record(for: FlowKey(third)))
        XCTAssertEqual(table.records.count, 2)
    }

    func testCapacityEvictsLeastRecentlySeenFlow() throws {
        var table = FlowTable(capacity: 2)
        let first = try PacketParser().parse(.ipv4TCP(id: "first", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 1_001, destinationPort: 443))
        let second = try PacketParser().parse(.ipv4TCP(id: "second", source: .v4(10, 0, 0, 2), destination: .v4(2, 2, 2, 2), sourcePort: 1_002, destinationPort: 443))
        let third = try PacketParser().parse(.ipv4TCP(id: "third", source: .v4(10, 0, 0, 2), destination: .v4(3, 3, 3, 3), sourcePort: 1_003, destinationPort: 443))

        _ = table.record(first)
        _ = table.record(second)
        _ = table.record(first)
        _ = table.record(third)

        XCTAssertNotNil(table.record(for: FlowKey(first)))
        XCTAssertNil(table.record(for: FlowKey(second)))
        XCTAssertNotNil(table.record(for: FlowKey(third)))
        XCTAssertEqual(table.records.count, 2)
    }

    func testZeroCapacityDoesNotStoreRecords() throws {
        var table = FlowTable(capacity: 0)
        let packet = try PacketParser().parse(.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443))

        let record = table.record(packet)

        XCTAssertEqual(record.key, FlowKey(packet))
        XCTAssertTrue(table.records.isEmpty)
    }

    // MARK: - DNS Sniffer Tests

    func testDNSSnifferReturnsNilForNonDNSPacket() throws {
        let packet = try PacketParser().parse(.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443))

        let result = DNSSniffer.sniff(packet: packet)

        XCTAssertNil(result)
    }

    func testDNSSnifferReturnsNilForShortDNSPacket() throws {
        // Create a minimal UDP packet to port 53 with too short payload
        let shortPayload: [UInt8] = [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let packet = try PacketParser().parse(Packet.ipv4UDP(
            id: "dns-short",
            source: .v4(10, 0, 0, 2),
            destination: .v4(8, 8, 8, 8),
            sourcePort: 12345,
            destinationPort: 53,
            payload: shortPayload
        ))

        let result = DNSSniffer.sniff(packet: packet)

        XCTAssertNil(result)
    }

    func testDNSSnifferParsesDNSQueryDomain() throws {
        // Build a DNS query for "example.com"
        var dnsQuery: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x01, 0x00, // Flags: standard query
            0x00, 0x01, // Questions: 1
            0x00, 0x00, // Answers: 0
            0x00, 0x00, // Authority: 0
            0x00, 0x00, // Additional: 0
        ]
        // Query name: example.com
        dnsQuery.append(contentsOf: [0x07]) // length of "example"
        dnsQuery.append(contentsOf: Array("example".utf8))
        dnsQuery.append(contentsOf: [0x03]) // length of "com"
        dnsQuery.append(contentsOf: Array("com".utf8))
        dnsQuery.append(contentsOf: [0x00]) // end of name
        dnsQuery.append(contentsOf: [0x00, 0x01]) // Type A
        dnsQuery.append(contentsOf: [0x00, 0x01]) // Class IN

        let packet = try PacketParser().parse(Packet.ipv4UDP(
            id: "dns-query",
            source: .v4(10, 0, 0, 2),
            destination: .v4(8, 8, 8, 8),
            sourcePort: 12345,
            destinationPort: 53,
            payload: dnsQuery
        ))

        let result = DNSSniffer.sniff(packet: packet)

        // DNS query alone should return nil (need response to get IP)
        XCTAssertNil(result)
    }

    func testDNSSnifferParsesDNSResponseWithARecord() throws {
        // Build a DNS response for "example.com" -> 93.184.216.34
        var dnsResponse: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x81, 0x80, // Flags: response, recursion available
            0x00, 0x01, // Questions: 1
            0x00, 0x01, // Answers: 1
            0x00, 0x00, // Authority: 0
            0x00, 0x00, // Additional: 0
        ]
        // Query name: example.com
        dnsResponse.append(contentsOf: [0x07]) // length of "example"
        dnsResponse.append(contentsOf: Array("example".utf8))
        dnsResponse.append(contentsOf: [0x03]) // length of "com"
        dnsResponse.append(contentsOf: Array("com".utf8))
        dnsResponse.append(contentsOf: [0x00]) // end of name
        dnsResponse.append(contentsOf: [0x00, 0x01]) // Type A
        dnsResponse.append(contentsOf: [0x00, 0x01]) // Class IN

        // Answer section
        dnsResponse.append(contentsOf: [0xc0, 0x0c]) // Name pointer to offset 12
        dnsResponse.append(contentsOf: [0x00, 0x01]) // Type A
        dnsResponse.append(contentsOf: [0x00, 0x01]) // Class IN
        dnsResponse.append(contentsOf: [0x00, 0x00, 0x00, 0x3c]) // TTL: 60
        dnsResponse.append(contentsOf: [0x00, 0x04]) // RDLENGTH: 4
        dnsResponse.append(contentsOf: [93, 184, 216, 34]) // RDATA: 93.184.216.34

        let packet = try PacketParser().parse(Packet.ipv4UDP(
            id: "dns-response",
            source: .v4(8, 8, 8, 8),
            destination: .v4(10, 0, 0, 2),
            sourcePort: 53,
            destinationPort: 12345,
            payload: dnsResponse
        ))

        let result = DNSSniffer.sniff(packet: packet)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "example.com")
        XCTAssertEqual(result?.ip, .v4(93, 184, 216, 34))
    }

    func testDNSSnifferParsesDNSResponseWithAAAARecord() throws {
        // Build a DNS response for "example.com" -> 2606:2800:220:1:248:1893:25c8:1946
        var dnsResponse: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x81, 0x80, // Flags: response, recursion available
            0x00, 0x01, // Questions: 1
            0x00, 0x01, // Answers: 1
            0x00, 0x00, // Authority: 0
            0x00, 0x00, // Additional: 0
        ]
        // Query name: example.com
        dnsResponse.append(contentsOf: [0x07]) // length of "example"
        dnsResponse.append(contentsOf: Array("example".utf8))
        dnsResponse.append(contentsOf: [0x03]) // length of "com"
        dnsResponse.append(contentsOf: Array("com".utf8))
        dnsResponse.append(contentsOf: [0x00]) // end of name
        dnsResponse.append(contentsOf: [0x00, 0x1c]) // Type AAAA
        dnsResponse.append(contentsOf: [0x00, 0x01]) // Class IN

        // Answer section
        dnsResponse.append(contentsOf: [0xc0, 0x0c]) // Name pointer to offset 12
        dnsResponse.append(contentsOf: [0x00, 0x1c]) // Type AAAA
        dnsResponse.append(contentsOf: [0x00, 0x01]) // Class IN
        dnsResponse.append(contentsOf: [0x00, 0x00, 0x00, 0x3c]) // TTL: 60
        dnsResponse.append(contentsOf: [0x00, 0x10]) // RDLENGTH: 16
        // RDATA: 2606:2800:220:1:248:1893:25c8:1946
        dnsResponse.append(contentsOf: [0x26, 0x06, 0x28, 0x00, 0x02, 0x20, 0x00, 0x01])
        dnsResponse.append(contentsOf: [0x02, 0x48, 0x18, 0x93, 0x25, 0xc8, 0x19, 0x46])

        let packet = try PacketParser().parse(Packet.ipv4UDP(
            id: "dns-response-aaaa",
            source: .v4(8, 8, 8, 8),
            destination: .v4(10, 0, 0, 2),
            sourcePort: 53,
            destinationPort: 12345,
            payload: dnsResponse
        ))

        let result = DNSSniffer.sniff(packet: packet)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "example.com")
        if case .v6(let address) = result?.ip {
            XCTAssertEqual(address, "2606:2800:220:1:248:1893:25c8:1946")
        } else {
            XCTFail("Expected IPv6 address")
        }
    }
}
