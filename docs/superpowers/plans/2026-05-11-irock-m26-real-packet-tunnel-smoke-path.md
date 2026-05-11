# M26 Real Packet Tunnel Smoke Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the iOS Packet Tunnel extension scaffold to the existing packet-flow, App Group store, and runtime controller seams with a one-shot smoke path.

**Architecture:** Keep `NetworkExtension` code only under `apps/irock-iOS/irockTunnelExtension`. Add small extension-local helper types for packet-flow adaptation, App Group store resolution, and smoke-runner orchestration. Use SwiftPM static tests and unsigned Xcode simulator build checks instead of requiring real signing or live VPN execution.

**Tech Stack:** Swift 5.10, SwiftPM, XCTest, Xcode project scaffold, NetworkExtension, IrockTunnelCore, IrockStorage, IrockTransport.

---

## File Structure

- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Add static validation for new M26 extension smoke-path files, source membership, provider wiring, and platform import boundaries.
- Modify: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
  - Add new extension Swift files to the group and source build phase.
- Modify: `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`
  - Call the smoke runner from `startTunnel(options:)` and cancel it from `stopTunnel(with:)`.
- Create: `apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift`
  - Extension-local `NEPacketTunnelFlow` adapter conforming to `PacketFlowIO`.
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift`
  - Extension-local App Group container resolver and `RuntimeStoreBundle` builder.
- Create: `apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift`
  - One-shot runner that wires the flow adapter, store bundle, and `TunnelRuntimeController`.

---

### Task 1: Static Smoke-Path Validation

**Files:**
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [ ] **Step 1: Add failing static validation tests**

Modify `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` so `requiredScaffoldPaths` includes the three new extension files:

```swift
    private var requiredScaffoldPaths: [String] {
        [
            "apps/irock-iOS/irock.xcodeproj/project.pbxproj",
            "apps/irock-iOS/irockApp/IrockApp.swift",
            "apps/irock-iOS/irockApp/ContentView.swift",
            "apps/irock-iOS/irockApp/Info.plist",
            "apps/irock-iOS/irockApp/irockApp.entitlements",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift",
            "apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift",
            "apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift",
            "apps/irock-iOS/irockTunnelExtension/Info.plist",
            "apps/irock-iOS/irockTunnelExtension/irockTunnelExtension.entitlements"
        ]
    }
```

Add these test methods before `private var repositoryRoot`:

```swift
    func testPacketTunnelProviderWiresSmokeRunner() throws {
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))

        XCTAssertTrue(provider.contains("IOSPacketTunnelSmokeRunner"))
        XCTAssertTrue(provider.contains("startTunnelTask"))
        XCTAssertTrue(provider.contains("packetFlow"))
        XCTAssertTrue(provider.contains("cancel()"))
    }

    func testPacketTunnelSmokePathFilesDeclareExpectedBoundaries() throws {
        let flowAdapter = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift"))
        let storeResolver = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift"))
        let smokeRunner = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift"))

        XCTAssertTrue(flowAdapter.contains("import " + "NetworkExtension"))
        XCTAssertTrue(flowAdapter.contains("PacketFlowIO"))
        XCTAssertTrue(flowAdapter.contains("readPacketObjects"))
        XCTAssertTrue(flowAdapter.contains("writePacketObjects"))
        XCTAssertTrue(storeResolver.contains("containerURL(forSecurityApplicationGroupIdentifier:"))
        XCTAssertTrue(storeResolver.contains("AppGroupRuntimeStoreDirectory"))
        XCTAssertTrue(storeResolver.contains("group.dev.irock.shared"))
        XCTAssertTrue(smokeRunner.contains("TunnelRuntimeController.runShadowsocksTCPBatch"))
        XCTAssertTrue(smokeRunner.contains("UnsupportedTransportAdapter"))
    }

    func testNetworkExtensionImportsStayInsideTunnelExtension() throws {
        let forbiddenRoots = [
            repositoryRoot.appendingPathComponent("packages"),
            repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp")
        ]

        for root in forbiddenRoots {
            for file in try swiftFiles(under: root) {
                let contents = try String(contentsOf: file)
                XCTAssertFalse(contents.contains("import " + "NetworkExtension"), "NetworkExtension leaked into \(file.path)")
            }
        }
    }
```

Modify `testXcodeProjectDeclaresIOSAppAndTunnelTargetShape()` so it also asserts the new source files are members of the project:

```swift
        XCTAssertTrue(project.contains("NEPacketTunnelFlowPacketFlowIO.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelAppGroupStoreResolver.swift in Sources"))
        XCTAssertTrue(project.contains("IOSPacketTunnelSmokeRunner.swift in Sources"))
```

- [ ] **Step 2: Run static scaffold tests to verify failure**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: tests compile and fail because the three M26 extension files do not exist and are not listed in the Xcode source phase.

- [ ] **Step 3: Commit failing validation tests**

Run:

```bash
git add packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift
git commit -m "test: add packet tunnel smoke path validation"
```

---

### Task 2: Extension-Local Smoke Path Files

**Files:**
- Create: `apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift`
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift`
- Create: `apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift`
- Modify: `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`

- [ ] **Step 1: Create packet-flow adapter**

Create `apps/irock-iOS/irockTunnelExtension/NEPacketTunnelFlowPacketFlowIO.swift`:

```swift
import Foundation
import IrockTunnelCore
import NetworkExtension

struct NEPacketTunnelFlowPacketFlowIO: PacketFlowIO {
    private let packetFlow: NEPacketTunnelFlow

    init(packetFlow: NEPacketTunnelFlow) {
        self.packetFlow = packetFlow
    }

    func readPackets(limit: Int) async throws -> [Packet] {
        let packets = await packetFlow.readPacketObjects()
        return packets.prefix(max(0, limit)).enumerated().map { index, packet in
            Packet(id: "ne-packet-\(index)", bytes: Array(packet.data))
        }
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        let packets = results.compactMap { result -> NEPacket? in
            switch result.action {
            case .direct, .proxy:
                return NEPacket(data: Data(result.packet.bytes), protocolFamily: sa_family_t(AF_INET))
            case .reject, .drop:
                return nil
            }
        }
        guard !packets.isEmpty else { return }
        await packetFlow.writePacketObjects(packets)
    }
}
```

- [ ] **Step 2: Create App Group store resolver**

Create `apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift`:

```swift
import Foundation
import IrockStorage

struct PacketTunnelAppGroupStoreResolver: Sendable {
    enum ResolverError: Error, Equatable, Sendable {
        case missingContainer(String)
    }

    let appGroupIdentifier: String
    private let fileManager: FileManager

    init(appGroupIdentifier: String = "group.dev.irock.shared", fileManager: FileManager = .default) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fileManager = fileManager
    }

    func makeRuntimeStoreBundle(logLimit: Int = 200) throws -> RuntimeStoreBundle {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw ResolverError.missingContainer(appGroupIdentifier)
        }
        return AppGroupRuntimeStoreDirectory(containerURL: containerURL).makeRuntimeStoreBundle(logLimit: logLimit, fileManager: fileManager)
    }
}
```

- [ ] **Step 3: Create one-shot smoke runner**

Create `apps/irock-iOS/irockTunnelExtension/IOSPacketTunnelSmokeRunner.swift`:

```swift
import IrockStorage
import IrockTransport
import IrockTunnelCore
import NetworkExtension

struct IOSPacketTunnelSmokeRunner: Sendable {
    private let storeResolver: PacketTunnelAppGroupStoreResolver
    private let batchLimit: Int
    private let flowLimit: Int

    init(
        storeResolver: PacketTunnelAppGroupStoreResolver = PacketTunnelAppGroupStoreResolver(),
        batchLimit: Int = 8,
        flowLimit: Int = 64
    ) {
        self.storeResolver = storeResolver
        self.batchLimit = batchLimit
        self.flowLimit = flowLimit
    }

    func runOnce(packetFlow: NEPacketTunnelFlow) async throws -> PacketTunnelRuntimeSummary {
        let stores = try storeResolver.makeRuntimeStoreBundle()
        return try await TunnelRuntimeController.runShadowsocksTCPBatch(
            snapshotStore: stores.snapshotStore,
            flow: NEPacketTunnelFlowPacketFlowIO(packetFlow: packetFlow),
            statusStore: stores.statusStore,
            logStore: stores.logStore,
            plain: UnsupportedTransportAdapter(transport: .tcp),
            tls: UnsupportedTransportAdapter(transport: .tcp),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
}
```

- [ ] **Step 4: Update PacketTunnelProvider**

Replace `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift` with:

```swift
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var startTunnelTask: Task<Void, Error>?

    override func startTunnel(options: [String: NSObject]?) async throws {
        let task = Task {
            _ = try await IOSPacketTunnelSmokeRunner().runOnce(packetFlow: packetFlow)
        }
        startTunnelTask = task
        try await task.value
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        startTunnelTask?.cancel()
        startTunnelTask = nil
    }
}
```

- [ ] **Step 5: Run scaffold validation before Xcode project update**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: file existence and provider wiring assertions pass, but Xcode project source membership assertions fail because the new files are not yet in `project.pbxproj`.

---

### Task 3: Xcode Project Source Membership

**Files:**
- Modify: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add build file entries**

In the `PBXBuildFile section`, add these entries after `IROCKPROVIDERBUILD00001`:

```text
		IROCKFLOWIOBUILD000001 /* NEPacketTunnelFlowPacketFlowIO.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKFLOWIOFILEREF00001 /* NEPacketTunnelFlowPacketFlowIO.swift */;};
		IROCKSTORERESBUILD0001 /* PacketTunnelAppGroupStoreResolver.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKSTORERESFILEREF001 /* PacketTunnelAppGroupStoreResolver.swift */;};
		IROCKSMOKERUNBUILD0001 /* IOSPacketTunnelSmokeRunner.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKSMOKERUNFILEREF001 /* IOSPacketTunnelSmokeRunner.swift */;};
```

- [ ] **Step 2: Add extension group children**

In `IROCKTUNNELGROUP0000001` children, add the new file references after `PacketTunnelProvider.swift`:

```text
					IROCKFLOWIOFILEREF00001 /* NEPacketTunnelFlowPacketFlowIO.swift */,
					IROCKSTORERESFILEREF001 /* PacketTunnelAppGroupStoreResolver.swift */,
					IROCKSMOKERUNFILEREF001 /* IOSPacketTunnelSmokeRunner.swift */,
```

- [ ] **Step 3: Add file references**

In the `PBXFileReference section`, add these entries after `IROCKPROVIDERFILEREF001`:

```text
		IROCKFLOWIOFILEREF00001 /* NEPacketTunnelFlowPacketFlowIO.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NEPacketTunnelFlowPacketFlowIO.swift; sourceTree = "<group>";};
		IROCKSTORERESFILEREF001 /* PacketTunnelAppGroupStoreResolver.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PacketTunnelAppGroupStoreResolver.swift; sourceTree = "<group>";};
		IROCKSMOKERUNFILEREF001 /* IOSPacketTunnelSmokeRunner.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSPacketTunnelSmokeRunner.swift; sourceTree = "<group>";};
```

- [ ] **Step 4: Add files to extension sources phase**

Replace the `IROCKTUNNELSOURCES000001` line with:

```text
		IROCKTUNNELSOURCES000001 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (IROCKPROVIDERBUILD00001 /* PacketTunnelProvider.swift in Sources */, IROCKFLOWIOBUILD000001 /* NEPacketTunnelFlowPacketFlowIO.swift in Sources */, IROCKSTORERESBUILD0001 /* PacketTunnelAppGroupStoreResolver.swift in Sources */, IROCKSMOKERUNBUILD0001 /* IOSPacketTunnelSmokeRunner.swift in Sources */); runOnlyForDeploymentPostprocessing = 0;};
```

- [ ] **Step 5: Run scaffold validation**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: all `XcodeScaffoldTests` pass.

- [ ] **Step 6: Commit smoke-path files and Xcode project wiring**

Run:

```bash
git add apps/irock-iOS packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift
git commit -m "feat: add packet tunnel smoke path wiring"
```

---

### Task 4: Full Verification and Review Prep

**Files:**
- Modify plan only if verification discovers a typo in the plan commands.

- [ ] **Step 1: Run full SwiftPM tests**

Run:

```bash
swift test
```

Expected: all SwiftPM tests pass.

- [ ] **Step 2: Verify Xcode project listing**

Run:

```bash
xcodebuild -list -project apps/irock-iOS/irock.xcodeproj
```

Expected: command exits 0 and lists the `irockApp` target/scheme information available from the scaffold.

- [ ] **Step 3: Verify unsigned iOS Simulator build**

Run:

```bash
xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED` without requiring a development team or provisioning profile.

- [ ] **Step 4: Run forbidden shared package import scan**

Run:

```bash
grep -R "import NetworkExtension\|import Network\|import Security\|import UIKit\|import AppKit" -n packages Package.swift || true
```

Expected: no output.

- [ ] **Step 5: Run allowed extension import scan**

Run:

```bash
grep -R "import NetworkExtension" -n apps/irock-iOS/irockTunnelExtension
```

Expected: `NetworkExtension` appears only in the tunnel extension Swift files.

- [ ] **Step 6: Scan this plan for placeholders and command typos**

Run:

```bash
grep -nE '[T]BD|[T]ODO|[i]mplement later|[f]ill in|n[g]it|n[g]rep' docs/superpowers/plans/2026-05-11-irock-m26-real-packet-tunnel-smoke-path.md || true
```

Expected: no output.

- [ ] **Step 7: Commit plan if not already committed**

Run:

```bash
git add docs/superpowers/plans/2026-05-11-irock-m26-real-packet-tunnel-smoke-path.md
git commit -m "docs: add M26 packet tunnel smoke path plan"
```

- [ ] **Step 8: Prepare branch for PR**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean worktree and M26 design, plan, validation, and implementation commits.
