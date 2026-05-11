# M32 Container App VPN Manager Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add an iOS app-local `NETunnelProviderManager` boundary so the container app can install, start, stop, and query the Packet Tunnel configuration.

**Architecture:** Keep `NetworkExtension` inside `apps/irock-iOS/irockApp` and never in shared Swift packages. Add a deterministic manager configuration plus a thin async manager wrapper in the iOS app target, then wire the app shell to the shared `IrockRootView` without adding production VPN controls yet. Static tooling tests protect Xcode source membership and platform import boundaries.

**Tech Stack:** Swift 5.10, SwiftUI, NetworkExtension, SwiftPM, XCTest, Xcode project scaffold.

---

## Files

- Create: `apps/irock-iOS/irockApp/IOSVPNManagerConfiguration.swift`
  - Holds placeholder provider bundle identifier, localized description, server address, and App Group identifier.
- Create: `apps/irock-iOS/irockApp/IOSVPNManager.swift`
  - Wraps `NETunnelProviderManager` load/save/start/stop/status operations.
- Modify: `apps/irock-iOS/irockApp/ContentView.swift`
  - Hosts `IrockRootView` with a shared `AppViewModel`.
- Modify: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
  - Adds both new Swift files to the app group and app target Sources phase.
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Adds static tests for manager files, project membership, and platform import placement.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m32-container-app-vpn-manager-integration-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m32-container-app-vpn-manager-integration.md`

## Task 1: iOS VPN manager scaffold contract

- [x] **Step 1: Write the failing static test**

Add this test to `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` after `testPacketTunnelProviderWiresLoopRunner`:

```swift
func testContainerAppDeclaresVPNManagerBoundary() throws {
    let configuration = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/IOSVPNManagerConfiguration.swift"))
    let manager = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/IOSVPNManager.swift"))
    let project = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irock.xcodeproj/project.pbxproj"))

    XCTAssertTrue(configuration.contains("struct IOSVPNManagerConfiguration"))
    XCTAssertTrue(configuration.contains("dev.irock.app.tunnel"))
    XCTAssertTrue(configuration.contains("group.dev.irock.shared"))
    XCTAssertTrue(manager.contains("import " + "NetworkExtension"))
    XCTAssertTrue(manager.contains("final class IOSVPNManager"))
    XCTAssertTrue(manager.contains("NETunnelProviderManager.loadAllFromPreferences"))
    XCTAssertTrue(manager.contains("NETunnelProviderProtocol"))
    XCTAssertTrue(manager.contains("providerBundleIdentifier"))
    XCTAssertTrue(manager.contains("saveToPreferences"))
    XCTAssertTrue(manager.contains("startVPNTunnel"))
    XCTAssertTrue(manager.contains("stopVPNTunnel"))
    XCTAssertTrue(project.contains("IOSVPNManagerConfiguration.swift in Sources"))
    XCTAssertTrue(project.contains("IOSVPNManager.swift in Sources"))
}
```

Also update `requiredScaffoldPaths` in the same file to include:

```swift
"apps/irock-iOS/irockApp/IOSVPNManagerConfiguration.swift",
"apps/irock-iOS/irockApp/IOSVPNManager.swift",
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter XcodeScaffoldTests/testContainerAppDeclaresVPNManagerBoundary`

Expected: FAIL because the manager files do not exist.

- [x] **Step 3: Add manager configuration file**

Create `apps/irock-iOS/irockApp/IOSVPNManagerConfiguration.swift`:

```swift
import Foundation

struct IOSVPNManagerConfiguration: Equatable, Sendable {
    let providerBundleIdentifier: String
    let localizedDescription: String
    let serverAddress: String
    let appGroupIdentifier: String

    static let `default` = IOSVPNManagerConfiguration(
        providerBundleIdentifier: "dev.irock.app.tunnel",
        localizedDescription: "irock Packet Tunnel",
        serverAddress: "irock.local",
        appGroupIdentifier: "group.dev.irock.shared"
    )
}
```

- [x] **Step 4: Add manager wrapper file**

Create `apps/irock-iOS/irockApp/IOSVPNManager.swift`:

```swift
import Foundation
import NetworkExtension

struct IOSVPNConnectionStatus: Equatable, Sendable {
    let isInstalled: Bool
    let isEnabled: Bool
    let statusDescription: String
}

final class IOSVPNManager {
    private let configuration: IOSVPNManagerConfiguration

    init(configuration: IOSVPNManagerConfiguration = .default) {
        self.configuration = configuration
    }

    func installOrUpdate() async throws {
        let manager = try await loadOrCreateManager()
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = configuration.providerBundleIdentifier
        tunnelProtocol.serverAddress = configuration.serverAddress
        tunnelProtocol.providerConfiguration = ["appGroupIdentifier": configuration.appGroupIdentifier]
        manager.protocolConfiguration = tunnelProtocol
        manager.localizedDescription = configuration.localizedDescription
        manager.isEnabled = true
        try await manager.saveToPreferences()
    }

    func start() async throws {
        let manager = try await loadOrCreateManager()
        if manager.protocolConfiguration == nil || !manager.isEnabled {
            try await installOrUpdate()
        }
        let currentManager = try await loadOrCreateManager()
        try currentManager.connection.startVPNTunnel()
    }

    func stop() async throws {
        let manager = try await loadOrCreateManager()
        manager.connection.stopVPNTunnel()
    }

    func status() async throws -> IOSVPNConnectionStatus {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first(where: matchesConfiguration) else {
            return IOSVPNConnectionStatus(isInstalled: false, isEnabled: false, statusDescription: "notInstalled")
        }
        return IOSVPNConnectionStatus(isInstalled: true, isEnabled: manager.isEnabled, statusDescription: statusDescription(manager.connection.status))
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first(where: matchesConfiguration) {
            return existing
        }
        return NETunnelProviderManager()
    }

    private func matchesConfiguration(_ manager: NETunnelProviderManager) -> Bool {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return false
        }
        return tunnelProtocol.providerBundleIdentifier == configuration.providerBundleIdentifier
    }

    private func statusDescription(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid:
            return "invalid"
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reasserting:
            return "reasserting"
        case .disconnecting:
            return "disconnecting"
        @unknown default:
            return "unknown"
        }
    }
}
```

- [x] **Step 5: Add files to Xcode project**

Modify `apps/irock-iOS/irock.xcodeproj/project.pbxproj`:

Add build file entries near existing app build files:

```text
		IROCKVPNCFGBUILD00001 /* IOSVPNManagerConfiguration.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKVPNCFGFILEREF001 /* IOSVPNManagerConfiguration.swift */;};
		IROCKVPNMGRBUILD00001 /* IOSVPNManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKVPNMGRFILEREF001 /* IOSVPNManager.swift */;};
```

Add app group children after `ContentView.swift`:

```text
				IROCKVPNCFGFILEREF001 /* IOSVPNManagerConfiguration.swift */,
				IROCKVPNMGRFILEREF001 /* IOSVPNManager.swift */,
```

Add file references after `ContentView.swift` file reference:

```text
		IROCKVPNCFGFILEREF001 /* IOSVPNManagerConfiguration.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSVPNManagerConfiguration.swift; sourceTree = "<group>";};
		IROCKVPNMGRFILEREF001 /* IOSVPNManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSVPNManager.swift; sourceTree = "<group>";};
```

Update the app sources build phase from:

```text
files = (IROCKAPPFILEBUILD000001 /* IrockApp.swift in Sources */, IROCKCONTENTBUILD000001 /* ContentView.swift in Sources */);
```

to:

```text
files = (IROCKAPPFILEBUILD000001 /* IrockApp.swift in Sources */, IROCKCONTENTBUILD000001 /* ContentView.swift in Sources */, IROCKVPNCFGBUILD00001 /* IOSVPNManagerConfiguration.swift in Sources */, IROCKVPNMGRBUILD00001 /* IOSVPNManager.swift in Sources */);
```

- [x] **Step 6: Run test to verify it passes**

Run: `swift test --filter XcodeScaffoldTests/testContainerAppDeclaresVPNManagerBoundary`

Expected: PASS.

## Task 2: Container app hosts shared root feature

- [x] **Step 1: Write the failing static test**

Add this test to `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` after `testContainerAppDeclaresVPNManagerBoundary`:

```swift
func testContainerAppHostsSharedRootView() throws {
    let contentView = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/ContentView.swift"))

    XCTAssertTrue(contentView.contains("import " + "IrockAppFeature"))
    XCTAssertTrue(contentView.contains("@StateObject"))
    XCTAssertTrue(contentView.contains("AppViewModel"))
    XCTAssertTrue(contentView.contains("IrockRootView(viewModel: viewModel)"))
    XCTAssertFalse(contentView.contains("Text(\"irock\")"))
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter XcodeScaffoldTests/testContainerAppHostsSharedRootView`

Expected: FAIL because `ContentView` still renders placeholder text.

- [x] **Step 3: Update ContentView**

Replace `apps/irock-iOS/irockApp/ContentView.swift` with:

```swift
import IrockAppFeature
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel(nodes: [])

    var body: some View {
        IrockRootView(viewModel: viewModel)
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter XcodeScaffoldTests/testContainerAppHostsSharedRootView`

Expected: PASS.

## Task 3: App platform import boundary update

- [x] **Step 1: Write the failing static test update**

Update `testPlatformImportsStayInsideTunnelExtension` in `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` so app-local `NetworkExtension` is allowed but `Network`, `Security`, `UIKit`, and `AppKit` remain forbidden in the app target.

Replace the test with:

```swift
func testPlatformImportsStayInsidePlatformTargets() throws {
    let forbiddenPackageImports = [
        "import " + "NetworkExtension",
        "import " + "Network",
        "import " + "Security",
        "import " + "UIKit",
        "import " + "AppKit"
    ]
    for file in try swiftFiles(under: repositoryRoot.appendingPathComponent("packages")) {
        let contents = try String(contentsOf: file)
        for forbiddenImport in forbiddenPackageImports {
            XCTAssertFalse(contents.contains(forbiddenImport), "\(forbiddenImport) leaked into \(file.path)")
        }
    }

    let forbiddenAppImports = [
        "import " + "Network",
        "import " + "Security",
        "import " + "UIKit",
        "import " + "AppKit"
    ]
    for file in try swiftFiles(under: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp")) {
        let contents = try String(contentsOf: file)
        for forbiddenImport in forbiddenAppImports {
            XCTAssertFalse(contents.contains(forbiddenImport), "\(forbiddenImport) leaked into \(file.path)")
        }
    }
}
```

- [x] **Step 2: Run test to verify it passes after Task 1**

Run: `swift test --filter XcodeScaffoldTests/testPlatformImportsStayInsidePlatformTargets`

Expected: PASS, with `NetworkExtension` allowed only in iOS app/tunnel target files.

## Task 4: Full verification

- [x] **Step 1: Run tooling scaffold tests**

Run: `swift test --filter IrockToolingTests`

Expected: PASS.

- [x] **Step 2: Run full SwiftPM suite**

Run: `swift test`

Expected: PASS.

- [x] **Step 3: Run unsigned iOS simulator build**

Run: `xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

- [x] **Step 4: Run platform import boundary scan**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
package_forbidden = {'Network', 'NetworkExtension', 'UIKit', 'AppKit', 'Security'}
app_forbidden = {'Network', 'UIKit', 'AppKit', 'Security'}
violations = []
for path in Path('packages').rglob('*.swift'):
    for line_no, line in enumerate(path.read_text().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith('import '):
            module = stripped.split()[1]
            if module in package_forbidden:
                violations.append(f'{path}:{line_no}: {stripped}')
for path in Path('apps/irock-iOS/irockApp').rglob('*.swift'):
    for line_no, line in enumerate(path.read_text().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith('import '):
            module = stripped.split()[1]
            if module in app_forbidden:
                violations.append(f'{path}:{line_no}: {stripped}')
if violations:
    print('\n'.join(violations))
    raise SystemExit(1)
print('Platform imports remain inside allowed targets')
PY
```

Expected: `Platform imports remain inside allowed targets`.

- [x] **Step 5: Update this plan with execution status**

Mark completed checkboxes in this file after each step passes.
