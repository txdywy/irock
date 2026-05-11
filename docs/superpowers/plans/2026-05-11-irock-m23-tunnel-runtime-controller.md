# M23 Tunnel Runtime Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic tunnel runtime controller that loads a runtime snapshot, adapts packet-flow I/O, bootstraps the Shadowsocks TCP runtime, and runs one packet batch.

**Architecture:** `TunnelRuntimeController` lives in `IrockTunnelCore` and composes existing M3 storage, M21 bootstrap, and M22 packet-flow adapter boundaries. It owns only snapshot-loading orchestration and missing-snapshot reporting; invalid manifests, packet-flow errors, proxy failures, and transport failures keep existing behavior.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, `IrockCore`, `IrockStorage`, `IrockTransport`, `IrockTunnelCore`.

---

## File Structure

M23 modifies these files:

```text
packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeController.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift
docs/superpowers/plans/2026-05-11-irock-m23-tunnel-runtime-controller.md
```

Responsibilities:

- `TunnelRuntimeController.swift`: contains the one-shot tunnel runtime controller and its missing-snapshot error.
- `TunnelRuntimeControllerTests.swift`: proves snapshot loading, packet-flow adaptation, bootstrap integration, missing-snapshot reporting, and failure propagation.
- This plan file: records implementation steps and verification commands.

---

### Task 1: Add controller success path

**Files:**
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeController.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift`

- [ ] **Step 1: Write failing controller success test**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift` with:

```swift
import XCTest
import IrockCore
import IrockStorage
import IrockTransport
@testable import IrockTunnelCore

final class TunnelRuntimeControllerTests: XCTestCase {
    func testRunShadowsocksTCPBatchLoadsSnapshotAndRunsPacketFlowBatch() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerSnapshot(tls: .disabled))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let flow = ControllerRecordingPacketFlowIO(packets: [packet])
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let plain = ControllerRecordingTransportAdapter(transport: .tcp)
        let tlsChild = ControllerRecordingTransportAdapter(transport: .tcp)

        let summary = try await TunnelRuntimeController.runShadowsocksTCPBatch(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tlsChild,
            batchLimit: 16,
            flowLimit: 32
        )

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
        XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(status.selectedNodeName, "Demo")
        XCTAssertEqual(status.message, "Packet batch processed")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
    }
}

private final class ControllerRecordingPacketFlowIO: PacketFlowIO, @unchecked Sendable {
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
        recordRead(limit: limit)
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        recordWrite(results)
    }

    private func recordRead(limit: Int) -> [Packet] {
        lock.lock()
        defer { lock.unlock() }
        storedReadLimits.append(limit)
        return Array(packets.prefix(limit))
    }

    private func recordWrite(_ results: [PacketProcessingResult]) {
        lock.lock()
        defer { lock.unlock() }
        storedWrittenResults.append(contentsOf: results)
    }
}

private final class ControllerRecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
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
    }

    private func record(_ request: TransportRequest) -> any TransportConnection {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(request)
        return EstablishedTransportConnection(host: request.host, port: request.port, transport: request.transport)
    }
}

private func controllerSnapshot(tls: TLSOptions, routingRuleManifest: RuntimeRoutingRuleManifest = RuntimeRoutingRuleManifest(version: 1, rules: [RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)])) -> RuntimeSnapshot {
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

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchLoadsSnapshotAndRunsPacketFlowBatch
```

Expected: FAIL to compile with `cannot find 'TunnelRuntimeController' in scope`.

- [ ] **Step 3: Implement minimal controller success path**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeController.swift`:

```swift
import IrockStorage
import IrockTransport

public enum TunnelRuntimeControllerError: Error, Equatable, Sendable {
    case missingRuntimeSnapshot
}

public struct TunnelRuntimeController: Sendable {
    public static func runShadowsocksTCPBatch<Flow: PacketFlowIO, Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary {
        guard let snapshot = try snapshotStore.load() else {
            throw TunnelRuntimeControllerError.missingRuntimeSnapshot
        }
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: batchLimit)
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: snapshot,
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tls,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        return try await runtime.runOnce()
    }
}
```

- [ ] **Step 4: Run success test to verify GREEN**

Run:

```bash
swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchLoadsSnapshotAndRunsPacketFlowBatch
```

Expected: PASS.

- [ ] **Step 5: Commit controller success path**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeController.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift
git commit -m "feat: add tunnel runtime controller batch runner"
```

---

### Task 2: Add missing snapshot reporting

**Files:**
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeController.swift`
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift`

- [ ] **Step 1: Add failing missing snapshot test**

Append this test inside `TunnelRuntimeControllerTests` before its closing brace:

```swift
    func testRunShadowsocksTCPBatchReportsMissingSnapshot() async throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()

        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: InMemoryRuntimeSnapshotStore(),
                flow: ControllerRecordingPacketFlowIO(packets: []),
                statusStore: statusStore,
                logStore: logStore,
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected missing runtime snapshot")
        } catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertNil(status.selectedNodeID)
            XCTAssertNil(status.selectedNodeName)
            XCTAssertEqual(status.message, "Runtime snapshot unavailable")
            let logs = try logStore.loadRecent()
            XCTAssertEqual(logs.map(\.message), ["Runtime snapshot unavailable"])
            XCTAssertEqual(logs.map(\.level), [.user])
            XCTAssertEqual(logs.map(\.nodeID), [nil])
            XCTAssertEqual(logs.map(\.phase), [.failed])
        } catch {
            XCTFail("Expected missing runtime snapshot, got \(error)")
        }
    }
```

- [ ] **Step 2: Run missing snapshot test to verify RED**

Run:

```bash
swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchReportsMissingSnapshot
```

Expected: FAIL because no status/log output is written for missing snapshots.

- [ ] **Step 3: Implement missing snapshot reporting**

Replace `TunnelRuntimeController.swift` with:

```swift
import Foundation
import IrockStorage
import IrockTransport

public enum TunnelRuntimeControllerError: Error, Equatable, Sendable {
    case missingRuntimeSnapshot
}

public struct TunnelRuntimeController: Sendable {
    public static func runShadowsocksTCPBatch<Flow: PacketFlowIO, Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary {
        guard let snapshot = try snapshotStore.load() else {
            reportMissingSnapshot(statusStore: statusStore, logStore: logStore)
            throw TunnelRuntimeControllerError.missingRuntimeSnapshot
        }
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: batchLimit)
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: snapshot,
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tls,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        return try await runtime.runOnce()
    }

    private static func reportMissingSnapshot(statusStore: RuntimeStatusStore, logStore: RuntimeLogStore) {
        let message = "Runtime snapshot unavailable"
        try? statusStore.save(RuntimeConnectionStatus(
            phase: .failed,
            selectedNodeID: nil,
            selectedNodeName: nil,
            updatedAt: Date(),
            message: message
        ))
        try? logStore.append(RuntimeLogEntry(
            id: "log-\(UUID().uuidString)",
            timestamp: Date(),
            level: .user,
            message: message,
            nodeID: nil,
            phase: .failed
        ))
    }
}
```

- [ ] **Step 4: Run missing snapshot and success tests**

Run:

```bash
swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchReportsMissingSnapshot
swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchLoadsSnapshotAndRunsPacketFlowBatch
```

Expected: PASS.

- [ ] **Step 5: Commit missing snapshot reporting**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeController.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift
git commit -m "feat: report missing tunnel runtime snapshot"
```

---

### Task 3: Cover controller failure propagation

**Files:**
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift`

- [ ] **Step 1: Add failure propagation tests**

Append these tests inside `TunnelRuntimeControllerTests` before its closing brace:

```swift
    func testRunShadowsocksTCPBatchIgnoresReporterFailuresWhenSnapshotIsMissing() async throws {
        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: InMemoryRuntimeSnapshotStore(),
                flow: ControllerRecordingPacketFlowIO(packets: []),
                statusStore: ControllerFailingRuntimeStatusStore(),
                logStore: ControllerFailingRuntimeLogStore(),
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected missing runtime snapshot")
        } catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
        } catch {
            XCTFail("Expected missing runtime snapshot, got \(error)")
        }
    }

    func testRunShadowsocksTCPBatchPropagatesInvalidRoutingManifest() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: nil, action: .direct)]
        )
        try snapshotStore.save(controllerSnapshot(tls: .disabled, routingRuleManifest: manifest))
        let flow = ControllerRecordingPacketFlowIO(packets: [])

        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: snapshotStore,
                flow: flow,
                statusStore: InMemoryRuntimeStatusStore(),
                logStore: InMemoryRuntimeLogStore(),
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected invalid routing manifest")
        } catch let error as RuntimeRoutingRuleAdapterError {
            XCTAssertEqual(error, .missingValue(kind: .domainSuffix))
            XCTAssertEqual(flow.readLimits, [])
            XCTAssertEqual(flow.writtenResults, [])
        } catch {
            XCTFail("Expected invalid routing manifest, got \(error)")
        }
    }

    func testRunShadowsocksTCPBatchPropagatesPacketFlowReadFailure() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerSnapshot(tls: .disabled))
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()

        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: snapshotStore,
                flow: ControllerFailingReadPacketFlowIO(error: ControllerPacketFlowTestError.readFailed),
                statusStore: statusStore,
                logStore: logStore,
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected packet flow read failure")
        } catch ControllerPacketFlowTestError.readFailed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet flow read failure, got \(error)")
        }
    }

    func testRunShadowsocksTCPBatchPropagatesPacketFlowWriteFailure() async throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        try snapshotStore.save(controllerSnapshot(tls: .disabled))
        let packet = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()

        do {
            _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                snapshotStore: snapshotStore,
                flow: ControllerFailingWritePacketFlowIO(packets: [packet], error: ControllerPacketFlowTestError.writeFailed),
                statusStore: statusStore,
                logStore: logStore,
                plain: ControllerRecordingTransportAdapter(transport: .tcp),
                tls: ControllerRecordingTransportAdapter(transport: .tcp),
                batchLimit: 16,
                flowLimit: 32
            )
            XCTFail("Expected packet flow write failure")
        } catch ControllerPacketFlowTestError.writeFailed {
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Packet batch failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Packet batch failed"])
        } catch {
            XCTFail("Expected packet flow write failure, got \(error)")
        }
    }
```

Append these helpers after `ControllerRecordingTransportAdapter`:

```swift
private enum ControllerPacketFlowTestError: Error {
    case readFailed
    case writeFailed
}

private enum ControllerRuntimeStoreError: Error {
    case failed
}

private struct ControllerFailingReadPacketFlowIO: PacketFlowIO {
    let error: ControllerPacketFlowTestError

    func readPackets(limit: Int) async throws -> [Packet] {
        throw error
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {}
}

private struct ControllerFailingWritePacketFlowIO: PacketFlowIO {
    let packets: [Packet]
    let error: ControllerPacketFlowTestError

    func readPackets(limit: Int) async throws -> [Packet] {
        Array(packets.prefix(limit))
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        throw error
    }
}

private final class ControllerFailingRuntimeStatusStore: RuntimeStatusStore, @unchecked Sendable {
    func save(_ status: RuntimeConnectionStatus) throws {
        throw ControllerRuntimeStoreError.failed
    }

    func load() throws -> RuntimeConnectionStatus? {
        nil
    }
}

private final class ControllerFailingRuntimeLogStore: RuntimeLogStore, @unchecked Sendable {
    func append(_ entry: RuntimeLogEntry) throws {
        throw ControllerRuntimeStoreError.failed
    }

    func loadRecent() throws -> [RuntimeLogEntry] {
        []
    }

    func clear() throws {}
}
```

- [ ] **Step 2: Run failure propagation tests**

Run:

```bash
swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchIgnoresReporterFailuresWhenSnapshotIsMissing
swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchPropagatesInvalidRoutingManifest
swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchPropagatesPacketFlowReadFailure
swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchPropagatesPacketFlowWriteFailure
```

Expected: PASS.

- [ ] **Step 3: Commit failure propagation coverage**

```bash
git add packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift
git commit -m "test: cover tunnel runtime controller failures"
```

---

### Task 4: Run full M23 verification and commit plan

**Files:**
- Modify: `docs/superpowers/plans/2026-05-11-irock-m23-tunnel-runtime-controller.md`

- [ ] **Step 1: Run focused controller tests**

```bash
swift test --filter TunnelRuntimeControllerTests
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
path = Path('docs/superpowers/plans/2026-05-11-irock-m23-tunnel-runtime-controller.md')
patterns = ['T' + 'BD', 'TO' + 'DO', 'implement ' + 'later', 'fill in ' + 'details', 'Similar ' + 'to']
for line_number, line in enumerate(path.read_text().splitlines(), start=1):
    if any(pattern in line for pattern in patterns):
        print(f'{line_number}:{line}')
PY
```

Expected: no output.

- [ ] **Step 6: Commit plan**

```bash
git add docs/superpowers/plans/2026-05-11-irock-m23-tunnel-runtime-controller.md
git commit -m "docs: add M23 tunnel runtime controller plan"
```

---

## Self-Review

Spec coverage:

- Controller loads `RuntimeSnapshotStore`: Task 1.
- Controller adapts `PacketFlowIO` through `PacketFlowRuntimeIO`: Task 1.
- Controller uses `TunnelRuntimeBootstrap.shadowsocksTCP(...)`: Task 1.
- One-batch summary return: Task 1.
- Missing snapshot error and safe status/log output: Task 2.
- Missing snapshot ignores reporting failures: Task 3.
- Invalid manifest propagation before packet I/O: Task 3.
- Packet-flow read/write failure propagation and existing runtime reporting: Task 3.
- Forbidden platform import guard and full SwiftPM verification: Task 4.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: plan uses current `RuntimeSnapshotStore`, `RuntimeStatusStore`, `RuntimeLogStore`, `RuntimeConnectionStatus`, `RuntimeLogEntry`, `PacketFlowIO`, `PacketFlowRuntimeIO`, `TunnelRuntimeBootstrap`, `PacketTunnelRuntimeSummary`, `TransportAdapter`, `TransportRequest`, and `EstablishedTransportConnection` APIs.
