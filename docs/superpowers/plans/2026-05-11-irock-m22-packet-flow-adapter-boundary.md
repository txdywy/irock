# M22 Packet Flow Adapter Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic packet-flow adapter boundary that lets future platform packet-flow code feed `PacketTunnelRuntime` without importing platform networking frameworks into shared Swift packages.

**Architecture:** M22 adds a small `PacketFlowIO` protocol and `PacketFlowRuntimeIO` adapter in `IrockTunnelCore`. The adapter conforms to the existing `PacketReader` and `PacketWriter` protocols, so `PacketTunnelRuntime` and `TunnelRuntimeBootstrap` do not need API changes.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, `IrockCore`, `IrockStorage`, `IrockTransport`, `IrockTunnelCore`.

---

## File Structure

M22 modifies these files:

```text
packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketFlowRuntimeIO.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift
docs/superpowers/plans/2026-05-11-irock-m22-packet-flow-adapter-boundary.md
```

Responsibilities:

- `PacketFlowRuntimeIO.swift`: defines the platform-neutral packet-flow contract and the runtime adapter that bridges it into `PacketReader` / `PacketWriter`.
- `PacketFlowRuntimeIOTests.swift`: proves delegation, full runtime bootstrap integration, and read/write failure reporting.
- This plan file: records implementation steps and verification commands.

---

### Task 1: Add packet-flow adapter contract

**Files:**
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketFlowRuntimeIO.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift`

- [ ] **Step 1: Write failing delegation tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift` with:

```swift
import XCTest
import IrockCore
import IrockProtocols
import IrockStorage
import IrockTransport
@testable import IrockTunnelCore

final class PacketFlowRuntimeIOTests: XCTestCase {
    func testReadBatchDelegatesToFlowWithConfiguredLimit() async throws {
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = RecordingPacketFlowIO(packets: [packet])
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: 7)

        let packets = try await io.readBatch()

        XCTAssertEqual(packets, [packet])
        XCTAssertEqual(flow.readLimits, [7])
    }

    func testWriteDelegatesResultsToFlow() async throws {
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let result = PacketProcessor(configuration: TunnelRuntimeConfiguration(snapshot: packetFlowSnapshot(tls: .disabled), batchLimit: 16, flowLimit: 32)).process(packet)
        let flow = RecordingPacketFlowIO(packets: [])
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: 7)

        try await io.write([result])

        XCTAssertEqual(flow.writtenResults, [result])
        XCTAssertEqual(flow.readLimits, [])
    }
}

private final class RecordingPacketFlowIO: PacketFlowIO, @unchecked Sendable {
    private let lock = NSLock()
    private let packets: [Packet]
    private var storedReadLimits: [Int] = []
    private var storedWrittenResults: [PacketProcessingResult] = []

    var readLimits: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return storedReadLimits
    }

    var writtenResults: [PacketProcessingResult] {
        lock.lock()
        defer { lock.unlock() }
        return storedWrittenResults
    }

    init(packets: [Packet]) {
        self.packets = packets
    }

    func readPackets(limit: Int) async throws -> [Packet] {
        lock.lock()
        defer { lock.unlock() }
        storedReadLimits.append(limit)
        return Array(packets.prefix(limit))
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        lock.lock()
        defer { lock.unlock() }
        storedWrittenResults.append(contentsOf: results)
    }
}

private func packetFlowSnapshot(tls: TLSOptions, routingRuleManifest: RuntimeRoutingRuleManifest = RuntimeRoutingRuleManifest(version: 1, rules: [RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)])) -> RuntimeSnapshot {
    RuntimeSnapshot(
        id: SnapshotID(rawValue: "snapshot-1"),
        selectedNode: ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo",
            protocolType: .shadowsocks,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: tls,
            udpPolicy: .disabled
        ),
        routeMode: .globalProxy,
        logLevel: .user,
        routingRuleManifest: routingRuleManifest
    )
}
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
swift test --filter 'PacketFlowRuntimeIOTests/testReadBatchDelegatesToFlowWithConfiguredLimit|PacketFlowRuntimeIOTests/testWriteDelegatesResultsToFlow'
```

Expected: FAIL to compile with errors like `cannot find type 'PacketFlowIO' in scope` and `cannot find 'PacketFlowRuntimeIO' in scope`.

- [ ] **Step 3: Implement minimal packet-flow adapter**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketFlowRuntimeIO.swift`:

```swift
public protocol PacketFlowIO: Sendable {
    func readPackets(limit: Int) async throws -> [Packet]
    func writePackets(_ results: [PacketProcessingResult]) async throws
}

public struct PacketFlowRuntimeIO<Flow: PacketFlowIO>: PacketReader, PacketWriter {
    private let flow: Flow
    private let batchLimit: Int

    public init(flow: Flow, batchLimit: Int) {
        self.flow = flow
        self.batchLimit = batchLimit
    }

    public func readBatch() async throws -> [Packet] {
        try await flow.readPackets(limit: batchLimit)
    }

    public func write(_ results: [PacketProcessingResult]) async throws {
        try await flow.writePackets(results)
    }
}
```

- [ ] **Step 4: Run delegation tests to verify GREEN**

Run:

```bash
swift test --filter PacketFlowRuntimeIOTests/testReadBatchDelegatesToFlowWithConfiguredLimit
swift test --filter PacketFlowRuntimeIOTests/testWriteDelegatesResultsToFlow
```

Expected: PASS.

- [ ] **Step 5: Commit packet-flow adapter contract**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketFlowRuntimeIO.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift
git commit -m "feat: add packet flow runtime io adapter"
```

---

### Task 2: Prove adapter works with tunnel runtime bootstrap

**Files:**
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift`

- [ ] **Step 1: Add bootstrapped runtime integration test**

Append this test inside `PacketFlowRuntimeIOTests` before its closing brace:

```swift
    func testBootstrappedRuntimeUsesPacketFlowIOForReadAndWrite() async throws {
        let plain = PacketFlowRecordingTransportAdapter(transport: .tcp)
        let tlsChild = PacketFlowRecordingTransportAdapter(transport: .tcp)
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = RecordingPacketFlowIO(packets: [packet])
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: 16)
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: packetFlowSnapshot(tls: .disabled),
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tlsChild,
            batchLimit: 16,
            flowLimit: 32
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.dropCount, 0)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(flow.readLimits, [16])
        XCTAssertEqual(flow.writtenResults.count, 1)
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(tlsChild.requests, [])
        let status = try XCTUnwrap(statusStore.load())
        XCTAssertEqual(status.phase, .connected)
        XCTAssertEqual(status.message, "Packet batch processed")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
    }
```

Append this helper after `RecordingPacketFlowIO`:

```swift
private final class PacketFlowRecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    private let lock = NSLock()
    private var storedRequests: [TransportRequest] = []

    var requests: [TransportRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    init(transport: TransportType) {
        self.supportedTransport = transport
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        record(request)
        return EstablishedTransportConnection(host: request.host, port: request.port, transport: request.transport)
    }

    private func record(_ request: TransportRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(request)
    }
}
```

- [ ] **Step 2: Run integration test**

Run:

```bash
swift test --filter PacketFlowRuntimeIOTests/testBootstrappedRuntimeUsesPacketFlowIOForReadAndWrite
```

Expected: PASS.

- [ ] **Step 3: Commit bootstrap integration coverage**

```bash
git add packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift
git commit -m "test: cover packet flow io bootstrap integration"
```

---

### Task 3: Cover packet-flow read and write failures

**Files:**
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift`

- [ ] **Step 1: Add read and write failure tests**

Append these tests inside `PacketFlowRuntimeIOTests` before its closing brace:

```swift
    func testBootstrappedRuntimePublishesFailureWhenPacketFlowReadFails() async throws {
        let io = PacketFlowRuntimeIO(flow: FailingReadPacketFlowIO(error: PacketFlowTestError.readFailed), batchLimit: 16)
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: packetFlowSnapshot(tls: .disabled),
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: PacketFlowRecordingTransportAdapter(transport: .tcp),
            tls: PacketFlowRecordingTransportAdapter(transport: .tcp),
            batchLimit: 16,
            flowLimit: 32
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected packet flow read failure")
        } catch PacketFlowTestError.readFailed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet flow read failure, got \(error)")
        }
    }

    func testBootstrappedRuntimePublishesFailureWhenPacketFlowWriteFails() async throws {
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = FailingWritePacketFlowIO(packets: [packet], error: PacketFlowTestError.writeFailed)
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: 16)
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: packetFlowSnapshot(tls: .disabled),
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: PacketFlowRecordingTransportAdapter(transport: .tcp),
            tls: PacketFlowRecordingTransportAdapter(transport: .tcp),
            batchLimit: 16,
            flowLimit: 32
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected packet flow write failure")
        } catch PacketFlowTestError.writeFailed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet flow write failure, got \(error)")
        }
    }
```

Append these helpers after `PacketFlowRecordingTransportAdapter`:

```swift
private enum PacketFlowTestError: Error {
    case readFailed
    case writeFailed
}

private struct FailingReadPacketFlowIO: PacketFlowIO {
    let error: PacketFlowTestError

    func readPackets(limit: Int) async throws -> [Packet] {
        throw error
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {}
}

private struct FailingWritePacketFlowIO: PacketFlowIO {
    let packets: [Packet]
    let error: PacketFlowTestError

    func readPackets(limit: Int) async throws -> [Packet] {
        Array(packets.prefix(limit))
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        throw error
    }
}
```

- [ ] **Step 2: Run failure tests**

Run:

```bash
swift test --filter PacketFlowRuntimeIOTests/testBootstrappedRuntimePublishesFailureWhenPacketFlowReadFails
swift test --filter PacketFlowRuntimeIOTests/testBootstrappedRuntimePublishesFailureWhenPacketFlowWriteFails
```

Expected: PASS.

- [ ] **Step 3: Commit failure coverage**

```bash
git add packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketFlowRuntimeIOTests.swift
git commit -m "test: cover packet flow io runtime failures"
```

---

### Task 4: Run full M22 verification and commit plan

**Files:**
- Modify: `docs/superpowers/plans/2026-05-11-irock-m22-packet-flow-adapter-boundary.md`

- [ ] **Step 1: Run focused packet-flow tests**

```bash
swift test --filter PacketFlowRuntimeIOTests
```

Expected: PASS.

- [ ] **Step 2: Run tunnel core tests**

```bash
swift test --filter IrockTunnelCoreTests
```

Expected: PASS.

- [ ] **Step 3: Run full SwiftPM suite**

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Verify no forbidden platform imports**

```bash
grep -R "import Network\|import Security\|import NetworkExtension" -n packages/IrockTunnelCore packages/IrockProtocols packages/IrockTransport Package.swift || true
```

Expected: no output.

- [ ] **Step 5: Run plan self-review scan**

```bash
python3 - <<'PY'
from pathlib import Path
path = Path('docs/superpowers/plans/2026-05-11-irock-m22-packet-flow-adapter-boundary.md')
patterns = ['T' + 'BD', 'TO' + 'DO', 'implement ' + 'later', 'fill in ' + 'details', 'Similar ' + 'to']
for line_number, line in enumerate(path.read_text().splitlines(), start=1):
    if any(pattern in line for pattern in patterns):
        print(f'{line_number}:{line}')
PY
```

Expected: no output.

- [ ] **Step 6: Commit plan**

```bash
git add docs/superpowers/plans/2026-05-11-irock-m22-packet-flow-adapter-boundary.md
git commit -m "docs: add M22 packet flow adapter boundary plan"
```

---

## Self-Review

Spec coverage:

- Packet-flow adapter contract: Task 1.
- Runtime adapter conforming to `PacketReader` and `PacketWriter`: Task 1.
- Batch-limit delegation: Task 1.
- Deterministic test doubles: Tasks 1-3.
- Bootstrapped runtime integration with `TunnelRuntimeBootstrap`: Task 2.
- Read and write failure reporting: Task 3.
- Forbidden platform import guard: Task 4.
- Full SwiftPM verification: Task 4.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: plan uses current `Packet`, `PacketProcessingResult`, `PacketReader`, `PacketWriter`, `PacketProcessor`, `TunnelRuntimeConfiguration`, `TunnelRuntimeBootstrap`, `InMemoryRuntimeStatusStore`, `InMemoryRuntimeLogStore`, `TransportAdapter`, `TransportRequest`, and `EstablishedTransportConnection` APIs.
