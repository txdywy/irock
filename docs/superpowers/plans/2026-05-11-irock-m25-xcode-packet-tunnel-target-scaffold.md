# M25 Xcode Packet Tunnel Target Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reviewable iOS Xcode app + Packet Tunnel extension scaffold with static validation and no real signing assumptions.

**Architecture:** Keep reusable logic in SwiftPM packages and add platform-only files under `apps/irock-iOS`. Validate scaffold shape through SwiftPM XCTest so this milestone does not depend on local Apple Developer Team, provisioning, or `xcodebuild` signing.

**Tech Stack:** SwiftPM, XCTest, Foundation `PropertyListSerialization`, Xcode project text scaffold, SwiftUI app shell, NetworkExtension provider shell, plist and entitlements templates.

---

## File Structure

- Create: `packages/IrockTooling/Sources/IrockTooling/IrockTooling.swift`
  - Empty marker target for repository-level static validation tests.
- Create: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - XCTest validation for Xcode scaffold files, plists, entitlements, and import boundaries.
- Modify: `Package.swift`
  - Add `IrockTooling` target and `IrockToolingTests` test target.
- Create: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
  - Reviewable two-target Xcode project scaffold.
- Create: `apps/irock-iOS/irockApp/IrockApp.swift`
- Create: `apps/irock-iOS/irockApp/ContentView.swift`
- Create: `apps/irock-iOS/irockApp/Info.plist`
- Create: `apps/irock-iOS/irockApp/irockApp.entitlements`
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`
- Create: `apps/irock-iOS/irockTunnelExtension/Info.plist`
- Create: `apps/irock-iOS/irockTunnelExtension/irockTunnelExtension.entitlements`

---

### Task 1: Static Validation Test Harness

**Files:**
- Modify: `Package.swift`
- Create: `packages/IrockTooling/Sources/IrockTooling/IrockTooling.swift`
- Create: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [ ] **Step 1: Add failing static validation tests**

Create `packages/IrockTooling/Sources/IrockTooling/IrockTooling.swift`:

```swift
public enum IrockTooling {}
```

Create `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`:

```swift
import XCTest

final class XcodeScaffoldTests: XCTestCase {
    func testRequiredIOSScaffoldFilesExist() throws {
        for path in requiredScaffoldPaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path), "Missing \(path)")
        }
    }

    func testExtensionInfoPlistDeclaresPacketTunnelExtensionPoint() throws {
        let plist = try loadPlist("apps/irock-iOS/irockTunnelExtension/Info.plist")
        let extensionDictionary = try XCTUnwrap(plist["NSExtension"] as? [String: Any])

        XCTAssertEqual(extensionDictionary["NSExtensionPointIdentifier"] as? String, "com.apple.networkextension.packet-tunnel")
        XCTAssertEqual(extensionDictionary["NSExtensionPrincipalClass"] as? String, "$(PRODUCT_MODULE_NAME).PacketTunnelProvider")
    }

    func testEntitlementTemplatesDeclareSharedAppGroupAndPacketTunnelCapability() throws {
        let appEntitlements = try loadPlist("apps/irock-iOS/irockApp/irockApp.entitlements")
        let extensionEntitlements = try loadPlist("apps/irock-iOS/irockTunnelExtension/irockTunnelExtension.entitlements")

        XCTAssertEqual(appEntitlements["com.apple.security.application-groups"] as? [String], ["group.dev.irock.shared"])
        XCTAssertEqual(extensionEntitlements["com.apple.security.application-groups"] as? [String], ["group.dev.irock.shared"])
        XCTAssertEqual(extensionEntitlements["com.apple.developer.networking.networkextension"] as? [String], ["packet-tunnel-provider"])
    }

    func testPlatformImportsStayOutOfSharedPackages() throws {
        let forbiddenImports = ["import NetworkExtension", "import Network", "import Security", "import UIKit", "import AppKit", "import SwiftUI"]
        let packageFiles = try swiftFiles(under: repositoryRoot.appendingPathComponent("packages"))

        for file in packageFiles {
            let contents = try String(contentsOf: file)
            for forbiddenImport in forbiddenImports {
                XCTAssertFalse(contents.contains(forbiddenImport), "\(forbiddenImport) leaked into \(file.path)")
            }
        }
    }

    func testPlatformImportsExistOnlyInIOSScaffold() throws {
        let provider = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift"))
        let app = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/IrockApp.swift"))
        let contentView = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/ContentView.swift"))

        XCTAssertTrue(provider.contains("import NetworkExtension"))
        XCTAssertTrue(app.contains("import SwiftUI"))
        XCTAssertTrue(contentView.contains("import SwiftUI"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var requiredScaffoldPaths: [String] {
        [
            "apps/irock-iOS/irock.xcodeproj/project.pbxproj",
            "apps/irock-iOS/irockApp/IrockApp.swift",
            "apps/irock-iOS/irockApp/ContentView.swift",
            "apps/irock-iOS/irockApp/Info.plist",
            "apps/irock-iOS/irockApp/irockApp.entitlements",
            "apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift",
            "apps/irock-iOS/irockTunnelExtension/Info.plist",
            "apps/irock-iOS/irockTunnelExtension/irockTunnelExtension.entitlements"
        ]
    }

    private func loadPlist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }
}
```

Modify `Package.swift` by adding product and targets:

```swift
.library(name: "IrockTooling", targets: ["IrockTooling"])
```

```swift
.target(
    name: "IrockTooling",
    path: "packages/IrockTooling/Sources/IrockTooling"
),
.testTarget(
    name: "IrockToolingTests",
    dependencies: ["IrockTooling"],
    path: "packages/IrockTooling/Tests/IrockToolingTests"
)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: tests compile but fail because required scaffold files are missing.

- [ ] **Step 3: Commit static validation harness**

```bash
git add Package.swift packages/IrockTooling
git commit -m "test: add xcode scaffold validation harness"
```

---

### Task 2: iOS App and Packet Tunnel Scaffold Files

**Files:**
- Create: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
- Create: `apps/irock-iOS/irockApp/IrockApp.swift`
- Create: `apps/irock-iOS/irockApp/ContentView.swift`
- Create: `apps/irock-iOS/irockApp/Info.plist`
- Create: `apps/irock-iOS/irockApp/irockApp.entitlements`
- Create: `apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift`
- Create: `apps/irock-iOS/irockTunnelExtension/Info.plist`
- Create: `apps/irock-iOS/irockTunnelExtension/irockTunnelExtension.entitlements`

- [ ] **Step 1: Add scaffold files**

Create the app Swift files:

```swift
import SwiftUI

@main
struct IrockApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("irock")
            .padding()
    }
}
```

Create `PacketTunnelProvider.swift`:

```swift
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String: NSObject]?) async throws {
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
    }
}
```

Create plist and entitlements files matching the design. Create `project.pbxproj` as a minimal text scaffold containing `irockApp`, `irockTunnelExtension`, package product names, bundle identifiers, and placeholder signing settings.

- [ ] **Step 2: Run scaffold validation**

Run:

```bash
swift test --filter XcodeScaffoldTests
```

Expected: all scaffold tests pass.

- [ ] **Step 3: Commit scaffold files**

```bash
git add apps/irock-iOS
git commit -m "feat: add iOS packet tunnel xcode scaffold"
```

---

### Task 3: Full Verification and Review Prep

**Files:**
- Modify plan only if self-check finds typos.

- [ ] **Step 1: Run full tests**

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Run forbidden shared package import scan**

```bash
grep -R "import NetworkExtension\|import Network\|import Security\|import UIKit\|import AppKit\|import SwiftUI" -n packages Package.swift || true
```

Expected: no output.

- [ ] **Step 3: Run allowed platform import scans**

```bash
grep -R "import NetworkExtension" -n apps/irock-iOS/irockTunnelExtension
grep -R "import SwiftUI" -n apps/irock-iOS/irockApp
grep -R "group.dev.irock.shared" -n apps/irock-iOS
```

Expected: NetworkExtension appears in `PacketTunnelProvider.swift`; SwiftUI appears in app Swift files; App Group placeholder appears in both entitlements.

- [ ] **Step 4: Scan plan for placeholders and command typos**

```bash
grep -nE '[T]BD|[T]ODO|[i]mplement later|[f]ill in|n[g]it|n[g]rep' docs/superpowers/plans/2026-05-11-irock-m25-xcode-packet-tunnel-target-scaffold.md || true
```

Expected: no output.

- [ ] **Step 5: Commit plan if not already committed**

```bash
git add docs/superpowers/plans/2026-05-11-irock-m25-xcode-packet-tunnel-target-scaffold.md
git commit -m "docs: add M25 Xcode packet tunnel target scaffold plan"
```

- [ ] **Step 6: Prepare branch for PR**

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean worktree and M25 design, plan, test harness, and scaffold commits.
