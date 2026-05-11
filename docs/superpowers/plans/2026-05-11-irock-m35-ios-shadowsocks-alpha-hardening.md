# M35 iOS Shadowsocks Alpha Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Stabilize the first iOS Shadowsocks Alpha path by making startup, connected, stopped, and failed runtime states observable through deterministic status/log transitions.

**Architecture:** Keep platform-neutral diagnostics in `IrockTunnelCore` and keep iOS App Group/NetworkExtension seams in `apps/irock-iOS`. Add focused tests before implementation so each Alpha failure surface has a stable user-safe message without changing packet processing semantics.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, NetworkExtension scaffold, Xcode unsigned simulator build.

---

## Files

- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeReporter.swift`
  - Add convenience helpers for publishing stopped and runtime-store-unavailable diagnostics.
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeController.swift`
  - Report runtime snapshot store load failures as a deterministic failed status/log before rethrowing.
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift`
  - Preserve existing preparing/connected behavior and classify packet-loop vs proxy failures with stable messages.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeReporterTests.swift`
  - Add tests for stopped and runtime-store-unavailable reporting.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift`
  - Add tests for snapshot-store failure diagnostics.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift`
  - Strengthen status/log transition assertions for startup, connected, packet-loop failure, and connection failure.
- Modify: `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`
  - Add stop lifecycle status/log reporting through a small provider-local helper if App Group stores resolve.
- Create: `apps/irock-iOS/Signing/M35-ALPHA-SMOKE.md`
  - Document real-device Shadowsocks Alpha validation expectations and external blockers.
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Add static tests for provider stop reporting and M35 smoke documentation.

## Task 1: Reporter diagnostics helpers

- [x] **Step 1: Write failing reporter tests**

Add these tests to `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeReporterTests.swift`:

```swift
func testReporterPublishesStoppedStatusAndLog() throws {
    let statusStore = InMemoryRuntimeStatusStore()
    let logStore = InMemoryRuntimeLogStore()
    let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)

    try reporter.reportStopped()

    let status = try XCTUnwrap(statusStore.load())
    XCTAssertEqual(status.phase, .disconnected)
    XCTAssertNil(status.selectedNodeID)
    XCTAssertNil(status.selectedNodeName)
    XCTAssertEqual(status.message, "Tunnel stopped")
    let logs = try logStore.loadRecent()
    XCTAssertEqual(logs.map(\.message), ["Tunnel stopped"])
    XCTAssertEqual(logs.map(\.phase), [.disconnected])
}

func testReporterPublishesRuntimeStoreUnavailableStatusAndLog() throws {
    let statusStore = InMemoryRuntimeStatusStore()
    let logStore = InMemoryRuntimeLogStore()
    let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)

    try reporter.reportRuntimeStoreUnavailable()

    let status = try XCTUnwrap(statusStore.load())
    XCTAssertEqual(status.phase, .failed)
    XCTAssertNil(status.selectedNodeID)
    XCTAssertNil(status.selectedNodeName)
    XCTAssertEqual(status.message, "Runtime store unavailable")
    let logs = try logStore.loadRecent()
    XCTAssertEqual(logs.map(\.message), ["Runtime store unavailable"])
    XCTAssertEqual(logs.map(\.phase), [.failed])
}
```

- [x] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TunnelRuntimeReporterTests`

Expected: FAIL because `reportStopped()` and `reportRuntimeStoreUnavailable()` do not exist.

- [x] **Step 3: Implement reporter helpers**

Update `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeReporter.swift` to include:

```swift
public func reportStopped() throws {
    try publishStatus(RuntimeConnectionStatus(
        phase: .disconnected,
        selectedNodeID: nil,
        selectedNodeName: nil,
        updatedAt: Date(),
        message: "Tunnel stopped"
    ))
    try appendLog(RuntimeLogEntry(
        id: "log-\(UUID().uuidString)",
        timestamp: Date(),
        level: .user,
        message: "Tunnel stopped",
        nodeID: nil,
        phase: .disconnected
    ))
}

public func reportRuntimeStoreUnavailable() throws {
    try publishStatus(RuntimeConnectionStatus(
        phase: .failed,
        selectedNodeID: nil,
        selectedNodeName: nil,
        updatedAt: Date(),
        message: "Runtime store unavailable"
    ))
    try appendLog(RuntimeLogEntry(
        id: "log-\(UUID().uuidString)",
        timestamp: Date(),
        level: .user,
        message: "Runtime store unavailable",
        nodeID: nil,
        phase: .failed
    ))
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TunnelRuntimeReporterTests`

Expected: PASS.

## Task 2: Snapshot store failure diagnostics

- [x] **Step 1: Write failing controller test**

Add this test to `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeControllerTests.swift`:

```swift
func testRunShadowsocksTCPBatchReportsRuntimeStoreFailureWhenSnapshotLoadThrows() async throws {
    let statusStore = InMemoryRuntimeStatusStore()
    let logStore = InMemoryRuntimeLogStore()

    do {
        _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
            snapshotStore: ControllerFailingLoadRuntimeSnapshotStore(),
            flow: ControllerRecordingPacketFlowIO(packets: []),
            statusStore: statusStore,
            logStore: logStore,
            plain: ControllerRecordingTransportAdapter(transport: .tcp),
            tls: ControllerRecordingTransportAdapter(transport: .tcp),
            credentialResolver: TestShadowsocksCredentialResolver(),
            batchLimit: 16,
            flowLimit: 32
        )
        XCTFail("Expected runtime store failure")
    } catch ControllerRuntimeStoreError.failed {
        let status = try XCTUnwrap(statusStore.load())
        XCTAssertEqual(status.phase, .failed)
        XCTAssertNil(status.selectedNodeID)
        XCTAssertNil(status.selectedNodeName)
        XCTAssertEqual(status.message, "Runtime store unavailable")
        let logs = try logStore.loadRecent()
        XCTAssertEqual(logs.map(\.message), ["Runtime store unavailable"])
        XCTAssertEqual(logs.map(\.phase), [.failed])
    } catch {
        XCTFail("Expected runtime store failure, got \(error)")
    }
}
```

Add this helper near the other controller test stores:

```swift
private final class ControllerFailingLoadRuntimeSnapshotStore: RuntimeSnapshotStore, @unchecked Sendable {
    func save(_ snapshot: RuntimeSnapshot) throws {}

    func load() throws -> RuntimeSnapshot? {
        throw ControllerRuntimeStoreError.failed
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter TunnelRuntimeControllerTests/testRunShadowsocksTCPBatchReportsRuntimeStoreFailureWhenSnapshotLoadThrows`

Expected: FAIL because snapshot load errors are rethrown before a deterministic diagnostic is written.

- [x] **Step 3: Implement snapshot load failure reporting**

Update the beginning of `TunnelRuntimeController.runShadowsocksTCPBatch`:

```swift
let snapshot: RuntimeSnapshot

do {
    guard let loadedSnapshot = try snapshotStore.load() else {
        reportMissingSnapshot(statusStore: statusStore, logStore: logStore)
        throw TunnelRuntimeControllerError.missingRuntimeSnapshot
    }
    snapshot = loadedSnapshot
} catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
    throw TunnelRuntimeControllerError.missingRuntimeSnapshot
} catch {
    let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
    try? reporter.reportRuntimeStoreUnavailable()
    throw error
}
```

Use `snapshot` in the existing `TunnelRuntimeBootstrap.shadowsocksTCP(...)` call.

- [x] **Step 4: Run controller tests**

Run: `swift test --filter TunnelRuntimeControllerTests`

Expected: PASS.

## Task 3: Runtime transition regression coverage

- [x] **Step 1: Strengthen existing runtime tests**

Update `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift` assertions so these existing tests prove the M35 lifecycle contract:

- `testRuntimePublishesPreparingAndConnectedStatus` asserts final status message `Packet batch processed` and logs `Tunnel runtime preparing`, `Tunnel runtime connected`.
- `testRuntimePublishesFailedStatusAndLogWhenReaderThrows` asserts final status message `Packet batch failed`.
- `testRuntimePublishesFailedStatusAndLogWhenWriterThrows` asserts final status message `Packet batch failed`.
- `testRuntimePublishesFailedStatusAndLogWhenProxyAdapterThrows` asserts final status message `Proxy adapter failed: TCP connect failed` and does not expose `secret connection refused`.

- [x] **Step 2: Run runtime tests**

Run: `swift test --filter PacketTunnelRuntimeTests`

Expected: PASS.

## Task 4: iOS provider stop boundary and M35 smoke documentation

- [x] **Step 1: Write failing tooling tests**

Add these tests to `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`:

```swift
func testPacketTunnelProviderReportsStoppedLifecycle() throws {
    let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))

    XCTAssertTrue(provider.contains("reportStoppedLifecycle"))
    XCTAssertTrue(provider.contains("PacketTunnelAppGroupStoreResolver"))
    XCTAssertTrue(provider.contains("TunnelRuntimeReporter"))
    XCTAssertTrue(provider.contains("reportStopped()"))
}

func testM35AlphaSmokeRunbookDocumentsDiagnosticExpectations() throws {
    let runbook = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/Signing/M35-ALPHA-SMOKE.md"))

    XCTAssertTrue(runbook.contains("Runtime snapshot unavailable"))
    XCTAssertTrue(runbook.contains("Runtime store unavailable"))
    XCTAssertTrue(runbook.contains("Proxy adapter failed"))
    XCTAssertTrue(runbook.contains("Packet batch failed"))
    XCTAssertTrue(runbook.contains("Tunnel stopped"))
    XCTAssertTrue(runbook.contains("External blocker"))
    XCTAssertTrue(runbook.contains("Do not commit"))
}
```

Update `requiredScaffoldPaths` to include:

```swift
"apps/irock-iOS/Signing/M35-ALPHA-SMOKE.md",
```

- [x] **Step 2: Run tests to verify they fail**

Run: `swift test --filter XcodeScaffoldTests/testPacketTunnelProviderReportsStoppedLifecycle && swift test --filter XcodeScaffoldTests/testM35AlphaSmokeRunbookDocumentsDiagnosticExpectations`

Expected: FAIL because provider stop reporting and runbook do not exist yet.

- [x] **Step 3: Update PacketTunnelProvider**

Update `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`:

```swift
import IrockTunnelCore
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var startTunnelTask: Task<Void, Error>?

    override func startTunnel(options: [String: NSObject]?) async throws {
        try await PacketTunnelRuntimeSettingsApplicator().apply(to: self)
        let loopRunner = IOSPacketTunnelLoopRunner()
        try loopRunner.validateStartup()
        let task = Task {
            try await loopRunner.run(packetFlow: packetFlow)
        }
        startTunnelTask = task
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        startTunnelTask?.cancel()
        startTunnelTask = nil
        reportStoppedLifecycle()
    }

    private func reportStoppedLifecycle() {
        guard let stores = try? PacketTunnelAppGroupStoreResolver().makeRuntimeStoreBundle() else {
            return
        }
        let reporter = TunnelRuntimeReporter(statusStore: stores.statusStore, logStore: stores.logStore)
        try? reporter.reportStopped()
    }
}
```

- [x] **Step 4: Add M35 smoke runbook**

Create `apps/irock-iOS/Signing/M35-ALPHA-SMOKE.md`:

```markdown
# M35 iOS Shadowsocks Alpha Smoke Validation

## Purpose

Validate that a locally signed iOS build reports deterministic status and log transitions for the first Shadowsocks Alpha path.

## Required local inputs

- Apple Developer account with Network Extension and App Groups enabled.
- Physical iOS device provisioned for the container app and Packet Tunnel extension.
- Shared App Group configured identically for both targets.
- One reachable Shadowsocks TCP or TCP/TLS node with local-only credentials.

## Do not commit

Do not commit real Shadowsocks credentials, server addresses, Apple Team IDs, provisioning profiles, certificates, `.mobileprovision`, `.p12`, `.cer`, or local signing files.

## Expected diagnostics

- Missing runtime snapshot reports `Runtime snapshot unavailable`.
- App Group or runtime store failure reports `Runtime store unavailable` when the shared status/log store is reachable.
- Proxy connection failure reports a `Proxy adapter failed` message without leaking credential material.
- Packet read/write loop failure reports `Packet batch failed`.
- Manual stop reports `Tunnel stopped`.
- Successful startup reaches `Packet batch processed` and logs `Tunnel runtime connected`.

## External blocker

If local signing, App Group provisioning, a physical device, or a real Shadowsocks node is unavailable, real-device validation is blocked outside the repository. In that case, record the blocker and rely on SwiftPM tests plus unsigned simulator build evidence for automation.
```

- [x] **Step 5: Run tooling tests**

Run: `swift test --filter IrockToolingTests`

Expected: PASS.

## Task 5: Full verification and Ralph state update

- [x] **Step 1: Run IrockTunnelCore tests**

Run: `swift test --filter IrockTunnelCoreTests`

Expected: PASS.

- [x] **Step 2: Run full SwiftPM tests**

Run: `swift test`

Expected: PASS.

- [x] **Step 3: Run unsigned iOS simulator build**

Run: `xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

- [x] **Step 4: Scan for committed secrets/provisioning artifacts**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
forbidden_suffixes = {'.mobileprovision', '.p12', '.cer'}
forbidden = [p for p in Path('apps/irock-iOS').rglob('*') if p.suffix in forbidden_suffixes]
if forbidden:
    print('\n'.join(str(p) for p in forbidden))
    raise SystemExit(1)
print('No signing artifacts committed')
PY
```

Expected: `No signing artifacts committed`.

- [x] **Step 5: Update Ralph state**

Update `.omc/prd.json` so `US-M35.passes` is `true` only after all criteria pass. Append `.omc/progress.txt` with changed files, verification commands, and any external real-device blocker.

- [x] **Step 6: Commit and push M35**

Stage only M35 source, tests, docs, and Ralph state if intentionally tracked. Do not stage secrets, provisioning artifacts, `.omc/`, or `.superpowers/` scratch files unless the project explicitly requires them. Commit with a message like:

```text
Add iOS Shadowsocks Alpha diagnostics hardening

Constraint: Keep shared packages platform-neutral and leave device signing as local external input
Confidence: high
Scope-risk: moderate
Not-tested: Real-device Shadowsocks validation blocked without local signing credentials and device
```

Then push if authorized by the active Ralph instruction.

## Self-review

- Spec coverage: Tasks cover deterministic diagnostics, status/log transitions, provider stopped lifecycle, manual real-device blocker documentation, SwiftPM tests, Xcode unsigned build, and secret scans.
- Placeholder scan: No TBD/TODO/fill-in placeholders remain.
- Type consistency: Planned helper names match the files that will call them: `reportStopped()`, `reportRuntimeStoreUnavailable()`, and `reportStoppedLifecycle()`.
