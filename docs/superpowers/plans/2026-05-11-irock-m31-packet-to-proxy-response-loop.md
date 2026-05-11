# M31 Packet to Proxy Response Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add the first safe packet response write-back loop by writing only explicitly produced response bytes back to Packet Tunnel flow writers.

**Architecture:** Introduce a narrow response payload seam instead of pretending metadata-only proxy connections are full streams. `PacketProcessingResult` carries optional response bytes, `ProxyConnection` exposes optional initial response bytes, and `PacketTunnelRuntime` enriches proxy results before the writer receives them. The iOS `NEPacketTunnelFlow` adapter writes only these explicit response bytes, preserving shared package platform neutrality.

**Tech Stack:** Swift 5.10, SwiftPM, XCTest, NetworkExtension in the iOS extension target only.

---

## Files

- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketProcessor.swift`
  - Add optional `responsePacketBytes` to `PacketProcessingResult`.
  - Add a small method for producing a copy with response bytes.
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Add `initialResponseBytes` to `ProxyConnection`.
  - Default existing `EstablishedProxyConnection` response bytes to `nil`.
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift`
  - Enrich proxy results with initial response bytes returned by proxy connections before writing.
- Modify: `apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift`
  - Write only explicit response payload bytes.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift`
  - Add runtime enrichment tests.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift`
  - Add writer delegation test for explicit response bytes.
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Update static test expectations for iOS flow adapter write-back behavior.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m31-packet-to-proxy-response-loop-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m31-packet-to-proxy-response-loop.md`

## Task 1: Explicit response payload contract

- [x] **Step 1: Write the failing test**

Add this test to `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift` inside `PacketFlowRuntimeIOTests`:

```swift
func testPacketProcessingResultCanCarryExplicitResponseBytes() async throws {
    let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
    var processor = PacketProcessor(configuration: try TunnelRuntimeConfiguration(snapshot: packetFlowSnapshot(tls: .disabled), batchLimit: 16, flowLimit: 32))
    let result = processor.process(packet).withResponsePacketBytes([0x45, 0x00, 0x00, 0x28])
    let flow = RecordingPacketFlowIO(packets: [])
    let io = PacketFlowRuntimeIO(flow: flow, batchLimit: 7)

    try await io.write([result])

    XCTAssertEqual(flow.writtenResults.first?.responsePacketBytes, [0x45, 0x00, 0x00, 0x28])
    XCTAssertEqual(flow.writtenResults.first?.packet.id, "tcp-1")
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter IrockTunnelCoreTests/testPacketProcessingResultCanCarryExplicitResponseBytes`

Expected: FAIL because `withResponsePacketBytes` and `responsePacketBytes` do not exist.

- [x] **Step 3: Implement minimal response payload contract**

In `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketProcessor.swift`, replace `PacketProcessingResult` with:

```swift
public struct PacketProcessingResult: Equatable, Sendable {
    public let packet: Packet
    public let parsedPacket: ParsedPacket?
    public let flowKey: FlowKey?
    public let action: PacketAction
    public let responsePacketBytes: [UInt8]?

    public init(packet: Packet, parsedPacket: ParsedPacket?, flowKey: FlowKey?, action: PacketAction, responsePacketBytes: [UInt8]? = nil) {
        self.packet = packet
        self.parsedPacket = parsedPacket
        self.flowKey = flowKey
        self.action = action
        self.responsePacketBytes = responsePacketBytes
    }

    public func withResponsePacketBytes(_ bytes: [UInt8]?) -> PacketProcessingResult {
        PacketProcessingResult(packet: packet, parsedPacket: parsedPacket, flowKey: flowKey, action: action, responsePacketBytes: bytes)
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter IrockTunnelCoreTests/testPacketProcessingResultCanCarryExplicitResponseBytes`

Expected: PASS.

## Task 2: Proxy connection response enrichment

- [x] **Step 1: Write the failing test**

Add this test to `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift` inside `PacketTunnelRuntimeTests`:

```swift
func testRuntimeWritesProxyInitialResponseBytesForMatchingFlow() async throws {
    let adapter = RuntimeRecordingProxyAdapter(protocolType: .trojan, initialResponseBytes: [0x45, 0x00, 0x00, 0x28])
    let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
    let reader = InMemoryPacketReader(packets: [packet])
    let writer = InMemoryPacketWriter()
    let runtime = PacketTunnelRuntime(
        reader: reader,
        writer: writer,
        configuration: TunnelRuntimeConfiguration(
            snapshot: snapshot(routeMode: .globalProxy),
            routingEngine: RoutingEngine(rules: [.final(.proxy)]),
            proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [adapter]),
            batchLimit: 16,
            flowLimit: 32
        )
    )

    let summary = try await runtime.runOnce()

    XCTAssertEqual(summary.readCount, 1)
    XCTAssertEqual(summary.writtenCount, 1)
    XCTAssertEqual(summary.proxyConnectCount, 1)
    XCTAssertEqual(writer.writtenResults.first?.responsePacketBytes, [0x45, 0x00, 0x00, 0x28])
}
```

Update the existing `RuntimeRecordingProxyAdapter` helper in the same file so its initializer accepts an optional response payload:

```swift
private final class RuntimeRecordingProxyAdapter: ProxyAdapter, @unchecked Sendable {
    let supportedProtocol: ProxyProtocolType
    private let initialResponseBytes: [UInt8]?
    private let lock = NSLock()
    private var storedConnectCount = 0

    var connectCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedConnectCount
    }

    init(protocolType: ProxyProtocolType, initialResponseBytes: [UInt8]? = nil) {
        self.supportedProtocol = protocolType
        self.initialResponseBytes = initialResponseBytes
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        recordConnect()
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination, initialResponseBytes: initialResponseBytes)
    }

    private func recordConnect() {
        lock.lock()
        defer { lock.unlock() }
        storedConnectCount += 1
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter IrockTunnelCoreTests/testRuntimeWritesProxyInitialResponseBytesForMatchingFlow`

Expected: FAIL because `ProxyConnection.initialResponseBytes` and runtime enrichment do not exist.

- [x] **Step 3: Add proxy connection response bytes**

In `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`, update the proxy connection protocol and established connection:

```swift
public protocol ProxyConnection: Sendable {
    var nodeID: NodeID { get }
    var destination: ProxyDestination { get }
    var initialResponseBytes: [UInt8]? { get }
}

public struct EstablishedProxyConnection: ProxyConnection, Equatable, Sendable {
    public let nodeID: NodeID
    public let destination: ProxyDestination
    public let initialResponseBytes: [UInt8]?

    public init(nodeID: NodeID, destination: ProxyDestination, initialResponseBytes: [UInt8]? = nil) {
        self.nodeID = nodeID
        self.destination = destination
        self.initialResponseBytes = initialResponseBytes
    }
}
```

- [x] **Step 4: Enrich proxy results before writing**

In `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift`, change `runOnce()` so it calls an enrichment method:

```swift
let proxyResponseBytesByFlow = try await connectProxyResults(results)
let writableResults = results.map { result in
    guard let flowKey = result.flowKey, let responseBytes = proxyResponseBytesByFlow[flowKey] else {
        return result
    }
    return result.withResponsePacketBytes(responseBytes)
}

try await writer.write(writableResults)
```

Then replace `connectProxyResults` with:

```swift
private func connectProxyResults(_ results: [PacketProcessingResult]) async throws -> [FlowKey: [UInt8]] {
    let outbound = ProxyOutbound(node: configuration.snapshot.selectedNode, registry: configuration.proxyAdapterRegistry)
    var connectedFlows: Set<FlowKey> = []
    var responseBytesByFlow: [FlowKey: [UInt8]] = [:]
    for result in results {
        guard let flowKey = result.flowKey, connectedFlows.insert(flowKey).inserted else {
            continue
        }
        if let connection = try await outbound.connect(result: result), let responseBytes = connection.initialResponseBytes, !responseBytes.isEmpty {
            responseBytesByFlow[flowKey] = responseBytes
        }
    }
    return responseBytesByFlow
}
```

Update the summary line to:

```swift
proxyConnectCount: proxyResponseBytesByFlow.count
```

- [x] **Step 5: Preserve proxy connect count semantics**

The previous step changes `proxyConnectCount` to count only responses. Instead, keep a tuple so existing tests continue counting connections:

```swift
let proxyConnectionSummary = try await connectProxyResults(results)
let writableResults = results.map { result in
    guard let flowKey = result.flowKey, let responseBytes = proxyConnectionSummary.responseBytesByFlow[flowKey] else {
        return result
    }
    return result.withResponsePacketBytes(responseBytes)
}

try await writer.write(writableResults)
```

Use this helper type and method in `PacketTunnelRuntime`:

```swift
private struct ProxyConnectionSummary {
    let connectCount: Int
    let responseBytesByFlow: [FlowKey: [UInt8]]
}

private func connectProxyResults(_ results: [PacketProcessingResult]) async throws -> ProxyConnectionSummary {
    let outbound = ProxyOutbound(node: configuration.snapshot.selectedNode, registry: configuration.proxyAdapterRegistry)
    var connectedFlows: Set<FlowKey> = []
    var connectCount = 0
    var responseBytesByFlow: [FlowKey: [UInt8]] = [:]
    for result in results {
        guard let flowKey = result.flowKey, connectedFlows.insert(flowKey).inserted else {
            continue
        }
        if let connection = try await outbound.connect(result: result) {
            connectCount += 1
            if let responseBytes = connection.initialResponseBytes, !responseBytes.isEmpty {
                responseBytesByFlow[flowKey] = responseBytes
            }
        }
    }
    return ProxyConnectionSummary(connectCount: connectCount, responseBytesByFlow: responseBytesByFlow)
}
```

Update the summary return to:

```swift
proxyConnectCount: proxyConnectionSummary.connectCount
```

- [x] **Step 6: Run tests to verify green**

Run: `swift test --filter IrockTunnelCoreTests/testRuntimeWritesProxyInitialResponseBytesForMatchingFlow`

Expected: PASS.

Run: `swift test --filter IrockTunnelCoreTests/PacketTunnelRuntimeTests`

Expected: PASS.

## Task 3: iOS Packet Tunnel flow writes only explicit responses

- [x] **Step 1: Write failing static tooling test**

In `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`, update `testPacketTunnelProviderWiresLoopRunner` or add a focused test:

```swift
func testNEPacketTunnelFlowAdapterWritesOnlyExplicitResponseBytes() throws {
    let flowAdapter = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift"))

    XCTAssertTrue(flowAdapter.contains("result.responsePacketBytes"))
    XCTAssertTrue(flowAdapter.contains("Data(responsePacketBytes)"))
    XCTAssertFalse(flowAdapter.contains("Data(result.packet.bytes)"))
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter IrockToolingTests/testNEPacketTunnelFlowAdapterWritesOnlyExplicitResponseBytes`

Expected: FAIL because the adapter still writes `Data(result.packet.bytes)`.

- [x] **Step 3: Update flow adapter write behavior**

In `apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift`, replace `writePackets(_:)` with:

```swift
func writePackets(_ results: [PacketProcessingResult]) async throws {
    let packets = results.compactMap { result -> NEPacket? in
        guard let responsePacketBytes = result.responsePacketBytes, !responsePacketBytes.isEmpty else {
            return nil
        }
        return NEPacket(data: Data(responsePacketBytes), protocolFamily: sa_family_t(AF_INET))
    }
    guard !packets.isEmpty else { return }
    await packetFlow.writePacketObjects(packets)
}
```

- [x] **Step 4: Run test to verify green**

Run: `swift test --filter IrockToolingTests/testNEPacketTunnelFlowAdapterWritesOnlyExplicitResponseBytes`

Expected: PASS.

## Task 4: Full verification

- [x] **Step 1: Run focused tunnel tests**

Run: `swift test --filter IrockTunnelCoreTests`

Expected: PASS.

- [x] **Step 2: Run tooling scaffold tests**

Run: `swift test --filter IrockToolingTests`

Expected: PASS.

- [x] **Step 3: Run full SwiftPM suite**

Run: `swift test`

Expected: PASS.

- [x] **Step 4: Run unsigned iOS simulator build**

Run: `xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

- [x] **Step 5: Run platform import boundary scan**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
forbidden = {'Network', 'NetworkExtension', 'UIKit', 'AppKit', 'Security'}
violations = []
for path in Path('packages').rglob('*.swift'):
    for line_no, line in enumerate(path.read_text().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith('import '):
            module = stripped.split()[1]
            if module in forbidden:
                violations.append(f'{path}:{line_no}: {stripped}')
if violations:
    print('\n'.join(violations))
    raise SystemExit(1)
print('No forbidden platform imports in packages')
PY
```

Expected: `No forbidden platform imports in packages`.

- [x] **Step 6: Update this plan with execution status**

Mark completed checkboxes in this file after each step passes.
