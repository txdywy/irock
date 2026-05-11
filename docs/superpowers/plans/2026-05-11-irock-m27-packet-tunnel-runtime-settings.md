# M27 Packet Tunnel Runtime Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic `NEPacketTunnelNetworkSettings` construction and application before the existing iOS Packet Tunnel smoke runner starts.

**Architecture:** Keep all `NetworkExtension` settings code in `apps/irock-iOS/irockTunnelExtension`. Split settings defaults, factory, and applicator into focused extension-local files. Validate with SwiftPM static tests plus unsigned iOS Simulator Xcode builds.

**Tech Stack:** Swift 5.10, SwiftPM, XCTest, Xcode project scaffold, NetworkExtension.

---

## File Structure

- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Add static validation for runtime settings files, Xcode source membership, default values, and provider startup ordering.
- Modify: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
  - Add new settings Swift files to the tunnel extension group and source build phase.
- Modify: `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`
  - Apply runtime settings before running the M26 smoke runner.
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift`
  - Deterministic settings defaults.
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift`
  - Builds `NEPacketTunnelNetworkSettings` from configuration.
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift`
  - Applies settings to an `NEPacketTunnelProvider`.

---

### Task 1: Static Runtime Settings Validation

**Files:**
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [ ] **Step 1: Add failing M27 static validation**

Modify `requiredScaffoldPaths` to include:

```swift
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift",
```

Place those entries after `IOSPacketTunnelSmokeRunner.swift` in the tunnel extension file list.

Modify `testXcodeProjectDeclaresIOSAppAndTunnelTargetShape()` to include:

```swift
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsConfiguration.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsFactory.swift in Sources"))
        XCTAssertTrue(project.contains("PacketTunnelRuntimeSettingsApplicator.swift in Sources"))
```

Add these tests before `private var repositoryRoot`:

```swift
    func testPacketTunnelRuntimeSettingsFilesDeclareExpectedDefaults() throws {
        let configuration = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift"))
        let factory = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift"))
        let applicator = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift"))

        XCTAssertTrue(configuration.contains("10.255.0.2"))
        XCTAssertTrue(configuration.contains("255.255.255.0"))
        XCTAssertTrue(configuration.contains("1.1.1.1"))
        XCTAssertTrue(configuration.contains("8.8.8.8"))
        XCTAssertTrue(configuration.contains("1500"))
        XCTAssertTrue(factory.contains("NEPacketTunnelNetworkSettings"))
        XCTAssertTrue(factory.contains("NEIPv4Settings"))
        XCTAssertTrue(factory.contains("NEDNSSettings"))
        XCTAssertTrue(factory.contains(".default()"))
        XCTAssertTrue(applicator.contains("setTunnelNetworkSettings"))
    }

    func testPacketTunnelProviderAppliesSettingsBeforeSmokeRunner() throws {
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))
        let settingsRange = try XCTUnwrap(provider.range(of: "PacketTunnelRuntimeSettingsApplicator"))
        let smokeRange = try XCTUnwrap(provider.range(of: "IOSPacketTunnelSmokeRunner"))

        XCTAssertLessThan(settingsRange.lowerBound, smokeRange.lowerBound)
        XCTAssertTrue(provider.contains("apply(to: self)"))
    }
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: tests compile and fail because the M27 settings files do not exist, provider does not apply settings, and the Xcode source phase does not include the new files.

- [ ] **Step 3: Commit failing validation tests**

Run:

```bash
git add packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift
git commit -m "test: add packet tunnel runtime settings validation"
```

---

### Task 2: Runtime Settings Helpers and Provider Wiring

**Files:**
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift`
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift`
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift`
- Modify: `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`

- [ ] **Step 1: Create runtime settings configuration**

Create `apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsConfiguration.swift`:

```swift
struct PacketTunnelRuntimeSettingsConfiguration: Equatable, Sendable {
    let tunnelRemoteAddress: String
    let ipv4Address: String
    let ipv4SubnetMask: String
    let dnsServers: [String]
    let mtu: Int

    init(
        tunnelRemoteAddress: String = "127.0.0.1",
        ipv4Address: String = "10.255.0.2",
        ipv4SubnetMask: String = "255.255.255.0",
        dnsServers: [String] = ["1.1.1.1", "8.8.8.8"],
        mtu: Int = 1500
    ) {
        self.tunnelRemoteAddress = tunnelRemoteAddress
        self.ipv4Address = ipv4Address
        self.ipv4SubnetMask = ipv4SubnetMask
        self.dnsServers = dnsServers
        self.mtu = mtu
    }
}
```

- [ ] **Step 2: Create runtime settings factory**

Create `apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsFactory.swift`:

```swift
import NetworkExtension

struct PacketTunnelRuntimeSettingsFactory: Sendable {
    let configuration: PacketTunnelRuntimeSettingsConfiguration

    init(configuration: PacketTunnelRuntimeSettingsConfiguration = PacketTunnelRuntimeSettingsConfiguration()) {
        self.configuration = configuration
    }

    func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: configuration.tunnelRemoteAddress)
        let ipv4Settings = NEIPv4Settings(addresses: [configuration.ipv4Address], subnetMasks: [configuration.ipv4SubnetMask])
        ipv4Settings.includedRoutes = [.default()]
        settings.ipv4Settings = ipv4Settings
        settings.dnsSettings = NEDNSSettings(servers: configuration.dnsServers)
        settings.mtu = NSNumber(value: configuration.mtu)
        return settings
    }
}
```

- [ ] **Step 3: Create runtime settings applicator**

Create `apps/irock-iOS/irockTunnelExtension/PacketTunnelRuntimeSettingsApplicator.swift`:

```swift
import NetworkExtension

struct PacketTunnelRuntimeSettingsApplicator: Sendable {
    private let factory: PacketTunnelRuntimeSettingsFactory

    init(factory: PacketTunnelRuntimeSettingsFactory = PacketTunnelRuntimeSettingsFactory()) {
        self.factory = factory
    }

    func apply(to provider: NEPacketTunnelProvider) async throws {
        try await provider.setTunnelNetworkSettings(factory.makeNetworkSettings())
    }
}
```

- [ ] **Step 4: Update provider startup ordering**

Replace `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift` with:

```swift
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var startTunnelTask: Task<Void, Error>?

    override func startTunnel(options: [String: NSObject]?) async throws {
        try await PacketTunnelRuntimeSettingsApplicator().apply(to: self)
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

- [ ] **Step 5: Run validation before Xcode project update**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: settings file existence/default/provider-order tests pass, but Xcode source membership assertions still fail.

---

### Task 3: Xcode Project Source Membership

**Files:**
- Modify: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add build file entries**

In the `PBXBuildFile section`, add after `IROCKSMOKERUNBUILD0001`:

```text
		IROCKSETCFGDBUILD001 /* PacketTunnelRuntimeSettingsConfiguration.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKSETCFGDFILEREF1 /* PacketTunnelRuntimeSettingsConfiguration.swift */;};
		IROCKSETFACTBUILD01 /* PacketTunnelRuntimeSettingsFactory.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKSETFACTFILEREF01 /* PacketTunnelRuntimeSettingsFactory.swift */;};
		IROCKSETAPPBUILD001 /* PacketTunnelRuntimeSettingsApplicator.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKSETAPPFILEREF001 /* PacketTunnelRuntimeSettingsApplicator.swift */;};
```

- [ ] **Step 2: Add extension group children**

In `IROCKTUNNELGROUP0000001` children, add after `IOSPacketTunnelSmokeRunner.swift`:

```text
				IROCKSETCFGDFILEREF1 /* PacketTunnelRuntimeSettingsConfiguration.swift */,
				IROCKSETFACTFILEREF01 /* PacketTunnelRuntimeSettingsFactory.swift */,
				IROCKSETAPPFILEREF001 /* PacketTunnelRuntimeSettingsApplicator.swift */,
```

- [ ] **Step 3: Add file references**

In the `PBXFileReference section`, add after `IROCKSMOKERUNFILEREF001`:

```text
		IROCKSETCFGDFILEREF1 /* PacketTunnelRuntimeSettingsConfiguration.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PacketTunnelRuntimeSettingsConfiguration.swift; sourceTree = "<group>";};
		IROCKSETFACTFILEREF01 /* PacketTunnelRuntimeSettingsFactory.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PacketTunnelRuntimeSettingsFactory.swift; sourceTree = "<group>";};
		IROCKSETAPPFILEREF001 /* PacketTunnelRuntimeSettingsApplicator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PacketTunnelRuntimeSettingsApplicator.swift; sourceTree = "<group>";};
```

- [ ] **Step 4: Add files to extension sources phase**

Replace the `IROCKTUNNELSOURCES000001` line with:

```text
		IROCKTUNNELSOURCES000001 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (IROCKPROVIDERBUILD00001 /* PacketTunnelProvider.swift in Sources */, IROCKFLOWIOBUILD000001 /* NEPacketTunnelFlowPacketFlowIO.swift in Sources */, IROCKSTORERESBUILD0001 /* PacketTunnelAppGroupStoreResolver.swift in Sources */, IROCKSMOKERUNBUILD0001 /* IOSPacketTunnelSmokeRunner.swift in Sources */, IROCKSETCFGDBUILD001 /* PacketTunnelRuntimeSettingsConfiguration.swift in Sources */, IROCKSETFACTBUILD01 /* PacketTunnelRuntimeSettingsFactory.swift in Sources */, IROCKSETAPPBUILD001 /* PacketTunnelRuntimeSettingsApplicator.swift in Sources */); runOnlyForDeploymentPostprocessing = 0;};
```

- [ ] **Step 5: Run scaffold validation**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: all `XcodeScaffoldTests` pass.

- [ ] **Step 6: Commit runtime settings implementation**

Run:

```bash
git add apps/irock-iOS packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift
git commit -m "feat: add packet tunnel runtime settings"
```

---

### Task 4: Full Verification and Review Prep

**Files:**
- Modify plan only if verification discovers a command or type typo.

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

Expected: command exits 0 and lists `irockApp` and `irockTunnelExtension`.

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

Expected: `NetworkExtension` appears only in tunnel extension Swift files.

- [ ] **Step 6: Scan this plan for placeholders and command typos**

Run:

```bash
grep -nE '[T]BD|[T]ODO|[i]mplement later|[f]ill in|n[g]it|n[g]rep' docs/superpowers/plans/2026-05-11-irock-m27-packet-tunnel-runtime-settings.md || true
```

Expected: no output.

- [ ] **Step 7: Commit plan if not already committed**

Run:

```bash
git add docs/superpowers/plans/2026-05-11-irock-m27-packet-tunnel-runtime-settings.md
git commit -m "docs: add M27 packet tunnel runtime settings plan"
```

- [ ] **Step 8: Prepare branch for PR**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean worktree and M27 roadmap, design, plan, validation, and implementation commits.
