# M33 Runtime Snapshot to Real Provider Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Connect the iOS app's runtime snapshot publisher to the Packet Tunnel provider's App Group-backed startup store.

**Architecture:** Add an iOS app-local App Group store resolver that mirrors the extension resolver and produces the same `RuntimeStoreBundle` rooted under `group.dev.irock.shared`. Keep shared app state in `IrockAppFeature.AppViewModel`; the iOS shell only chooses file-backed App Group stores or an in-memory fallback for unsigned builds. Static scaffold tests verify the app and provider share the same storage boundary without requiring real provisioning.

**Tech Stack:** Swift 5.10, SwiftUI, Foundation App Groups, IrockStorage, IrockAppFeature, XCTest, Xcode project scaffold.

---

## Files

- Create: `apps/irock-iOS/irockApp/IOSAppGroupRuntimeStoreResolver.swift`
  - Resolves the app-side App Group container and creates `RuntimeStoreBundle`.
- Modify: `apps/irock-iOS/irockApp/ContentView.swift`
  - Builds `AppViewModel` with App Group-backed runtime stores when available, otherwise in-memory fallback.
- Modify: `apps/irock-iOS/irock.xcodeproj/project.pbxproj`
  - Adds the resolver file to the iOS app group and app target sources.
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Adds static tests for app/provider App Group store boundary and ContentView injection.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m33-runtime-snapshot-to-real-provider-flow-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m33-runtime-snapshot-to-real-provider-flow.md`

## Task 1: App-side App Group runtime store resolver

- [x] **Step 1: Write the failing static test**

Add this test to `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` after `testContainerAppDeclaresVPNManagerBoundary`:

```swift
func testContainerAppDeclaresAppGroupRuntimeStoreResolver() throws {
    let resolver = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/IOSAppGroupRuntimeStoreResolver.swift"))
    let extensionResolver = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockTunnelExtension/PacketTunnelAppGroupStoreResolver.swift"))
    let project = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irock.xcodeproj/project.pbxproj"))

    XCTAssertTrue(resolver.contains("struct IOSAppGroupRuntimeStoreResolver"))
    XCTAssertTrue(resolver.contains("group.dev.irock.shared"))
    XCTAssertTrue(resolver.contains("containerURL(forSecurityApplicationGroupIdentifier:"))
    XCTAssertTrue(resolver.contains("AppGroupRuntimeStoreDirectory"))
    XCTAssertTrue(resolver.contains("makeRuntimeStoreBundle"))
    XCTAssertTrue(extensionResolver.contains("group.dev.irock.shared"))
    XCTAssertTrue(extensionResolver.contains("AppGroupRuntimeStoreDirectory"))
    XCTAssertTrue(project.contains("IOSAppGroupRuntimeStoreResolver.swift in Sources"))
}
```

Also update `requiredScaffoldPaths` to include:

```swift
"apps/irock-iOS/irockApp/IOSAppGroupRuntimeStoreResolver.swift",
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter XcodeScaffoldTests/testContainerAppDeclaresAppGroupRuntimeStoreResolver`

Expected: FAIL because `IOSAppGroupRuntimeStoreResolver.swift` does not exist.

- [x] **Step 3: Add app-side resolver file**

Create `apps/irock-iOS/irockApp/IOSAppGroupRuntimeStoreResolver.swift`:

```swift
import Foundation
import IrockStorage

struct IOSAppGroupRuntimeStoreResolver: Sendable {
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

- [x] **Step 4: Add resolver to Xcode project**

Modify `apps/irock-iOS/irock.xcodeproj/project.pbxproj`:

Add a build file entry near other app source build files:

```text
		IROCKAPPSTORERESBUILD01 /* IOSAppGroupRuntimeStoreResolver.swift in Sources */ = {isa = PBXBuildFile; fileRef = IROCKAPPSTORERESFILEREF1 /* IOSAppGroupRuntimeStoreResolver.swift */;};
```

Add the app group child after `IOSVPNManager.swift`:

```text
				IROCKAPPSTORERESFILEREF1 /* IOSAppGroupRuntimeStoreResolver.swift */,
```

Add the file reference after `IOSVPNManager.swift`:

```text
		IROCKAPPSTORERESFILEREF1 /* IOSAppGroupRuntimeStoreResolver.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSAppGroupRuntimeStoreResolver.swift; sourceTree = "<group>";};
```

Update the app sources phase to include:

```text
IROCKAPPSTORERESBUILD01 /* IOSAppGroupRuntimeStoreResolver.swift in Sources */
```

- [x] **Step 5: Run test to verify it passes**

Run: `swift test --filter XcodeScaffoldTests/testContainerAppDeclaresAppGroupRuntimeStoreResolver`

Expected: PASS.

## Task 2: ContentView injects App Group runtime stores

- [x] **Step 1: Write the failing static test**

Add this test to `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` after `testContainerAppHostsSharedRootView`:

```swift
func testContentViewInjectsAppGroupRuntimeStoresWithFallback() throws {
    let contentView = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irockApp/ContentView.swift"))

    XCTAssertTrue(contentView.contains("IOSAppGroupRuntimeStoreResolver"))
    XCTAssertTrue(contentView.contains("makeRuntimeStoreBundle"))
    XCTAssertTrue(contentView.contains("runtimeSnapshotStore: stores.snapshotStore"))
    XCTAssertTrue(contentView.contains("runtimeStatusStore: stores.statusStore"))
    XCTAssertTrue(contentView.contains("runtimeLogStore: stores.logStore"))
    XCTAssertTrue(contentView.contains("AppViewModel(nodes: [])"))
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter XcodeScaffoldTests/testContentViewInjectsAppGroupRuntimeStoresWithFallback`

Expected: FAIL because `ContentView` does not resolve App Group stores.

- [x] **Step 3: Update ContentView**

Replace `apps/irock-iOS/irockApp/ContentView.swift` with:

```swift
import IrockAppFeature
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = Self.makeViewModel()

    var body: some View {
        IrockRootView(viewModel: viewModel)
    }

    private static func makeViewModel() -> AppViewModel {
        do {
            let stores = try IOSAppGroupRuntimeStoreResolver().makeRuntimeStoreBundle()
            return AppViewModel(
                nodes: [],
                runtimeSnapshotStore: stores.snapshotStore,
                runtimeStatusStore: stores.statusStore,
                runtimeLogStore: stores.logStore
            )
        } catch {
            return AppViewModel(nodes: [])
        }
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter XcodeScaffoldTests/testContentViewInjectsAppGroupRuntimeStoresWithFallback`

Expected: PASS.

## Task 3: Provider startup flow evidence

- [x] **Step 1: Strengthen static provider-flow test**

Update `testPacketTunnelSmokePathFilesDeclareExpectedBoundaries` in `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` to also assert:

```swift
XCTAssertTrue(smokeRunner.contains("stores.snapshotStore"))
XCTAssertTrue(smokeRunner.contains("stores.statusStore"))
XCTAssertTrue(smokeRunner.contains("stores.logStore"))
XCTAssertTrue(smokeRunner.contains("validateStartup"))
XCTAssertTrue(smokeRunner.contains("missingRuntimeSnapshot"))
```

- [x] **Step 2: Run test to verify it passes**

Run: `swift test --filter XcodeScaffoldTests/testPacketTunnelSmokePathFilesDeclareExpectedBoundaries`

Expected: PASS because provider already reads snapshot/status/log stores through the App Group resolver.

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
