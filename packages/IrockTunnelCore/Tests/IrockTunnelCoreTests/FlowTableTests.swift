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
}
