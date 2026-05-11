# M28 Packet Tunnel Long-Running Packet Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the iOS Packet Tunnel extension's one-shot packet batch with a cancellable long-running provider loop.

**Architecture:** Add an extension-local `IOSPacketTunnelLoopRunner` that repeatedly calls the existing `IOSPacketTunnelSmokeRunner.runOnce(packetFlow:)` batch seam until cancellation. `PacketTunnelProvider` applies network settings, starts the loop in a stored `Task`, returns from `startTunnel(options:)`, and cancels the task from `stopTunnel(with:)`.

**Tech Stack:** Swift, NetworkExtension, Swift Concurrency `Task`, SwiftPM XCTest static scaffold tests, Xcode project source membership.

---

## File Structure

- Create `apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift`
  - Owns extension-local loop lifecycle and pacing.
  - Depends on `IOSPacketTunnelSmokeRunner` and `NEPacketTunnelFlow`.
- Modify `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`
  - Starts the loop runner after applying settings.
  - Stops awaiting a one-shot batch as the provider lifetime.
- Modify `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
  - Adds `IOSPacketTunnelLoopRunner.swift` to the tunnel extension group and sources build phase.
- Modify `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Adds static checks for the loop runner file, Xcode membership, and provider wiring.

---

### Task 1: Add failing scaffold tests for the loop runner boundary

**Files:**
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
- Test: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [ ] **Step 1: Add the new required scaffold file path**

In `requiredScaffoldPaths`, add this entry immediately after `IOSPacketTunnelSmokeRunner.swift`:

```swift
"apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift",
```

The resulting section should be:

```swift
"apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift",
"apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift",
"apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift",
"apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift",
```

- [ ] **Step 2: Add Xcode source membership assertion**

In `testXcodeProjectDeclaresIOSAppAndTunnelTargetShape()`, add this assertion immediately after the existing `IOSPacketTunnelSmokeRunner.swift in Sources` assertion:

```swift
XCTAssertTrue(project.contains("IOSPacketTunnelLoopRunner.swift in Sources"))
```

The relevant assertions should be:

```swift
XCTAssertTrue(project.contains("NEPacketTunnelFlowPacketFlowIO.swift in Sources"))
XCTAssertTrue(project.contains("PacketTunnelAppGroupStoreResolver.swift in Sources"))
XCTAssertTrue(project.contains("IOSPacketTunnelSmokeRunner.swift in Sources"))
XCTAssertTrue(project.contains("IOSPacketTunnelLoopRunner.swift in Sources"))
XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsConfiguration.swift in Sources"))
```

- [ ] **Step 3: Add loop runner boundary test**

Add this test method immediately after `testPacketTunnelSmokePathFilesDeclareExpectedBoundaries()`:

```swift
func testPacketTunnelLoopRunnerDeclaresCancellableLongRunningBoundary() throws {
    let loopRunner = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift"))
    let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))

    XCTAssertTrue(loopRunner.contains("import " + "NetworkExtension"))
    XCTAssertTrue(loopRunner.contains("IOSPacketTunnelSmokeRunner"))
    XCTAssertTrue(loopRunner.contains("Task.isCancelled"))
    XCTAssertTrue(loopRunner.contains("Task.sleep"))
    XCTAssertTrue(loopRunner.contains("while !Task.isCancelled"))
    XCTAssertTrue(provider.contains("IOSPacketTunnelLoopRunner"))
    XCTAssertFalse(provider.contains("IOSPacketTunnelSmokeRunner().runOnce"))
}
```

- [ ] **Step 4: Run focused test and verify it fails**

Run:

```bash
swift test --filter XcodeScaffoldTests/testRequiredIOSScaffoldFilesExist
```

Expected: FAIL with a message containing:

```text
Missing apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift
```

- [ ] **Step 5: Commit the failing test**

```bash
git add packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift
git commit -m "$(cat <<'EOF'
test: require packet tunnel loop runner
EOF
)"
```

---

### Task 2: Implement the extension-local loop runner

**Files:**
- Create: `apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift`
- Test: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [ ] **Step 1: Create `IOSPacketTunnelLoopRunner.swift`**

Create `apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift` with exactly this content:

```swift
import Foundation
import NetworkExtension

struct IOSPacketTunnelLoopRunner: Sendable {
    private let smokeRunner: IOSPacketTunnelSmokeRunner
    private let loopDelayNanoseconds: UInt64

    init(
        smokeRunner: IOSPacketTunnelSmokeRunner = IOSPacketTunnelSmokeRunner(),
        loopDelayNanoseconds: UInt64 = 50_000_000
    ) {
        self.smokeRunner = smokeRunner
        self.loopDelayNanoseconds = loopDelayNanoseconds
    }

    func run(packetFlow: NEPacketTunnelFlow) async throws {
        while !Task.isCancelled {
            _ = try await smokeRunner.runOnce(packetFlow: packetFlow)
            try await Task.sleep(nanoseconds: loopDelayNanoseconds)
        }
    }
}
```

- [ ] **Step 2: Run focused boundary test and verify remaining failures**

Run:

```bash
swift test --filter XcodeScaffoldTests/testPacketTunnelLoopRunnerDeclaresCancellableLongRunningBoundary
```

Expected: FAIL because `PacketTunnelProvider` does not yet contain `IOSPacketTunnelLoopRunner` and still contains `IOSPacketTunnelSmokeRunner().runOnce`.

- [ ] **Step 3: Commit the loop runner file**

```bash
git add apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelLoopRunner.swift
git commit -m "$(cat <<'EOF'
feat: add packet tunnel loop runner
EOF
)"
```

---

### Task 3: Wire PacketTunnelProvider to the loop runner

**Files:**
- Modify: `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`
- Test: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [ ] **Step 1: Replace provider one-shot task with loop task**

Replace the full contents of `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift` with:

```swift
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var startTunnelTask: Task<Void, Error>?

    override func startTunnel(options: [String: NSObject]?) async throws {
        try await PacketTunnelRuntimeSettingsApplicator().apply(to: self)
        let task = Task {
            try await IOSPacketTunnelLoopRunner().run(packetFlow: packetFlow)
        }
        startTunnelTask = task
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        startTunnelTask?.cancel()
        startTunnelTask = nil
    }
}
```

- [ ] **Step 2: Run provider wiring tests**

Run:

```bash
swift test --filter XcodeScaffoldTests/testPacketTunnelLoopRunnerDeclaresCancellableLongRunningBoundary
swift test --filter XcodeScaffoldTests/testPacketTunnelProviderAppliesSettingsBeforeSmokeRunner
```

Expected: both PASS. The existing settings-order test still passes because `IOSPacketTunnelLoopRunner` appears after `PacketTunnelRuntimeSettingsApplicator`.

- [ ] **Step 3: Commit provider wiring**

```bash
git add apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift
git commit -m "$(cat <<'EOF'
feat: run packet tunnel loop from provider
EOF
)"
```

---

### Task 4: Add the loop runner to the Xcode project

**Files:**
- Modify: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
- Test: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [ ] **Step 1: Add PBXBuildFile entry**

In the `PBXBuildFile` section of `apps/irock-iOS/irock.xcodeproj/project.pbxproj`, add:

```text
		B2F30B420000000000000028 /* IOSPacketTunnelLoopRunner.swift in Sources */ = {isa = PBXBuildFile; fileRef = B2F30B410000000000000028 /* IOSPacketTunnelLoopRunner.swift */; };
```

Place it near the existing tunnel extension Swift build files, immediately after `IOSPacketTunnelSmokeRunner.swift in Sources`.

- [ ] **Step 2: Add group child entry**

In the `irockTunnelExtension` group children list, add:

```text
				B2F30B410000000000000028 /* IOSPacketTunnelLoopRunner.swift */,
```

Place it immediately after `IOSPacketTunnelSmokeRunner.swift`.

- [ ] **Step 3: Add PBXFileReference entry**

In the `PBXFileReference` section, add:

```text
		B2F30B410000000000000028 /* IOSPacketTunnelLoopRunner.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSPacketTunnelLoopRunner.swift; sourceTree = "<group>"; };
```

Place it near the existing tunnel extension file references.

- [ ] **Step 4: Add sources build phase entry**

In the tunnel extension `PBXSourcesBuildPhase` files list, add:

```text
				B2F30B420000000000000028 /* IOSPacketTunnelLoopRunner.swift in Sources */,
```

Place it immediately after `IOSPacketTunnelSmokeRunner.swift in Sources`.

- [ ] **Step 5: Run Xcode scaffold tests**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: PASS.

- [ ] **Step 6: Commit Xcode membership**

```bash
git add apps/irock-iOS/irock.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
build: include packet tunnel loop runner in Xcode target
EOF
)"
```

---

### Task 5: Run full M28 verification

**Files:**
- No source edits expected.
- Verify all M28 acceptance criteria.

- [ ] **Step 1: Run all SwiftPM tests**

Run:

```bash
swift test
```

Expected: PASS with all tests passing.

- [ ] **Step 2: Run Xcode project listing**

Run:

```bash
xcodebuild -list -project apps/irock-iOS/irock.xcodeproj
```

Expected: PASS and lists `irockApp` and `irockTunnelExtension` targets/schemes.

- [ ] **Step 3: Run unsigned iOS Simulator build**

Run:

```bash
xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Run forbidden shared package import scan**

Run:

```bash
grep -R "import NetworkExtension\|import Network\|import Security\|import UIKit\|import AppKit" -n packages Package.swift || true
```

Expected: no output.

- [ ] **Step 5: Run allowed tunnel extension NetworkExtension scan**

Run:

```bash
grep -R "import NetworkExtension" -n apps/irock-iOS/irockTunnelExtension
```

Expected: output only from tunnel extension files, including `IOSPacketTunnelLoopRunner.swift`.

- [ ] **Step 6: Run plan placeholder scan**

Run:

```bash
grep -n "TB[D]\|TO[D]O\|implement late[r]\|fill in detail[s]\|Similar to Tas[k]" docs/superpowers/plans/2026-05-11-irock-m28-packet-tunnel-long-running-loop.md || true
```

Expected: no output.

---

### Task 6: Finish branch

**Files:**
- Commit any verification-driven corrections first.

- [ ] **Step 1: Inspect final branch state**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean working tree and M28 commits ahead of `origin/main`.

- [ ] **Step 2: Push branch and create PR**

Run:

```bash
git push -u origin worktree-m28-packet-tunnel-long-running-loop
gh pr create --title "Add Packet Tunnel long-running loop" --body "$(cat <<'EOF'
## Summary
- Add a cancellable iOS Packet Tunnel loop runner around the existing runtime batch seam
- Wire PacketTunnelProvider to start the loop after applying network settings and cancel it on stop
- Extend scaffold validation and Xcode source membership for the loop runner

## Test Plan
- [ ] swift test
- [ ] swift test --filter XcodeScaffoldTests
- [ ] xcodebuild -list -project apps/irock-iOS/irock.xcodeproj
- [ ] xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
- [ ] grep -R "import NetworkExtension\\|import Network\\|import Security\\|import UIKit\\|import AppKit" -n packages Package.swift || true
- [ ] grep -R "import NetworkExtension" -n apps/irock-iOS/irockTunnelExtension
EOF
)"
```

Expected: PR URL is printed.

- [ ] **Step 3: Squash merge PR and delete remote branch**

Run:

```bash
gh pr merge --squash --delete-branch
```

Expected: PR is merged. If local checkout cleanup fails because `main` is used by the primary worktree, verify PR state with `gh pr view --json state,mergeCommit,url`, delete the remote branch with `git push origin --delete worktree-m28-packet-tunnel-long-running-loop`, then continue cleanup manually.

- [ ] **Step 4: Fast-forward primary main and prepare M29 branch**

Run:

```bash
git -C /Users/yiwei/irock pull --ff-only
git fetch --prune
git checkout -B worktree-m29-platform-tcp-dialer origin/main
```

Expected: current worktree is on `worktree-m29-platform-tcp-dialer` tracking the new `origin/main` state.

- [ ] **Step 5: Delete local M28 branch after squash equivalence check**

Run:

```bash
git diff --stat worktree-m28-packet-tunnel-long-running-loop origin/main
git branch -D worktree-m28-packet-tunnel-long-running-loop
```

Expected: diff output is empty before branch deletion.
