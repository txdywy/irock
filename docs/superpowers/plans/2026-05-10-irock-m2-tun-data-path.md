# irock M2 TUN Data Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `IrockTunnelCore`, a SwiftPM-testable TUN data path core that runs mock packet batches through parse, flow tracking, route decision, action generation, and writer output.

**Architecture:** M2 adds a new SwiftPM package target that depends only on `IrockCore` and `IrockRouting`. It deliberately avoids `NetworkExtension`, Xcode target creation, protocol adapters, real outbound I/O, DNS resolution, and benchmark work. Future Packet Tunnel extensions will adapt Apple `packetFlow` into the `PacketReader` / `PacketWriter` boundary and call `PacketTunnelRuntime`.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, `IrockCore`, `IrockRouting`.

---

## File Structure

M2 creates and modifies these files:

```text
Package.swift
README.md
CLAUDE.md
packages/IrockTunnelCore/Sources/IrockTunnelCore/IrockTunnelCore.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/Packet.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketParser.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/FlowTable.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketProcessor.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/InMemoryPacketIO.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/IrockTunnelCoreTests.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketParserTests.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/FlowTableTests.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketProcessorTests.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeConfigurationTests.swift
```

Responsibilities:

- `IrockTunnelCore.swift`: module marker only.
- `Packet.swift`: packet value, parsed packet value, IP address, transport protocol, packet fixture builders for tests and future callers.
- `PacketParser.swift`: IPv4 TCP/UDP parser and parse errors.
- `FlowTable.swift`: flow key, flow record, bounded flow table.
- `PacketProcessor.swift`: parse → flow → route/action conversion.
- `PacketTunnelRuntime.swift`: single-batch runtime orchestration and summary.
- `TunnelRuntimeConfiguration.swift`: frozen runtime inputs and limits.
- `InMemoryPacketIO.swift`: XCTest-friendly reader/writer implementations.

---

### Task 1: Add IrockTunnelCore package target

**Files:**
- Modify: `Package.swift`
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/IrockTunnelCore.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/IrockTunnelCoreTests.swift`

- [ ] **Step 1: Write the failing package test**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/IrockTunnelCoreTests.swift`:

```swift
import XCTest
@testable import IrockTunnelCore

final class IrockTunnelCoreTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(IrockTunnelCoreModule.name, "IrockTunnelCore")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter IrockTunnelCoreTests
```

Expected: FAIL because the `IrockTunnelCore` target does not exist.

- [ ] **Step 3: Add package product and target**

Modify `Package.swift`.

Add this product after `IrockAppFeature`:

```swift
.library(name: "IrockTunnelCore", targets: ["IrockTunnelCore"])
```

Add these targets after `IrockAppFeatureTests`:

```swift
.target(
    name: "IrockTunnelCore",
    dependencies: ["IrockCore", "IrockRouting"],
    path: "packages/IrockTunnelCore/Sources/IrockTunnelCore"
),
.testTarget(
    name: "IrockTunnelCoreTests",
    dependencies: ["IrockTunnelCore"],
    path: "packages/IrockTunnelCore/Tests/IrockTunnelCoreTests"
)
```

Keep valid Swift commas between array entries.

- [ ] **Step 4: Add minimal source**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/IrockTunnelCore.swift`:

```swift
public enum IrockTunnelCoreModule {
    public static let name = "IrockTunnelCore"
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter IrockTunnelCoreTests
swift test
```

Expected: `IrockTunnelCoreTests` passes and the full suite passes.

- [ ] **Step 6: Commit**

```bash
git add Package.swift packages/IrockTunnelCore
git commit -m "chore: add tunnel core package"
```

---

### Task 2: Add packet model and IPv4 parser

**Files:**
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/Packet.swift`
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketParser.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketParserTests.swift`

- [ ] **Step 1: Write parser tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run parser tests to verify failure**

Run:

```bash
swift test --filter PacketParserTests
```

Expected: FAIL because `Packet`, `PacketParser`, and related types are missing.

- [ ] **Step 3: Implement packet values**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/Packet.swift`:

```swift
public struct Packet: Equatable, Sendable {
    public let id: String
    public let bytes: [UInt8]

    public init(id: String, bytes: [UInt8]) {
        self.id = id
        self.bytes = bytes
    }
}

public enum IPAddress: Equatable, Hashable, Sendable {
    case v4(UInt8, UInt8, UInt8, UInt8)

    public var stringValue: String {
        switch self {
        case let .v4(a, b, c, d):
            return "\(a).\(b).\(c).\(d)"
        }
    }
}

public enum TransportProtocol: UInt8, Equatable, Sendable {
    case tcp = 6
    case udp = 17
}

public struct ParsedPacket: Equatable, Sendable {
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
```

- [ ] **Step 4: Implement parser**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketParser.swift`:

```swift
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
```

- [ ] **Step 5: Run parser tests and full suite**

Run:

```bash
swift test --filter PacketParserTests
swift test
```

Expected: parser tests pass and full suite passes.

- [ ] **Step 6: Commit**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/Packet.swift packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketParser.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketParserTests.swift
git commit -m "feat: add packet parser baseline"
```

---

### Task 3: Add bounded flow table

**Files:**
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/FlowTable.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/FlowTableTests.swift`

- [ ] **Step 1: Write flow table tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/FlowTableTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run flow tests to verify failure**

Run:

```bash
swift test --filter FlowTableTests
```

Expected: FAIL because `FlowKey`, `FlowRecord`, and `FlowTable` are missing.

- [ ] **Step 3: Implement flow table**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/FlowTable.swift`:

```swift
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

    public init(key: FlowKey, packetCount: Int, lastSeenSequence: Int) {
        self.key = key
        self.packetCount = packetCount
        self.lastSeenSequence = lastSeenSequence
    }
}

public struct FlowTable: Equatable, Sendable {
    public private(set) var records: [FlowRecord]
    public let capacity: Int
    private var sequence: Int

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.records = []
        self.sequence = 0
    }

    public func record(for key: FlowKey) -> FlowRecord? {
        records.first { $0.key == key }
    }

    public mutating func record(_ packet: ParsedPacket) -> FlowRecord {
        let key = FlowKey(packet)
        sequence += 1

        if let index = records.firstIndex(where: { $0.key == key }) {
            let updated = FlowRecord(key: key, packetCount: records[index].packetCount + 1, lastSeenSequence: sequence)
            records[index] = updated
            return updated
        }

        let inserted = FlowRecord(key: key, packetCount: 1, lastSeenSequence: sequence)
        guard capacity > 0 else { return inserted }

        records.append(inserted)
        if records.count > capacity {
            records.removeFirst(records.count - capacity)
        }
        return inserted
    }
}
```

- [ ] **Step 4: Run flow tests and full suite**

Run:

```bash
swift test --filter FlowTableTests
swift test
```

Expected: flow tests pass and full suite passes.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/FlowTable.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/FlowTableTests.swift
git commit -m "feat: add bounded flow table"
```

---

### Task 4: Add runtime configuration and packet processor

**Files:**
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift`
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketProcessor.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketProcessorTests.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeConfigurationTests.swift`

- [ ] **Step 1: Write configuration tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeConfigurationTests.swift`:

```swift
import XCTest
import IrockCore
import IrockRouting
@testable import IrockTunnelCore

final class TunnelRuntimeConfigurationTests: XCTestCase {
    func testConfigurationConsumesRuntimeSnapshotRouteModeAndLimits() {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled),
            routeMode: .globalProxy,
            logLevel: .user
        )

        let configuration = TunnelRuntimeConfiguration(snapshot: snapshot, routingEngine: RoutingEngine(rules: [.final(.reject)]), batchLimit: 32, flowLimit: 128)

        XCTAssertEqual(configuration.routeMode, .globalProxy)
        XCTAssertEqual(configuration.batchLimit, 32)
        XCTAssertEqual(configuration.flowLimit, 128)
    }
}
```

- [ ] **Step 2: Write processor tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketProcessorTests.swift`:

```swift
import XCTest
import IrockCore
import IrockRouting
@testable import IrockTunnelCore

final class PacketProcessorTests: XCTestCase {
    func testGlobalProxyModeReturnsProxyAction() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.reject)]))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)

        let result = processor.process(packet)

        XCTAssertEqual(result.action, .proxy(FlowKey(sourceIP: .v4(10, 0, 0, 2), sourcePort: 51_234, destinationIP: .v4(93, 184, 216, 34), destinationPort: 443, transportProtocol: .tcp)))
    }

    func testDirectModeReturnsDirectAction() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .direct, rules: [.final(.reject)]))
        let packet = Packet.ipv4UDP(id: "udp-1", source: .v4(10, 0, 0, 2), destination: .v4(1, 1, 1, 1), sourcePort: 55_555, destinationPort: 53)

        let result = processor.process(packet)

        XCTAssertEqual(result.action, .direct(FlowKey(sourceIP: .v4(10, 0, 0, 2), sourcePort: 55_555, destinationIP: .v4(1, 1, 1, 1), destinationPort: 53, transportProtocol: .udp)))
        XCTAssertEqual(result.parsedPacket?.isDNSCandidate, true)
    }

    func testRuleBasedModeReturnsRejectFromRoutingEngine() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .ruleBased, rules: [.final(.reject)]))
        let packet = Packet.ipv4TCP(id: "tcp-2", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)

        let result = processor.process(packet)

        XCTAssertEqual(result.action, .reject(FlowKey(sourceIP: .v4(10, 0, 0, 2), sourcePort: 51_234, destinationIP: .v4(93, 184, 216, 34), destinationPort: 443, transportProtocol: .tcp)))
    }

    func testMalformedPacketDropsWithParseFailedReason() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.proxy)]))

        let result = processor.process(Packet(id: "bad", bytes: [0x45]))

        XCTAssertEqual(result.action, .drop(.parseFailed(.tooShort)))
    }

    func testUnsupportedProtocolDropsWithUnsupportedProtocolReason() {
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy, rules: [.final(.proxy)]))
        var bytes = Packet.ipv4TCP(id: "icmp", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 1_000, destinationPort: 443).bytes
        bytes[9] = 1

        let result = processor.process(Packet(id: "icmp", bytes: bytes))

        XCTAssertEqual(result.action, .drop(.unsupportedProtocol))
    }

    private func configuration(routeMode: RouteMode, rules: [RoutingRule]) -> TunnelRuntimeConfiguration {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled),
            routeMode: routeMode,
            logLevel: .user
        )
        return TunnelRuntimeConfiguration(snapshot: snapshot, routingEngine: RoutingEngine(rules: rules), batchLimit: 16, flowLimit: 32)
    }
}
```

- [ ] **Step 3: Run configuration and processor tests to verify failure**

Run:

```bash
swift test --filter 'TunnelRuntimeConfigurationTests|PacketProcessorTests'
```

Expected: FAIL because configuration, processor, action, drop reason, and result types are missing.

- [ ] **Step 4: Implement runtime configuration**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift`:

```swift
import IrockCore
import IrockRouting

public struct TunnelRuntimeConfiguration: Sendable {
    public let snapshot: RuntimeSnapshot
    public let routingEngine: RoutingEngine
    public let batchLimit: Int
    public let flowLimit: Int

    public var routeMode: RouteMode {
        snapshot.routeMode
    }

    public init(snapshot: RuntimeSnapshot, routingEngine: RoutingEngine, batchLimit: Int, flowLimit: Int) {
        self.snapshot = snapshot
        self.routingEngine = routingEngine
        self.batchLimit = max(0, batchLimit)
        self.flowLimit = max(0, flowLimit)
    }
}
```

- [ ] **Step 5: Implement processor**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketProcessor.swift`:

```swift
import IrockCore
import IrockRouting

public enum PacketDropReason: Equatable, Sendable {
    case parseFailed(PacketParseError)
    case unsupportedProtocol
    case flowLimitExceeded
    case noRoute
}

public enum PacketAction: Equatable, Sendable {
    case direct(FlowKey)
    case proxy(FlowKey)
    case reject(FlowKey)
    case drop(PacketDropReason)
}

public struct PacketProcessingResult: Equatable, Sendable {
    public let packet: Packet
    public let parsedPacket: ParsedPacket?
    public let flowKey: FlowKey?
    public let action: PacketAction

    public init(packet: Packet, parsedPacket: ParsedPacket?, flowKey: FlowKey?, action: PacketAction) {
        self.packet = packet
        self.parsedPacket = parsedPacket
        self.flowKey = flowKey
        self.action = action
    }
}

public struct PacketProcessor: Sendable {
    private let configuration: TunnelRuntimeConfiguration
    private let parser: PacketParser
    private var flowTable: FlowTable

    public init(configuration: TunnelRuntimeConfiguration, parser: PacketParser = PacketParser()) {
        self.configuration = configuration
        self.parser = parser
        self.flowTable = FlowTable(capacity: configuration.flowLimit)
    }

    public mutating func process(_ packet: Packet) -> PacketProcessingResult {
        let parsed: ParsedPacket
        do {
            parsed = try parser.parse(packet)
        } catch PacketParseError.unsupportedTransportProtocol {
            return PacketProcessingResult(packet: packet, parsedPacket: nil, flowKey: nil, action: .drop(.unsupportedProtocol))
        } catch let error as PacketParseError {
            return PacketProcessingResult(packet: packet, parsedPacket: nil, flowKey: nil, action: .drop(.parseFailed(error)))
        } catch {
            return PacketProcessingResult(packet: packet, parsedPacket: nil, flowKey: nil, action: .drop(.noRoute))
        }

        let record = flowTable.record(parsed)
        let key = record.key
        return PacketProcessingResult(packet: packet, parsedPacket: parsed, flowKey: key, action: action(for: parsed, key: key))
    }

    public mutating func process(_ packets: [Packet]) -> [PacketProcessingResult] {
        packets.prefix(configuration.batchLimit).map { process($0) }
    }

    private func action(for packet: ParsedPacket, key: FlowKey) -> PacketAction {
        switch configuration.routeMode {
        case .globalProxy:
            return .proxy(key)
        case .direct:
            return .direct(key)
        case .ruleBased:
            let decision = configuration.routingEngine.resolve(RoutingContext(host: nil, ipAddress: packet.destinationIP.stringValue, port: packet.destinationPort))
            switch decision.action {
            case .direct:
                return .direct(key)
            case .proxy:
                return .proxy(key)
            case .reject:
                return .reject(key)
            }
        }
    }
}
```

- [ ] **Step 6: Run processor tests and full suite**

Run:

```bash
swift test --filter 'TunnelRuntimeConfigurationTests|PacketProcessorTests'
swift test
```

Expected: targeted tests pass and full suite passes.

- [ ] **Step 7: Commit**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketProcessor.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeConfigurationTests.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketProcessorTests.swift
git commit -m "feat: add tunnel packet processor"
```

---

### Task 5: Add packet runtime and in-memory packet I/O

**Files:**
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift`
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/InMemoryPacketIO.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift`

- [ ] **Step 1: Write runtime tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift`:

```swift
import XCTest
import IrockCore
import IrockRouting
@testable import IrockTunnelCore

final class PacketTunnelRuntimeTests: XCTestCase {
    func testRuntimeReadsProcessesAndWritesBatch() async throws {
        let reader = InMemoryPacketReader(packets: [
            .ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443),
            Packet(id: "bad", bytes: [0x45])
        ])
        let writer = InMemoryPacketWriter()
        let configuration = TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 8, flowLimit: 32)
        var runtime = PacketTunnelRuntime(reader: reader, writer: writer, processor: PacketProcessor(configuration: configuration))

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 2)
        XCTAssertEqual(summary.writtenCount, 2)
        XCTAssertEqual(summary.dropCount, 1)
        XCTAssertEqual(writer.writtenResults.map(\.action), [
            .proxy(FlowKey(sourceIP: .v4(10, 0, 0, 2), sourcePort: 51_234, destinationIP: .v4(93, 184, 216, 34), destinationPort: 443, transportProtocol: .tcp)),
            .drop(.parseFailed(.tooShort))
        ])
    }

    private func snapshot(routeMode: RouteMode) -> RuntimeSnapshot {
        RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled),
            routeMode: routeMode,
            logLevel: .user
        )
    }
}
```

- [ ] **Step 2: Run runtime tests to verify failure**

Run:

```bash
swift test --filter PacketTunnelRuntimeTests
```

Expected: FAIL because `PacketTunnelRuntime`, `PacketReader`, `PacketWriter`, `InMemoryPacketReader`, and `InMemoryPacketWriter` are missing.

- [ ] **Step 3: Implement runtime**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift`:

```swift
public protocol PacketReader: Sendable {
    func readBatch() async throws -> [Packet]
}

public protocol PacketWriter: Sendable {
    func write(_ results: [PacketProcessingResult]) async throws
}

public struct PacketTunnelRuntimeSummary: Equatable, Sendable {
    public let readCount: Int
    public let writtenCount: Int
    public let dropCount: Int

    public init(readCount: Int, writtenCount: Int, dropCount: Int) {
        self.readCount = readCount
        self.writtenCount = writtenCount
        self.dropCount = dropCount
    }
}

public struct PacketTunnelRuntime<Reader: PacketReader, Writer: PacketWriter>: Sendable {
    private let reader: Reader
    private let writer: Writer
    private var processor: PacketProcessor

    public init(reader: Reader, writer: Writer, processor: PacketProcessor) {
        self.reader = reader
        self.writer = writer
        self.processor = processor
    }

    public mutating func runOnce() async throws -> PacketTunnelRuntimeSummary {
        let packets = try await reader.readBatch()
        let results = processor.process(packets)
        try await writer.write(results)
        return PacketTunnelRuntimeSummary(
            readCount: packets.count,
            writtenCount: results.count,
            dropCount: results.filter { result in
                if case .drop = result.action { return true }
                return false
            }.count
        )
    }
}
```

- [ ] **Step 4: Implement in-memory packet I/O**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/InMemoryPacketIO.swift`:

```swift
public struct InMemoryPacketReader: PacketReader {
    private let packets: [Packet]

    public init(packets: [Packet]) {
        self.packets = packets
    }

    public func readBatch() async throws -> [Packet] {
        packets
    }
}

public final class InMemoryPacketWriter: PacketWriter, @unchecked Sendable {
    public private(set) var writtenResults: [PacketProcessingResult]

    public init(writtenResults: [PacketProcessingResult] = []) {
        self.writtenResults = writtenResults
    }

    public func write(_ results: [PacketProcessingResult]) async throws {
        writtenResults.append(contentsOf: results)
    }
}
```

- [ ] **Step 5: Run runtime tests and full suite**

Run:

```bash
swift test --filter PacketTunnelRuntimeTests
swift test
```

Expected: runtime tests pass and full suite passes.

- [ ] **Step 6: Commit**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift packages/IrockTunnelCore/Sources/IrockTunnelCore/InMemoryPacketIO.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift
git commit -m "feat: add packet tunnel runtime harness"
```

---

### Task 6: Update docs and final verification

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README current phase and plan links**

Replace `README.md` with:

```markdown
# irock

irock is a personal iOS/macOS network proxy client inspired by Shadowrocket's information architecture. The project uses Swift, SwiftUI, Network Extension, and shared Swift packages for protocol, routing, storage, diagnostics, and performance modules.

## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, and M2 TUN data path core:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing/storage behavior, app feature state, packet parsing, flow tracking, and tunnel runtime processing
- Xcode target creation instructions; Xcode workspace, app targets, and Packet Tunnel targets are not yet committed

## Design

See `docs/superpowers/specs/2026-05-09-irock-design.md`.

## Implementation plans

- M0: `docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md`
- M1: `docs/superpowers/plans/2026-05-10-irock-m1-ui-configuration.md`
- M2: `docs/superpowers/plans/2026-05-10-irock-m2-tun-data-path.md`

## Xcode targets

See `apps/XCODE_TARGETS.md` for the required iOS/macOS app and Packet Tunnel target layout.
```

- [ ] **Step 2: Update CLAUDE project status and commands**

In `CLAUDE.md`, update project status to say M2 tunnel core exists after implementation. Ensure commands include:

```markdown
- Run all SwiftPM tests: `swift test`
- Run a single test target: `swift test --filter IrockCoreTests`
- Run app feature tests: `swift test --filter IrockAppFeatureTests`
- Run tunnel core tests: `swift test --filter IrockTunnelCoreTests`
```

Keep the existing guidance that there is not yet an Xcode workspace, app target, or Packet Tunnel target.

- [ ] **Step 3: Run final verification**

Run:

```bash
swift test --filter IrockTunnelCoreTests
swift test
git status --short --ignored
git log --oneline --max-count=12
```

Expected:

- `IrockTunnelCoreTests` pass.
- Full suite passes.
- Only ignored scratch/build directories appear under ignored output.
- Recent commits include all M2 task commits.

- [ ] **Step 4: Commit docs**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document M2 tunnel core"
```

---

## Self-Review

Spec coverage:

- `IrockTunnelCore` product/target/test target: Task 1.
- Packet values and IPv4 TCP/UDP parsing: Task 2.
- DNS candidate classification: Task 2.
- Parse errors for short packet, unsupported version, unsupported protocol, and truncated header: Task 2.
- Flow key, flow record, packet count, capacity limit, oldest-flow eviction: Task 3.
- Runtime configuration consuming `RuntimeSnapshot.routeMode` and limits: Task 4.
- Global proxy, direct, rule-based reject, malformed packet drop, unsupported protocol drop: Task 4.
- `PacketReader` / `PacketWriter`, in-memory I/O, runtime summary: Task 5.
- README/CLAUDE updates and final verification: Task 6.
- Non-goals preserved: no task creates Xcode targets, imports NetworkExtension, calls packetFlow, implements DNS resolution, TCP reconstruction, UDP relay, protocol adapters, transport adapters, benchmarks, or third-party proxy cores.

Placeholder scan: no placeholder markers or unspecified implementation steps are required for M2 execution.

Type consistency:

- `RouteMode`, `RuntimeSnapshot`, `ProxyNode`, `CredentialReference`, and `TLSOptions` match `IrockCore`.
- `RoutingEngine`, `RoutingRule`, `RoutingContext`, and `RoutingAction` match `IrockRouting`.
- `PacketAction` cases use `FlowKey` consistently across processor and runtime tests.
- `PacketParseError.unsupportedTransportProtocol` maps to `.drop(.unsupportedProtocol)` in the processor, while other parse errors map to `.drop(.parseFailed(...))`.
