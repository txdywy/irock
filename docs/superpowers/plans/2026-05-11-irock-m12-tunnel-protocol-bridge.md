# irock M12 Tunnel Protocol Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect tunnel proxy routing decisions to the `IrockProtocols` adapter boundary without implementing real protocol forwarding.

**Architecture:** `IrockTunnelCore` gains a dependency on `IrockProtocols` and a focused `ProxyOutbound` bridge that converts proxied packet results into `ProxyRequest` values. `TunnelRuntimeConfiguration` carries an injectable `ProxyAdapterRegistry`, and `PacketTunnelRuntime` attempts proxy adapter connections after packet processing and before writing results, surfacing adapter failures through existing runtime status/log reporting.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, `IrockCore`, `IrockRouting`, `IrockProtocols`, `IrockStorage` test stores.

---

## File Structure

M12 modifies or creates these files:

```text
Package.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/ProxyOutbound.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/ProxyOutboundTests.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift
```

Responsibilities:

- `Package.swift`: add `IrockProtocols` as a dependency of `IrockTunnelCore` and `IrockTunnelCoreTests`.
- `ProxyOutbound.swift`: convert `.proxy` packet-processing results into protocol-layer `ProxyRequest` values and invoke the selected adapter.
- `TunnelRuntimeConfiguration.swift`: carry the adapter registry with an empty-registry default.
- `PacketTunnelRuntime.swift`: run outbound adapter attempts and publish deterministic failure feedback.
- `ProxyOutboundTests.swift`: unit-test request construction and action filtering.
- `PacketTunnelRuntimeTests.swift`: integration-test runtime invocation, summary counts, and failure reporting.

---

### Task 1: Add package dependency and ProxyOutbound bridge

**Files:**
- Modify: `Package.swift`
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/ProxyOutbound.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/ProxyOutboundTests.swift`

- [ ] **Step 1: Write failing ProxyOutbound tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/ProxyOutboundTests.swift` with:

```swift
import XCTest
import IrockCore
import IrockProtocols
import IrockRouting
@testable import IrockTunnelCore

final class ProxyOutboundTests: XCTestCase {
    func testConnectBuildsIPv4ProxyRequestFromProxyResult() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let outbound = ProxyOutbound(node: makeNode(protocolType: .trojan), registry: ProxyAdapterRegistry(adapters: [adapter]))
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let result = processor.process(packet)

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection?.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(adapter.requests.map(\.node.id), [NodeID(rawValue: "node-1")])
        XCTAssertEqual(adapter.requests.map(\.destination), [.ipv4("93.184.216.34", port: 443)])
        XCTAssertEqual(adapter.requests.first?.metadata["packetID"], "tcp-1")
        XCTAssertEqual(adapter.requests.first?.metadata["transportProtocol"], "tcp")
    }

    func testConnectBuildsIPv6ProxyRequestFromProxyResult() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let outbound = ProxyOutbound(node: makeNode(protocolType: .trojan), registry: ProxyAdapterRegistry(adapters: [adapter]))
        var processor = PacketProcessor(configuration: configuration(routeMode: .globalProxy))
        let packet = Packet.ipv6TCP(id: "tcp-6", source: .v6("2001:db8::1"), destination: .v6("2606:2800:220:1:248:1893:25c8:1946"), sourcePort: 51_234, destinationPort: 443)
        let result = processor.process(packet)

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.destination, .ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443))
        XCTAssertEqual(adapter.requests.map(\.destination), [.ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443)])
    }

    func testConnectReturnsNilForNonProxyResults() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let outbound = ProxyOutbound(node: makeNode(protocolType: .trojan), registry: ProxyAdapterRegistry(adapters: [adapter]))
        var processor = PacketProcessor(configuration: configuration(routeMode: .direct))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let result = processor.process(packet)

        let connection = try await outbound.connect(result: result)

        XCTAssertNil(connection)
        XCTAssertEqual(adapter.requests, [])
    }

    private func configuration(routeMode: RouteMode) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(snapshot: RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: makeNode(protocolType: .trojan), routeMode: routeMode, logLevel: .user), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32)
    }

    private func makeNode(protocolType: ProxyProtocolType) -> ProxyNode {
        ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: protocolType, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled)
    }
}

private final class RecordingProxyAdapter: ProxyAdapter, @unchecked Sendable {
    let supportedProtocol: ProxyProtocolType
    private let lock = NSLock()
    private var storedRequests: [ProxyRequest] = []

    var requests: [ProxyRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    init(protocolType: ProxyProtocolType) {
        self.supportedProtocol = protocolType
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }
}
```

- [ ] **Step 2: Run ProxyOutbound test to verify failure**

Run:

```bash
swift test --filter 'ProxyOutboundTests/testConnectBuildsIPv4ProxyRequestFromProxyResult'
```

Expected: FAIL with missing module dependency and/or missing `ProxyOutbound`.

- [ ] **Step 3: Add `IrockProtocols` dependency to tunnel target and tests**

In `Package.swift`, change the `IrockTunnelCore` target dependencies from:

```swift
.target(
    name: "IrockTunnelCore",
    dependencies: ["IrockCore", "IrockRouting", "IrockStorage"],
    path: "packages/IrockTunnelCore/Sources/IrockTunnelCore"
),
.testTarget(
    name: "IrockTunnelCoreTests",
    dependencies: ["IrockTunnelCore", "IrockStorage"],
    path: "packages/IrockTunnelCore/Tests/IrockTunnelCoreTests"
)
```

to:

```swift
.target(
    name: "IrockTunnelCore",
    dependencies: ["IrockCore", "IrockRouting", "IrockStorage", "IrockProtocols"],
    path: "packages/IrockTunnelCore/Sources/IrockTunnelCore"
),
.testTarget(
    name: "IrockTunnelCoreTests",
    dependencies: ["IrockTunnelCore", "IrockStorage", "IrockProtocols"],
    path: "packages/IrockTunnelCore/Tests/IrockTunnelCoreTests"
)
```

- [ ] **Step 4: Implement ProxyOutbound**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/ProxyOutbound.swift` with:

```swift
import IrockCore
import IrockProtocols

public struct ProxyOutbound: Sendable {
    private let node: ProxyNode
    private let registry: ProxyAdapterRegistry

    public init(node: ProxyNode, registry: ProxyAdapterRegistry) {
        self.node = node
        self.registry = registry
    }

    public func connect(result: PacketProcessingResult) async throws -> (any ProxyConnection)? {
        guard case .proxy = result.action, let parsedPacket = result.parsedPacket else {
            return nil
        }

        let request = ProxyRequest(
            node: node,
            destination: destination(for: parsedPacket),
            metadata: [
                "packetID": result.packet.id,
                "transportProtocol": parsedPacket.transportProtocol.rawValue
            ]
        )
        return try await registry.adapter(for: node.protocolType).connect(request: request)
    }

    private func destination(for packet: ParsedPacket) -> ProxyDestination {
        switch packet.destinationIP {
        case .v4:
            return .ipv4(packet.destinationIP.stringValue, port: packet.destinationPort)
        case .v6:
            return .ipv6(packet.destinationIP.stringValue, port: packet.destinationPort)
        }
    }
}
```

- [ ] **Step 5: Run ProxyOutbound tests**

Run:

```bash
swift test --filter ProxyOutboundTests
```

Expected: PASS.

- [ ] **Step 6: Commit ProxyOutbound bridge**

```bash
git add Package.swift packages/IrockTunnelCore/Sources/IrockTunnelCore/ProxyOutbound.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/ProxyOutboundTests.swift
git commit -m "feat: bridge tunnel proxy results to adapters"
```

---

### Task 2: Inject adapter registry through runtime configuration

**Files:**
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift`
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift`

- [ ] **Step 1: Write failing configuration test**

Add this test inside `PacketTunnelRuntimeTests` before `private func snapshot(routeMode:)`:

```swift
    func testConfigurationStoresProxyAdapterRegistry() async throws {
        let adapter = RuntimeRecordingProxyAdapter(protocolType: .trojan)
        let registry = ProxyAdapterRegistry(adapters: [adapter])
        let configuration = TunnelRuntimeConfiguration(
            snapshot: snapshot(routeMode: .globalProxy),
            routingEngine: RoutingEngine(rules: [.final(.proxy)]),
            proxyAdapterRegistry: registry,
            batchLimit: 16,
            flowLimit: 32
        )

        let selected = configuration.proxyAdapterRegistry.adapter(for: .trojan)
        let connection = try await selected.connect(request: ProxyRequest(node: snapshot(routeMode: .globalProxy).selectedNode, destination: .ipv4("93.184.216.34", port: 443)))

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
    }
```

Also add `import IrockProtocols` at the top of `PacketTunnelRuntimeTests.swift`.

Add this helper near the bottom of `PacketTunnelRuntimeTests.swift`:

```swift
private final class RuntimeRecordingProxyAdapter: ProxyAdapter, @unchecked Sendable {
    let supportedProtocol: ProxyProtocolType
    private let lock = NSLock()
    private var connectCountValue = 0

    var connectCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return connectCountValue
    }

    init(protocolType: ProxyProtocolType) {
        self.supportedProtocol = protocolType
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        lock.lock()
        connectCountValue += 1
        lock.unlock()
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }
}
```

- [ ] **Step 2: Run configuration test to verify failure**

Run:

```bash
swift test --filter 'PacketTunnelRuntimeTests/testConfigurationStoresProxyAdapterRegistry'
```

Expected: FAIL because `TunnelRuntimeConfiguration` has no `proxyAdapterRegistry` initializer parameter or property.

- [ ] **Step 3: Implement registry injection**

Replace `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift` with:

```swift
import IrockCore
import IrockProtocols
import IrockRouting

public struct TunnelRuntimeConfiguration: Sendable {
    public let snapshot: RuntimeSnapshot
    public let routingEngine: RoutingEngine
    public let proxyAdapterRegistry: ProxyAdapterRegistry
    public let batchLimit: Int
    public let flowLimit: Int

    public var routeMode: RouteMode {
        snapshot.routeMode
    }

    public var routingRuleManifest: RuntimeRoutingRuleManifest {
        snapshot.routingRuleManifest
    }

    public init(snapshot: RuntimeSnapshot, routingEngine: RoutingEngine, proxyAdapterRegistry: ProxyAdapterRegistry = ProxyAdapterRegistry(adapters: []), batchLimit: Int, flowLimit: Int) {
        self.snapshot = snapshot
        self.routingEngine = routingEngine
        self.proxyAdapterRegistry = proxyAdapterRegistry
        self.batchLimit = max(0, batchLimit)
        self.flowLimit = max(0, flowLimit)
    }

    public init(snapshot: RuntimeSnapshot, proxyAdapterRegistry: ProxyAdapterRegistry = ProxyAdapterRegistry(adapters: []), batchLimit: Int, flowLimit: Int) throws {
        let rules = try RuntimeRoutingRuleAdapter.routingRules(from: snapshot.routingRuleManifest)
        self.init(
            snapshot: snapshot,
            routingEngine: RoutingEngine(rules: rules),
            proxyAdapterRegistry: proxyAdapterRegistry,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
}
```

- [ ] **Step 4: Run tunnel core tests**

Run:

```bash
swift test --filter IrockTunnelCoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit registry injection**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift
git commit -m "feat: inject proxy adapter registry into tunnel runtime"
```

---

### Task 3: Invoke adapters from PacketTunnelRuntime

**Files:**
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift`
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift`

- [ ] **Step 1: Write failing runtime adapter invocation test**

Add this test inside `PacketTunnelRuntimeTests` before `private func snapshot(routeMode:)`:

```swift
    func testRuntimeConnectsProxyResultsBeforeWritingBatch() async throws {
        let adapter = RuntimeRecordingProxyAdapter(protocolType: .trojan)
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
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
        XCTAssertEqual(summary.dropCount, 0)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(adapter.connectCount, 1)
        XCTAssertEqual(writer.writtenResults.count, 1)
    }
```

- [ ] **Step 2: Run runtime adapter test to verify failure**

Run:

```bash
swift test --filter 'PacketTunnelRuntimeTests/testRuntimeConnectsProxyResultsBeforeWritingBatch'
```

Expected: FAIL because `PacketTunnelRuntimeSummary` has no `proxyConnectCount` and runtime does not call adapters.

- [ ] **Step 3: Implement adapter invocation and summary count**

Replace `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift` with:

```swift
import Foundation
import IrockCore
import IrockProtocols

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
    public let proxyConnectCount: Int

    public init(readCount: Int, writtenCount: Int, dropCount: Int, proxyConnectCount: Int = 0) {
        self.readCount = readCount
        self.writtenCount = writtenCount
        self.dropCount = dropCount
        self.proxyConnectCount = proxyConnectCount
    }
}

public struct PacketTunnelRuntime<Reader: PacketReader, Writer: PacketWriter>: Sendable {
    private let reader: Reader
    private let writer: Writer
    private let configuration: TunnelRuntimeConfiguration
    private let reporter: TunnelRuntimeReporter?

    public init(reader: Reader, writer: Writer, configuration: TunnelRuntimeConfiguration, reporter: TunnelRuntimeReporter? = nil) {
        self.reader = reader
        self.writer = writer
        self.configuration = configuration
        self.reporter = reporter
    }

    public func runOnce() async throws -> PacketTunnelRuntimeSummary {
        publish(.preparing, message: "Preparing packet batch")
        appendLog(message: "Tunnel runtime preparing", phase: .preparing)

        let packets: [Packet]
        let results: [PacketProcessingResult]
        let proxyConnectCount: Int
        do {
            packets = try await reader.readBatch()
            var processor = PacketProcessor(configuration: configuration)
            results = processor.process(packets)
            proxyConnectCount = try await connectProxyResults(results)

            try await writer.write(results)
        } catch {
            publish(.failed, message: failureMessage(for: error))
            appendLog(message: failureMessage(for: error), phase: .failed)
            throw error
        }

        publish(.connected, message: "Packet batch processed")
        appendLog(message: "Tunnel runtime connected", phase: .connected)

        return PacketTunnelRuntimeSummary(
            readCount: packets.count,
            writtenCount: results.count,
            dropCount: results.filter { result in
                if case .drop = result.action {
                    return true
                }
                return false
            }.count,
            proxyConnectCount: proxyConnectCount
        )
    }

    private func connectProxyResults(_ results: [PacketProcessingResult]) async throws -> Int {
        let outbound = ProxyOutbound(node: configuration.snapshot.selectedNode, registry: configuration.proxyAdapterRegistry)
        var connectCount = 0
        for result in results {
            if try await outbound.connect(result: result) != nil {
                connectCount += 1
            }
        }
        return connectCount
    }

    private func failureMessage(for error: Error) -> String {
        if let protocolError = error as? ProxyProtocolError {
            return "Proxy adapter failed: \(protocolError.description)"
        }
        return "Packet batch failed"
    }

    private func publish(_ phase: RuntimeConnectionPhase, message: String) {
        try? reporter?.publishStatus(RuntimeConnectionStatus(
            phase: phase,
            selectedNodeID: configuration.snapshot.selectedNode.id,
            selectedNodeName: configuration.snapshot.selectedNode.name,
            updatedAt: Date(),
            message: message
        ))
    }

    private func appendLog(message: String, phase: RuntimeConnectionPhase) {
        try? reporter?.appendLog(RuntimeLogEntry(
            id: "log-\(UUID().uuidString)",
            timestamp: Date(),
            level: .user,
            message: message,
            nodeID: configuration.snapshot.selectedNode.id,
            phase: phase
        ))
    }
}
```

- [ ] **Step 4: Run runtime adapter test**

Run:

```bash
swift test --filter 'PacketTunnelRuntimeTests/testRuntimeConnectsProxyResultsBeforeWritingBatch'
```

Expected: PASS.

- [ ] **Step 5: Run tunnel core tests**

Run:

```bash
swift test --filter IrockTunnelCoreTests
```

Expected: Existing tests that use default empty registries may now fail on global proxy traffic because unsupported adapters throw. Task 4 updates expectations.

- [ ] **Step 6: Commit runtime adapter invocation**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift
git commit -m "feat: invoke proxy adapters from tunnel runtime"
```

---

### Task 4: Surface unsupported adapter failures through runtime feedback

**Files:**
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift`

- [ ] **Step 1: Update existing proxy runtime tests to use a registered adapter**

In `PacketTunnelRuntimeTests.swift`, update successful global-proxy runtime construction in these tests to pass a registered `RuntimeRecordingProxyAdapter` through `proxyAdapterRegistry`:

- `testRuntimeReadsProcessesAndWritesBatch()`
- `testRuntimePublishesPreparingAndConnectedStatus()`
- `testRuntimeIgnoresReporterFailuresBeforePacketProcessing()`
- `testRuntimeIgnoresReporterFailuresAfterPacketWrite()`

For each runtime configuration, use:

```swift
TunnelRuntimeConfiguration(
    snapshot: snapshot(routeMode: .globalProxy),
    routingEngine: RoutingEngine(rules: [.final(.proxy)]),
    proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [RuntimeRecordingProxyAdapter(protocolType: .trojan)]),
    batchLimit: 16,
    flowLimit: 32
)
```

- [ ] **Step 2: Add unsupported failure test**

Add this test inside `PacketTunnelRuntimeTests` before `private func snapshot(routeMode:)`:

```swift
    func testRuntimePublishesFailedStatusAndLogWhenProxyAdapterIsUnsupported() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
        let writer = InMemoryPacketWriter()
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32),
            reporter: reporter
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
            XCTAssertEqual(status.selectedNodeName, "Demo")
            XCTAssertEqual(status.message, "Proxy adapter failed: Unsupported protocol: trojan")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Proxy adapter failed: Unsupported protocol: trojan"])
            XCTAssertEqual(writer.writtenResults, [])
        } catch {
            XCTFail("Expected proxy protocol error, got \(error)")
        }
    }
```

- [ ] **Step 3: Add explicit proxy adapter failure test**

Add this test inside `PacketTunnelRuntimeTests` before `private func snapshot(routeMode:)`:

```swift
    func testRuntimePublishesFailedStatusAndLogWhenProxyAdapterThrows() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
        let writer = InMemoryPacketWriter()
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(
                snapshot: snapshot(routeMode: .globalProxy),
                routingEngine: RoutingEngine(rules: [.final(.proxy)]),
                proxyAdapterRegistry: ProxyAdapterRegistry(adapters: [FailingProxyAdapter(protocolType: .trojan)]),
                batchLimit: 16,
                flowLimit: 32
            ),
            reporter: reporter
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected protocol failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tcpConnectFailed("secret connection refused"))
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Proxy adapter failed: TCP connect failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Proxy adapter failed: TCP connect failed"])
            XCTAssertEqual(writer.writtenResults, [])
        } catch {
            XCTFail("Expected proxy protocol error, got \(error)")
        }
    }
```

Add this helper near the bottom of the file:

```swift
private struct FailingProxyAdapter: ProxyAdapter {
    let supportedProtocol: ProxyProtocolType

    init(protocolType: ProxyProtocolType) {
        self.supportedProtocol = protocolType
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        throw ProxyProtocolError.tcpConnectFailed("secret connection refused")
    }
}
```

- [ ] **Step 4: Run tunnel runtime tests**

Run:

```bash
swift test --filter PacketTunnelRuntimeTests
```

Expected: PASS.

- [ ] **Step 5: Run all tunnel core tests**

Run:

```bash
swift test --filter IrockTunnelCoreTests
```

Expected: PASS.

- [ ] **Step 6: Commit failure feedback tests**

```bash
git add packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift
git commit -m "test: cover tunnel proxy adapter failures"
```

---

### Task 5: Final verification and dependency guard

**Files:**
- Verify only; no source edits expected unless verification exposes a bug.

- [ ] **Step 1: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS.

- [ ] **Step 2: Run tunnel core tests**

Run:

```bash
swift test --filter IrockTunnelCoreTests
```

Expected: PASS.

- [ ] **Step 3: Run full SwiftPM test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Verify no reverse dependency from protocols to tunnel**

Run:

```bash
grep -R "import IrockTunnelCore\|import IrockStorage\|import IrockAppFeature" -n packages/IrockProtocols Package.swift || true
```

Expected: no output from `packages/IrockProtocols` source or test files. `Package.swift` should not add `IrockTunnelCore`, `IrockStorage`, or `IrockAppFeature` to the `IrockProtocols` target.

- [ ] **Step 5: Inspect git status**

Run:

```bash
git status --short
```

Expected: only M12 docs if not committed yet, or clean after documentation commit.

- [ ] **Step 6: Commit M12 docs if still uncommitted**

```bash
git add docs/superpowers/specs/2026-05-11-irock-m12-tunnel-protocol-bridge-design.md docs/superpowers/plans/2026-05-11-irock-m12-tunnel-protocol-bridge.md
git commit -m "docs: add M12 tunnel protocol bridge plan"
```

---

## Self-Review

Spec coverage:

- `ProxyOutbound` request construction and adapter invocation: Task 1.
- Runtime configuration registry injection: Task 2.
- Runtime adapter connection attempt and summary count: Task 3.
- Unsupported and throwing adapter feedback through M10 status/log path: Task 4.
- Dependency direction and full verification: Task 5.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: all tasks use the M11 types `ProxyDestination`, `ProxyRequest`, `ProxyConnection`, `ProxyAdapter`, `ProxyAdapterRegistry`, and `ProxyProtocolError` consistently. Runtime summary uses `proxyConnectCount` throughout.
