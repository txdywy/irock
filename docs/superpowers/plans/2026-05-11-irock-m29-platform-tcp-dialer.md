# M29 Platform TCP Dialer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add an iOS Packet Tunnel extension-local TCP dialer behind the existing `TCPDialer` seam.

**Architecture:** Keep `IrockTransport` platform-neutral and implement the real socket dialer in `apps/irock-iOS/irockTunnelExtension`. The tunnel smoke/runtime path will use `TCPTransportAdapter(dialer: IOSPlatformTCPDialer())` for plain TCP while keeping TLS unsupported until a later milestone.

**Tech Stack:** Swift, Network framework `NWConnection`, Swift Concurrency, SwiftPM XCTest static scaffold tests, Xcode project source membership.

---

## Execution Status

Implemented in this worktree and verified with:

- `swift test --filter XcodeScaffoldTests`
- `swift test`
- `xcodebuild -list -project apps/irock-iOS/irock.xcodeproj`
- `xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- Shared package platform import scan
- M29 plan/spec placeholder scan

Independent review found timeout/cancellation and queue-churn concerns; the final implementation uses a waiter-owned completion gate, direct timeout/cancellation resume, a static dialer queue, defensive host validation, and non-terminal `.waiting` behavior.

---

## File Structure

- Create `apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift`
  - Extension-local `TCPDialer` implementation using `NWConnection`.
  - Owns connection readiness wait, cancellation, timeout, and transport error mapping.
- Modify `apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift`
  - Replaces the plain `UnsupportedTransportAdapter(transport: .tcp)` with `TCPTransportAdapter(dialer: IOSPlatformTCPDialer())`.
  - Leaves TLS as `UnsupportedTransportAdapter(transport: .tcp)`.
- Modify `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
  - Adds `IOSPlatformTCPDialer.swift` to the tunnel extension group and sources build phase.
- Modify `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Adds static checks for file existence, Xcode source membership, platform import containment, dialer behavior markers, and smoke runner wiring.
- Create `docs/superpowers/specs/2026-05-11-irock-m29-platform-tcp-dialer-design.md`
  - Captures the milestone design and acceptance criteria.

---

### Task 1: Add failing scaffold tests for the platform TCP dialer

**Files:**
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
- Test: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [x] **Step 1: Add the new required scaffold path**

In `requiredScaffoldPaths`, add this entry immediately after `IOSPacketTunnelLoopRunner.swift`:

```swift
"apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift",
```

The resulting tunnel extension section should be:

```swift
"apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift",
"apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift",
"apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift",
"apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift",
"apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift",
"apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift",
"apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift",
"apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift",
"apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift",
```

- [x] **Step 2: Add Xcode source membership assertion**

In `testXcodeProjectDeclaresIOSAppAndTunnelTargetShape()`, add this assertion immediately after the existing `IOSPacketTunnelLoopRunner.swift in Sources` assertion:

```swift
XCTAssertTrue(project.contains("IOSPlatformTCPDialer.swift in Sources"))
```

The relevant assertion block should be:

```swift
XCTAssertTrue(project.contains("PacketTunnelAppGroupStoreResolver.swift in Sources"))
XCTAssertTrue(project.contains("IOSPacketTunnelSmokeRunner.swift in Sources"))
XCTAssertTrue(project.contains("IOSPacketTunnelLoopRunner.swift in Sources"))
XCTAssertTrue(project.contains("IOSPlatformTCPDialer.swift in Sources"))
XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsConfiguration.swift in Sources"))
XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsFactory.swift in Sources"))
XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsApplicator.swift in Sources"))
```

- [x] **Step 3: Add platform TCP dialer boundary test**

Add this test method immediately after `testPacketTunnelLoopRunnerDeclaresCancellableLongRunningBoundary()`:

```swift
func testPlatformTCPDialerDeclaresNetworkConnectionBoundary() throws {
    let dialer = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift"))

    XCTAssertTrue(dialer.contains("import " + "IrockTransport"))
    XCTAssertTrue(dialer.contains("import " + "Network"))
    XCTAssertTrue(dialer.contains("struct IOSPlatformTCPDialer: TCPDialer"))
    XCTAssertTrue(dialer.contains("NWConnection"))
    XCTAssertTrue(dialer.contains("NWEndpoint.Host"))
    XCTAssertTrue(dialer.contains("NWEndpoint.Port"))
    XCTAssertTrue(dialer.contains("connection.start"))
    XCTAssertTrue(dialer.contains("withTaskCancellationHandler"))
    XCTAssertTrue(dialer.contains("private static let queue"))
    XCTAssertTrue(dialer.contains("waiter.cancel()"))
    XCTAssertTrue(dialer.contains("let timeoutTask = Task"))
    XCTAssertTrue(dialer.contains("resume(with: .failure(TransportError.tcpConnectFailed(\"tcp dial timed out\")))"))
    XCTAssertTrue(dialer.contains("missing tcp host"))
    XCTAssertTrue(dialer.contains("Task.sleep"))
    XCTAssertFalse(dialer.contains("withThrowingTaskGroup"))
    XCTAssertTrue(dialer.contains("case .ready"))
    XCTAssertTrue(dialer.contains("case .failed"))
    XCTAssertTrue(dialer.contains("case .waiting"))
    XCTAssertTrue(dialer.contains("case .waiting:\n            break"))
    XCTAssertTrue(dialer.contains("TCPDialResult"))
    XCTAssertTrue(dialer.contains("TransportError.tcpConnectFailed"))
}
```

- [x] **Step 4: Add smoke runner wiring assertion**

In `testPacketTunnelSmokePathFilesDeclareExpectedBoundaries()`, replace this assertion:

```swift
XCTAssertTrue(smokeRunner.contains("UnsupportedTransportAdapter"))
```

with these assertions:

```swift
XCTAssertTrue(smokeRunner.contains("TCPTransportAdapter(dialer: IOSPlatformTCPDialer())"))
XCTAssertTrue(smokeRunner.contains("tls: UnsupportedTransportAdapter(transport: .tcp)"))
```

- [x] **Step 5: Expand platform import containment test**

In `testNetworkExtensionImportsStayInsideTunnelExtension()`, replace the method with:

```swift
func testPlatformImportsStayInsideTunnelExtension() throws {
    let forbiddenRoots = [
        repositoryRoot.appendingPathComponent("packages"),
        repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp")
    ]
    let forbiddenImports = [
        "import " + "NetworkExtension",
        "import " + "Network",
        "import " + "Security",
        "import " + "UIKit",
        "import " + "AppKit"
    ]

    for root in forbiddenRoots {
        for file in try swiftFiles(under: root) {
            let contents = try String(contentsOf: file)
            for forbiddenImport in forbiddenImports {
                XCTAssertFalse(contents.contains(forbiddenImport), "\(forbiddenImport) leaked into \(file.path)")
            }
        }
    }
}
```

- [x] **Step 6: Run focused scaffold existence test and verify it fails**

Run:

```bash
swift test --filter XcodeScaffoldTests/testRequiredIOSScaffoldFilesExist
```

Expected: FAIL with a message containing:

```text
Missing apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift
```

- [x] **Step 7: Commit the failing tests**

```bash
git add packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift
git commit -m "$(cat <<'EOF'
test: require platform TCP dialer
EOF
)"
```

---

### Task 2: Implement the extension-local TCP dialer

**Files:**
- Create: `apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift`
- Test: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [x] **Step 1: Create `IOSPlatformTCPDialer.swift`**

Create `apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift` with exactly this content:

```swift
import Foundation
import IrockTransport
import Network

struct IOSPlatformTCPDialer: TCPDialer {
    private static let queue = DispatchQueue(label: "dev.irock.tcp-dialer")
    private let timeoutNanoseconds: UInt64

    init(timeoutNanoseconds: UInt64 = 5_000_000_000) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func open(host: String, port: Int) async throws -> TCPDialResult {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            throw TransportError.invalidConfiguration("missing tcp host")
        }
        guard (1...65_535).contains(port), let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw TransportError.invalidConfiguration("invalid tcp port")
        }

        let connection = NWConnection(host: NWEndpoint.Host(normalizedHost), port: endpointPort, using: .tcp)
        let waiter = IOSPlatformTCPDialWaiter(
            connection: connection,
            host: normalizedHost,
            port: port,
            timeoutNanoseconds: timeoutNanoseconds
        )

        return try await withTaskCancellationHandler {
            try await waiter.open(on: Self.queue)
        } onCancel: {
            waiter.cancel()
        }
    }
}

private final class IOSPlatformTCPDialWaiter: @unchecked Sendable {
    private let connection: NWConnection
    private let host: String
    private let port: Int
    private let timeoutNanoseconds: UInt64
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TCPDialResult, Error>?
    private var terminalResult: Result<TCPDialResult, Error>?

    init(connection: NWConnection, host: String, port: Int, timeoutNanoseconds: UInt64) {
        self.connection = connection
        self.host = host
        self.port = port
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func open(on queue: DispatchQueue) async throws -> TCPDialResult {
        let timeoutTask = Task { [weak self] in
            guard let self else { return }
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            resume(with: .failure(TransportError.tcpConnectFailed("tcp dial timed out")))
        }

        defer {
            timeoutTask.cancel()
            connection.cancel()
        }

        return try await withCheckedThrowingContinuation { continuation in
            guard install(continuation) else { return }
            connection.stateUpdateHandler = { [weak self] state in
                self?.handle(state)
            }
            connection.start(queue: queue)
        }
    }

    func cancel() {
        resume(with: .failure(CancellationError()))
        connection.cancel()
    }

    private func install(_ continuation: CheckedContinuation<TCPDialResult, Error>) -> Bool {
        lock.lock()
        if let terminalResult {
            lock.unlock()
            complete(continuation, with: terminalResult)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            resume(with: .success(TCPDialResult(host: host, port: port)))
        case .failed(let error):
            resume(with: .failure(TransportError.tcpConnectFailed(error.localizedDescription)))
        case .waiting:
            break
        case .cancelled:
            resume(with: .failure(CancellationError()))
        case .setup, .preparing:
            break
        @unknown default:
            resume(with: .failure(TransportError.tcpConnectFailed("unknown tcp connection state")))
        }
    }

    private func resume(with result: Result<TCPDialResult, Error>) {
        lock.lock()
        guard terminalResult == nil else {
            lock.unlock()
            return
        }
        terminalResult = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        if let continuation {
            complete(continuation, with: result)
        }
    }

    private func complete(_ continuation: CheckedContinuation<TCPDialResult, Error>, with result: Result<TCPDialResult, Error>) {
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
```

- [x] **Step 2: Run platform dialer boundary test and verify Xcode membership still fails**

Run:

```bash
swift test --filter XcodeScaffoldTests/testPlatformTCPDialerDeclaresNetworkConnectionBoundary
swift test --filter XcodeScaffoldTests/testXcodeProjectDeclaresIOSAppAndTunnelTargetShape
```

Expected: first test PASS. Second test FAIL because `IOSPlatformTCPDialer.swift in Sources` is not in `project.pbxproj` yet.

- [x] **Step 3: Commit the dialer file**

```bash
git add apps/irock-iOS/irockTunnelExtension/IOSPlatformTCPDialer.swift
git commit -m "$(cat <<'EOF'
feat: add iOS platform TCP dialer
EOF
)"
```

---

### Task 3: Wire the smoke runner to the platform TCP dialer

**Files:**
- Modify: `apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift`
- Test: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [x] **Step 1: Replace the plain unsupported transport adapter**

In `IOSPacketTunnelSmokeRunner.runOnce(packetFlow:)`, replace this argument:

```swift
plain: UnsupportedTransportAdapter(transport: .tcp),
```

with:

```swift
plain: TCPTransportAdapter(dialer: IOSPlatformTCPDialer()),
```

The full `runOnce(packetFlow:)` method should be:

```swift
func runOnce(packetFlow: NEPacketTunnelFlow) async throws -> PacketTunnelRuntimeSummary {
    let stores = try storeResolver.makeRuntimeStoreBundle()
    return try await TunnelRuntimeController.runShadowsocksTCPBatch(
        snapshotStore: stores.snapshotStore,
        flow: NEPacketTunnelFlowPacketFlowIO(packetFlow: packetFlow),
        statusStore: stores.statusStore,
        logStore: stores.logStore,
        plain: TCPTransportAdapter(dialer: IOSPlatformTCPDialer()),
        tls: UnsupportedTransportAdapter(transport: .tcp),
        batchLimit: batchLimit,
        flowLimit: flowLimit
    )
}
```

- [x] **Step 2: Run smoke runner boundary test**

Run:

```bash
swift test --filter XcodeScaffoldTests/testPacketTunnelSmokePathFilesDeclareExpectedBoundaries
```

Expected: PASS.

- [x] **Step 3: Commit smoke runner wiring**

```bash
git add apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift
git commit -m "$(cat <<'EOF'
feat: use platform TCP dialer in tunnel smoke path
EOF
)"
```

---

### Task 4: Add the platform TCP dialer to the Xcode project

**Files:**
- Modify: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
- Test: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [x] **Step 1: Add PBXBuildFile entry**

In the `PBXBuildFile` section of `apps/irock-iOS/irock.xcodeproj/project.pbxproj`, add this entry immediately after `IOSPacketTunnelLoopRunner.swift in Sources`:

```text
		IROCKTCPDIALBUILD001 /* IOSPlatformTCPDialer.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKTCPDIALFILEREF01 /* IOSPlatformTCPDialer.swift */;};
```

- [x] **Step 2: Add group child entry**

In the `irockTunnelExtension` group children list, add this entry immediately after `IOSPacketTunnelLoopRunner.swift`:

```text
				IROCKTCPDIALFILEREF01 /* IOSPlatformTCPDialer.swift */,
```

- [x] **Step 3: Add PBXFileReference entry**

In the `PBXFileReference` section, add this entry immediately after `IOSPacketTunnelLoopRunner.swift`:

```text
		IROCKTCPDIALFILEREF01 /* IOSPlatformTCPDialer.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSPlatformTCPDialer.swift; sourceTree = "<group>";};
```

- [x] **Step 4: Add sources build phase entry**

In the tunnel extension `PBXSourcesBuildPhase` files list, add this entry immediately after `IOSPacketTunnelLoopRunner.swift in Sources`:

```text
IROCKTCPDIALBUILD001 /* IOSPlatformTCPDialer.swift in Sources */,
```

The tunnel sources list should include this sequence:

```text
IROCKSMOKERUNBUILD0001 /* IOSPacketTunnelSmokeRunner.swift in Sources */, IROCKLOOPRUNBUILD001 /* IOSPacketTunnelLoopRunner.swift in Sources */, IROCKTCPDIALBUILD001 /* IOSPlatformTCPDialer.swift in Sources */, IROCKSETCFGDBUILD001 /* PacketTunnelRuntimeSettingsConfiguration.swift in Sources */
```

- [x] **Step 5: Run Xcode scaffold tests**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: PASS.

- [x] **Step 6: Commit Xcode membership**

```bash
git add apps/irock-iOS/irock.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
build: include platform TCP dialer in tunnel target
EOF
)"
```

---

### Task 5: Add and verify M29 design artifact

**Files:**
- Create: `docs/superpowers/specs/2026-05-11-irock-m29-platform-tcp-dialer-design.md`
- Test: `docs/superpowers/specs/2026-05-11-irock-m29-platform-tcp-dialer-design.md`

- [x] **Step 1: Ensure the M29 design document exists**

Create `docs/superpowers/specs/2026-05-11-irock-m29-platform-tcp-dialer-design.md` with the design already prepared for this milestone. It must include these headings:

```markdown
# M29 Platform TCP Dialer Design

## Goal

## Context

## Scope

## Out of scope

## Architecture

## Data flow

## Error and cancellation behavior

## Testing strategy

## Acceptance criteria
```

- [x] **Step 2: Run plan/spec placeholder scans**

Run:

```bash
grep -n "TB[D]\|TO[D]O\|implement late[r]\|fill in detail[s]\|Similar to Tas[k]" docs/superpowers/plans/2026-05-11-irock-m29-platform-tcp-dialer.md docs/superpowers/specs/2026-05-11-irock-m29-platform-tcp-dialer-design.md || true
```

Expected: no output.

- [x] **Step 3: Commit M29 planning artifacts**

```bash
git add docs/superpowers/plans/2026-05-11-irock-m29-platform-tcp-dialer.md docs/superpowers/specs/2026-05-11-irock-m29-platform-tcp-dialer-design.md
git commit -m "$(cat <<'EOF'
docs: add M29 platform TCP dialer plan
EOF
)"
```

---

### Task 6: Run full M29 verification

**Files:**
- No source edits expected.
- Verify all M29 acceptance criteria.

- [x] **Step 1: Run all SwiftPM tests**

Run:

```bash
swift test
```

Expected: PASS with all tests passing.

- [x] **Step 2: Run Xcode project listing**

Run:

```bash
xcodebuild -list -project apps/irock-iOS/irock.xcodeproj
```

Expected: PASS and lists `irockApp` and `irockTunnelExtension` targets/schemes.

- [x] **Step 3: Run unsigned iOS Simulator build**

Run:

```bash
xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

- [x] **Step 4: Run forbidden shared package import scan**

Run:

```bash
grep -R "import NetworkExtension\|import Network\|import Security\|import UIKit\|import AppKit" -n packages Package.swift || true
```

Expected: no output.

- [x] **Step 5: Run allowed tunnel extension platform import scan**

Run:

```bash
grep -R "import NetworkExtension\|import Network" -n apps/irock-iOS/irockTunnelExtension
```

Expected: output only from tunnel extension files, including `IOSPlatformTCPDialer.swift` for `import Network`.

- [x] **Step 6: Inspect final branch state**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean working tree and M29 commits ahead of `origin/main`.
