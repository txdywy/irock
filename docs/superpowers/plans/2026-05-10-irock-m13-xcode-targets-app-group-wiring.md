# irock M13 Xcode Targets + App Group Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create real iOS/macOS Xcode app and Packet Tunnel target skeletons with App Group runtime snapshot wiring while keeping shared business logic in SwiftPM packages.

**Architecture:** M13 uses XcodeGen as the source-of-truth for Xcode projects and commits both `project.yml` specs and generated `.xcodeproj`/`.xcworkspace` artifacts. Thin platform app targets import `IrockAppFeature`; thin Packet Tunnel targets import `IrockStorage` and `IrockTunnelCore`, resolve the shared App Group snapshot path, load `RuntimeSnapshot`, and construct `TunnelRuntimeConfiguration` without starting real packet forwarding.

**Tech Stack:** Swift 5.10+, SwiftUI, NetworkExtension, Xcode 26+, XcodeGen, Swift Package Manager, XCTest.

---

## File Structure

M13 creates and modifies these files:

```text
irock.xcworkspace/contents.xcworkspacedata
apps/Shared/IrockPlatformSupport/AppGroupRuntimeSnapshotLocation.swift
apps/Shared/IrockPlatformSupport/PlatformRuntimeSnapshotLoader.swift
apps/irock-iOS/project.yml
apps/irock-iOS/irock-iOS.xcodeproj/
apps/irock-iOS/Sources/irockApp/IrockIOSApp.swift
apps/irock-iOS/Sources/irockTunnelExtension/PacketTunnelProvider.swift
apps/irock-iOS/Sources/irockTunnelExtension/Info.plist
apps/irock-iOS/Entitlements/irockApp.entitlements
apps/irock-iOS/Entitlements/irockTunnelExtension.entitlements
apps/irock-macOS/project.yml
apps/irock-macOS/irock-macOS.xcodeproj/
apps/irock-macOS/Sources/irockMacApp/IrockMacApp.swift
apps/irock-macOS/Sources/irockMacTunnelExtension/PacketTunnelProvider.swift
apps/irock-macOS/Sources/irockMacTunnelExtension/Info.plist
apps/irock-macOS/Entitlements/irockMacApp.entitlements
apps/irock-macOS/Entitlements/irockMacTunnelExtension.entitlements
README.md
CLAUDE.md
apps/XCODE_TARGETS.md
docs/superpowers/plans/2026-05-10-irock-m13-xcode-targets-app-group-wiring.md
```

Responsibilities:

- `AppGroupRuntimeSnapshotLocation.swift`: resolves the shared App Group runtime snapshot file URL.
- `PlatformRuntimeSnapshotLoader.swift`: loads a `RuntimeSnapshot` from the App Group location and builds `TunnelRuntimeConfiguration`.
- `IrockIOSApp.swift` / `IrockMacApp.swift`: platform SwiftUI app entry points that mount `IrockAppFeature.IrockRootView`.
- `PacketTunnelProvider.swift`: minimal NetworkExtension provider that loads runtime configuration on start and does no packet forwarding yet.
- `project.yml`: XcodeGen target, package dependency, entitlement, and scheme configuration.
- `Info.plist`: extension metadata for Packet Tunnel providers.
- Entitlements files: project-level placeholders for App Groups, Keychain Sharing, and Network Extension capabilities.
- README/CLAUDE/XCODE_TARGETS docs: reflect that Xcode skeleton exists and signing remains local.

---

## Task 1: Add shared App Group snapshot loader source

**Files:**
- Create: `apps/Shared/IrockPlatformSupport/AppGroupRuntimeSnapshotLocation.swift`
- Create: `apps/Shared/IrockPlatformSupport/PlatformRuntimeSnapshotLoader.swift`

- [ ] **Step 1: Create the App Group snapshot location helper**

Create `apps/Shared/IrockPlatformSupport/AppGroupRuntimeSnapshotLocation.swift` with:

```swift
import Foundation

public enum AppGroupRuntimeSnapshotLocationError: Error, LocalizedError, Sendable {
    case appGroupContainerUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .appGroupContainerUnavailable(identifier):
            return "App Group container is unavailable for \(identifier)"
        }
    }
}

public enum AppGroupRuntimeSnapshotLocation {
    public static let appGroupID = "group.com.irock.shared"
    public static let snapshotFileName = "runtime-snapshot.json"

    public static func snapshotURL(fileManager: FileManager = .default) throws -> URL {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw AppGroupRuntimeSnapshotLocationError.appGroupContainerUnavailable(appGroupID)
        }
        return containerURL.appendingPathComponent(snapshotFileName, isDirectory: false)
    }

    public static func snapshotDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try snapshotURL(fileManager: fileManager).deletingLastPathComponent()
    }
}
```

- [ ] **Step 2: Create the platform runtime snapshot loader**

Create `apps/Shared/IrockPlatformSupport/PlatformRuntimeSnapshotLoader.swift` with:

```swift
import Foundation
import IrockCore
import IrockStorage
import IrockTunnelCore

public enum PlatformRuntimeSnapshotLoader {
    public static func loadSnapshot(fileManager: FileManager = .default) throws -> RuntimeSnapshot? {
        let directoryURL = try AppGroupRuntimeSnapshotLocation.snapshotDirectoryURL(fileManager: fileManager)
        return try FileRuntimeSnapshotStore(directoryURL: directoryURL, fileManager: fileManager).load()
    }

    public static func loadConfiguration(fileManager: FileManager = .default) throws -> TunnelRuntimeConfiguration? {
        guard let snapshot = try loadSnapshot(fileManager: fileManager) else {
            return nil
        }
        return try TunnelRuntimeConfiguration(snapshot: snapshot)
    }
}
```

- [ ] **Step 3: Commit shared platform support sources**

Run:

```bash
git add apps/Shared/IrockPlatformSupport/AppGroupRuntimeSnapshotLocation.swift apps/Shared/IrockPlatformSupport/PlatformRuntimeSnapshotLoader.swift
git commit -m "$(cat <<'EOF'
feat: add App Group runtime snapshot helpers

Provide platform-level helpers for app and tunnel targets to resolve and load the shared runtime snapshot from the App Group container.
EOF
)"
```

---

## Task 2: Add thin platform app and tunnel source files

**Files:**
- Create: `apps/irock-iOS/Sources/irockApp/IrockIOSApp.swift`
- Create: `apps/irock-iOS/Sources/irockTunnelExtension/PacketTunnelProvider.swift`
- Create: `apps/irock-iOS/Sources/irockTunnelExtension/Info.plist`
- Create: `apps/irock-macOS/Sources/irockMacApp/IrockMacApp.swift`
- Create: `apps/irock-macOS/Sources/irockMacTunnelExtension/PacketTunnelProvider.swift`
- Create: `apps/irock-macOS/Sources/irockMacTunnelExtension/Info.plist`

- [ ] **Step 1: Create the iOS SwiftUI app entry point**

Create `apps/irock-iOS/Sources/irockApp/IrockIOSApp.swift` with:

```swift
import SwiftUI
import IrockAppFeature

@main
struct IrockIOSApp: App {
    var body: some Scene {
        WindowGroup {
            IrockRootView(viewModel: AppViewModel(nodes: []))
        }
    }
}
```

- [ ] **Step 2: Create the macOS SwiftUI app entry point**

Create `apps/irock-macOS/Sources/irockMacApp/IrockMacApp.swift` with:

```swift
import SwiftUI
import IrockAppFeature

@main
struct IrockMacApp: App {
    var body: some Scene {
        WindowGroup {
            IrockRootView(viewModel: AppViewModel(nodes: []))
        }
    }
}
```

- [ ] **Step 3: Create the iOS Packet Tunnel provider**

Create `apps/irock-iOS/Sources/irockTunnelExtension/PacketTunnelProvider.swift` with:

```swift
import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var loadedConfigurationDescription: String?

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        do {
            if let configuration = try PlatformRuntimeSnapshotLoader.loadConfiguration() {
                loadedConfigurationDescription = "Loaded route mode: \(configuration.routeMode.rawValue)"
            } else {
                loadedConfigurationDescription = "No runtime snapshot available"
            }
        } catch {
            throw NSError(
                domain: "com.irock.tunnel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(describing: error)]
            )
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        loadedConfigurationDescription = nil
    }
}
```

- [ ] **Step 4: Create the macOS Packet Tunnel provider**

Create `apps/irock-macOS/Sources/irockMacTunnelExtension/PacketTunnelProvider.swift` with:

```swift
import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var loadedConfigurationDescription: String?

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        do {
            if let configuration = try PlatformRuntimeSnapshotLoader.loadConfiguration() {
                loadedConfigurationDescription = "Loaded route mode: \(configuration.routeMode.rawValue)"
            } else {
                loadedConfigurationDescription = "No runtime snapshot available"
            }
        } catch {
            throw NSError(
                domain: "com.irock.tunnel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(describing: error)]
            )
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        loadedConfigurationDescription = nil
    }
}
```

- [ ] **Step 5: Create the iOS tunnel extension Info.plist**

Create `apps/irock-iOS/Sources/irockTunnelExtension/Info.plist` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.networkextension.packet-tunnel</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 6: Create the macOS tunnel extension Info.plist**

Create `apps/irock-macOS/Sources/irockMacTunnelExtension/Info.plist` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.networkextension.packet-tunnel</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 7: Commit platform app and tunnel source skeletons**

Run:

```bash
git add apps/irock-iOS/Sources/irockApp/IrockIOSApp.swift apps/irock-iOS/Sources/irockTunnelExtension/PacketTunnelProvider.swift apps/irock-iOS/Sources/irockTunnelExtension/Info.plist apps/irock-macOS/Sources/irockMacApp/IrockMacApp.swift apps/irock-macOS/Sources/irockMacTunnelExtension/PacketTunnelProvider.swift apps/irock-macOS/Sources/irockMacTunnelExtension/Info.plist
git commit -m "$(cat <<'EOF'
feat: add thin app and tunnel target sources

Create SwiftUI app entries and minimal Packet Tunnel providers that load App Group runtime configuration without forwarding packets yet.
EOF
)"
```

---

## Task 3: Add entitlements placeholders

**Files:**
- Create: `apps/irock-iOS/Entitlements/irockApp.entitlements`
- Create: `apps/irock-iOS/Entitlements/irockTunnelExtension.entitlements`
- Create: `apps/irock-macOS/Entitlements/irockMacApp.entitlements`
- Create: `apps/irock-macOS/Entitlements/irockMacTunnelExtension.entitlements`

- [ ] **Step 1: Create the iOS app entitlements file**

Create `apps/irock-iOS/Entitlements/irockApp.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.irock.shared</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.irock.shared</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Create the iOS tunnel entitlements file**

Create `apps/irock-iOS/Entitlements/irockTunnelExtension.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.irock.shared</string>
    </array>
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>packet-tunnel-provider</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.irock.shared</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Create the macOS app entitlements file**

Create `apps/irock-macOS/Entitlements/irockMacApp.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.irock.shared</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.irock.shared</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 4: Create the macOS tunnel entitlements file**

Create `apps/irock-macOS/Entitlements/irockMacTunnelExtension.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.irock.shared</string>
    </array>
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>packet-tunnel-provider</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.irock.shared</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 5: Commit entitlements placeholders**

Run:

```bash
git add apps/irock-iOS/Entitlements/irockApp.entitlements apps/irock-iOS/Entitlements/irockTunnelExtension.entitlements apps/irock-macOS/Entitlements/irockMacApp.entitlements apps/irock-macOS/Entitlements/irockMacTunnelExtension.entitlements
git commit -m "$(cat <<'EOF'
feat: add platform entitlement placeholders

Declare shared App Group, Keychain Sharing, and Packet Tunnel entitlement placeholders without committing private signing material.
EOF
)"
```

---

## Task 4: Add XcodeGen project specs

**Files:**
- Create: `apps/irock-iOS/project.yml`
- Create: `apps/irock-macOS/project.yml`

- [ ] **Step 1: Ensure XcodeGen is available**

Run:

```bash
command -v xcodegen || brew install xcodegen
xcodegen --version
```

Expected: prints an XcodeGen version. If Homebrew is unavailable, install XcodeGen manually and rerun `xcodegen --version` before continuing.

- [ ] **Step 2: Create the iOS XcodeGen project spec**

Create `apps/irock-iOS/project.yml` with:

```yaml
name: irock-iOS
options:
  minimumXcodeGenVersion: 2.42.0
  deploymentTarget:
    iOS: "17.0"
packages:
  irock:
    path: ../..
targets:
  irockApp:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: Sources/irockApp
      - path: ../Shared/IrockPlatformSupport
    dependencies:
      - package: irock
        product: IrockAppFeature
      - target: irockTunnelExtension
        embed: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.irock.app.ios
        PRODUCT_NAME: irock
        INFOPLIST_KEY_CFBundleDisplayName: irock
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_ENTITLEMENTS: Entitlements/irockApp.entitlements
  irockTunnelExtension:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: Sources/irockTunnelExtension
      - path: ../Shared/IrockPlatformSupport
    dependencies:
      - package: irock
        product: IrockCore
      - package: irock
        product: IrockStorage
      - package: irock
        product: IrockTunnelCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.irock.app.ios.tunnel
        PRODUCT_NAME: irockTunnelExtension
        INFOPLIST_FILE: Sources/irockTunnelExtension/Info.plist
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_ENTITLEMENTS: Entitlements/irockTunnelExtension.entitlements
schemes:
  irockApp:
    build:
      targets:
        irockApp: all
        irockTunnelExtension: all
    run:
      config: Debug
    test:
      config: Debug
    archive:
      config: Release
  irockTunnelExtension:
    build:
      targets:
        irockTunnelExtension: all
```

- [ ] **Step 3: Create the macOS XcodeGen project spec**

Create `apps/irock-macOS/project.yml` with:

```yaml
name: irock-macOS
options:
  minimumXcodeGenVersion: 2.42.0
  deploymentTarget:
    macOS: "14.0"
packages:
  irock:
    path: ../..
targets:
  irockMacApp:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: Sources/irockMacApp
      - path: ../Shared/IrockPlatformSupport
    dependencies:
      - package: irock
        product: IrockAppFeature
      - target: irockMacTunnelExtension
        embed: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.irock.app.macos
        PRODUCT_NAME: irock
        INFOPLIST_KEY_CFBundleDisplayName: irock
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_ENTITLEMENTS: Entitlements/irockMacApp.entitlements
        ENABLE_HARDENED_RUNTIME: YES
  irockMacTunnelExtension:
    type: app-extension
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: Sources/irockMacTunnelExtension
      - path: ../Shared/IrockPlatformSupport
    dependencies:
      - package: irock
        product: IrockCore
      - package: irock
        product: IrockStorage
      - package: irock
        product: IrockTunnelCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.irock.app.macos.tunnel
        PRODUCT_NAME: irockMacTunnelExtension
        INFOPLIST_FILE: Sources/irockMacTunnelExtension/Info.plist
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_ENTITLEMENTS: Entitlements/irockMacTunnelExtension.entitlements
        ENABLE_HARDENED_RUNTIME: YES
schemes:
  irockMacApp:
    build:
      targets:
        irockMacApp: all
        irockMacTunnelExtension: all
    run:
      config: Debug
    test:
      config: Debug
    archive:
      config: Release
  irockMacTunnelExtension:
    build:
      targets:
        irockMacTunnelExtension: all
```

- [ ] **Step 4: Generate projects with XcodeGen**

Run:

```bash
xcodegen generate --spec apps/irock-iOS/project.yml
xcodegen generate --spec apps/irock-macOS/project.yml
```

Expected: creates `apps/irock-iOS/irock-iOS.xcodeproj` and `apps/irock-macOS/irock-macOS.xcodeproj` without YAML parsing errors.

- [ ] **Step 5: Commit XcodeGen specs and generated projects**

Run:

```bash
git add apps/irock-iOS/project.yml apps/irock-iOS/irock-iOS.xcodeproj apps/irock-macOS/project.yml apps/irock-macOS/irock-macOS.xcodeproj
git commit -m "$(cat <<'EOF'
feat: add XcodeGen platform projects

Define and generate iOS and macOS app plus Packet Tunnel extension projects from XcodeGen specs.
EOF
)"
```

---

## Task 5: Add root workspace

**Files:**
- Create: `irock.xcworkspace/contents.xcworkspacedata`

- [ ] **Step 1: Create root workspace metadata**

Create `irock.xcworkspace/contents.xcworkspacedata` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:Package.swift">
   </FileRef>
   <FileRef
      location = "group:apps/irock-iOS/irock-iOS.xcodeproj">
   </FileRef>
   <FileRef
      location = "group:apps/irock-macOS/irock-macOS.xcodeproj">
   </FileRef>
</Workspace>
```

- [ ] **Step 2: Verify workspace schemes are discoverable**

Run:

```bash
xcodebuild -list -workspace irock.xcworkspace
```

Expected: output lists `irockApp`, `irockTunnelExtension`, `irockMacApp`, and `irockMacTunnelExtension` schemes. If Xcode reports package resolution or workspace parsing errors, fix the workspace/project paths before continuing.

- [ ] **Step 3: Commit root workspace**

Run:

```bash
git add irock.xcworkspace/contents.xcworkspacedata
git commit -m "$(cat <<'EOF'
feat: add root Xcode workspace

Collect the Swift package and generated platform projects in a single workspace for app and tunnel development.
EOF
)"
```

---

## Task 6: Verify Xcode builds and document signing outcomes

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `apps/XCODE_TARGETS.md`

- [ ] **Step 1: Run SwiftPM tests**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

- [ ] **Step 2: Run iOS generic build**

Run:

```bash
xcodebuild -workspace irock.xcworkspace -scheme irockApp -destination 'generic/platform=iOS' build
```

Expected: either PASS, or FAIL only at signing/provisioning/capability selection. If it fails due to source compile errors, package dependency errors, missing files, or scheme resolution, fix those before continuing.

- [ ] **Step 3: Run macOS generic build**

Run:

```bash
xcodebuild -workspace irock.xcworkspace -scheme irockMacApp -destination 'generic/platform=macOS' build
```

Expected: either PASS, or FAIL only at signing/provisioning/capability selection. If it fails due to source compile errors, package dependency errors, missing files, or scheme resolution, fix those before continuing.

- [ ] **Step 4: Update README current phase and Xcode section**

Replace `README.md` current phase paragraph with:

```markdown
## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, M2 TUN data path core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, M6 local routing rule parsing foundation, M7 runtime rule manifest foundation, M8 runtime rule adapter foundation, M9 app routing rule manifest foundation, and M13 Xcode target/App Group wiring skeleton:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing rule manifests, runtime rule adapters, routing/storage behavior, file-backed snapshot persistence, app feature state, runtime snapshot publishing, Shadowsocks URI import, local routing rule parsing, packet parsing, flow tracking, and tunnel runtime processing
- XcodeGen-backed iOS/macOS app and Packet Tunnel target skeletons with App Group runtime snapshot path wiring; local signing and Developer Team configuration are still required before device VPN execution
```

Replace the implementation plan list in `README.md` with:

```markdown
## Implementation plans

- M0: `docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md`
- M1: `docs/superpowers/plans/2026-05-10-irock-m1-ui-configuration.md`
- M2: `docs/superpowers/plans/2026-05-10-irock-m2-tun-data-path.md`
- M3: `docs/superpowers/plans/2026-05-10-irock-m3-runtime-snapshot-persistence.md`
- M4: `docs/superpowers/plans/2026-05-10-irock-m4-runtime-snapshot-publishing.md`
- M5: `docs/superpowers/plans/2026-05-10-irock-m5-shadowsocks-uri-import.md`
- M6: `docs/superpowers/plans/2026-05-10-irock-m6-local-routing-rules.md`
- M7: `docs/superpowers/plans/2026-05-10-irock-m7-runtime-rule-manifest.md`
- M8: `docs/superpowers/plans/2026-05-10-irock-m8-runtime-rule-adapter.md`
- M9: `docs/superpowers/plans/2026-05-10-irock-m9-app-routing-rule-manifest.md`
- M13: `docs/superpowers/plans/2026-05-10-irock-m13-xcode-targets-app-group-wiring.md`
```

Replace the Xcode targets section in `README.md` with:

```markdown
## Xcode targets

The repository includes XcodeGen-backed iOS/macOS app and Packet Tunnel target skeletons. See `apps/XCODE_TARGETS.md` for target layout, regeneration commands, signing notes, and App Group requirements.
```

- [ ] **Step 5: Update CLAUDE.md project status and commands**

Replace the `CLAUDE.md` project status paragraph with:

```markdown
## Project status

irock has a SwiftPM package graph, M1 app feature configuration scaffolding, M2 tunnel core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, M6 local routing rule parsing foundation, M7 runtime rule manifest foundation, M8 runtime rule adapter foundation, M9 app routing rule manifest foundation, and M13 Xcode target/App Group wiring skeleton in the working tree. The committed product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Implementation plans live under `docs/superpowers/plans/`, including M0 engineering foundation through M9 app routing rule manifest plus M13 Xcode target/App Group wiring.

Xcode workspace, app targets, and Packet Tunnel targets now exist as XcodeGen-backed skeletons. Do not assume device VPN execution works until a local Apple Developer Team, App Groups, Keychain Sharing, and Network Extension signing are configured.
```

Replace the `After Xcode targets exist...` command note with:

```markdown
Xcode commands:

- List workspace schemes: `xcodebuild -list -workspace irock.xcworkspace`
- Build iOS app skeleton: `xcodebuild -workspace irock.xcworkspace -scheme irockApp -destination 'generic/platform=iOS' build`
- Build macOS app skeleton: `xcodebuild -workspace irock.xcworkspace -scheme irockMacApp -destination 'generic/platform=macOS' build`

Signing-related failures may require local Developer Team and entitlement configuration; source/package/scheme failures should be fixed in the repo.
```

- [ ] **Step 6: Replace apps/XCODE_TARGETS.md with current target guidance**

Replace `apps/XCODE_TARGETS.md` with:

```markdown
# Xcode Targets

The repository now contains XcodeGen-backed iOS/macOS app and Packet Tunnel target skeletons.

## Regenerating projects

Install XcodeGen if needed:

```bash
brew install xcodegen
```

Regenerate projects:

```bash
xcodegen generate --spec apps/irock-iOS/project.yml
xcodegen generate --spec apps/irock-macOS/project.yml
```

Open the workspace:

```bash
open irock.xcworkspace
```

## Workspace

`irock.xcworkspace` includes:

- Root Swift package: `Package.swift`
- iOS project: `apps/irock-iOS/irock-iOS.xcodeproj`
- macOS project: `apps/irock-macOS/irock-macOS.xcodeproj`

## iOS targets

`apps/irock-iOS/irock-iOS.xcodeproj` contains:

- `irockApp`: SwiftUI app shell importing `IrockAppFeature`
- `irockTunnelExtension`: Packet Tunnel Provider shell importing runtime snapshot and tunnel configuration packages

Bundle IDs:

- App: `com.irock.app.ios`
- Tunnel: `com.irock.app.ios.tunnel`

## macOS targets

`apps/irock-macOS/irock-macOS.xcodeproj` contains:

- `irockMacApp`: SwiftUI app shell importing `IrockAppFeature`
- `irockMacTunnelExtension`: Packet Tunnel Provider shell importing runtime snapshot and tunnel configuration packages

Bundle IDs:

- App: `com.irock.app.macos`
- Tunnel: `com.irock.app.macos.tunnel`

## Shared App Group

All app and tunnel targets use this placeholder App Group:

```text
group.com.irock.shared
```

`apps/Shared/IrockPlatformSupport` resolves the App Group container and the shared runtime snapshot file name:

```text
runtime-snapshot.json
```

## Signing requirements

Do not commit provisioning profiles, certificates, private keys, or personal Team IDs.

Before running on device or starting a real VPN tunnel, configure locally in Xcode:

- Apple Developer Team
- App Groups for `group.com.irock.shared`
- Keychain Sharing
- Network Extensions / Packet Tunnel Provider entitlement
- Matching bundle IDs for app and tunnel targets

## Verification

SwiftPM verification:

```bash
swift test
```

Workspace discovery:

```bash
xcodebuild -list -workspace irock.xcworkspace
```

Generic builds:

```bash
xcodebuild -workspace irock.xcworkspace -scheme irockApp -destination 'generic/platform=iOS' build
xcodebuild -workspace irock.xcworkspace -scheme irockMacApp -destination 'generic/platform=macOS' build
```

Signing-related build failures require local account/capability setup. Source compile, package dependency, missing file, or scheme discovery failures should be fixed in the repository.
```

- [ ] **Step 7: Commit docs refresh**

Run:

```bash
git add README.md CLAUDE.md apps/XCODE_TARGETS.md
git commit -m "$(cat <<'EOF'
docs: document Xcode target skeleton

Update project guidance for the XcodeGen-backed app and Packet Tunnel target skeleton with App Group wiring.
EOF
)"
```

---

## Final Verification Checklist

After all tasks complete, run:

```bash
git status --short
swift test
xcodebuild -list -workspace irock.xcworkspace
```

Also run these and record whether they pass or fail only at signing/provisioning:

```bash
xcodebuild -workspace irock.xcworkspace -scheme irockApp -destination 'generic/platform=iOS' build
xcodebuild -workspace irock.xcworkspace -scheme irockMacApp -destination 'generic/platform=macOS' build
```

Expected final state:

- `git status --short` shows no uncommitted tracked changes.
- `swift test` passes with all SwiftPM tests.
- `xcodebuild -list -workspace irock.xcworkspace` discovers iOS and macOS app/tunnel schemes.
- iOS/macOS project generation succeeds from XcodeGen specs.
- Generic Xcode builds either pass or fail only because local signing/team/capability setup is missing.
- README, CLAUDE.md, and `apps/XCODE_TARGETS.md` accurately describe the new Xcode skeleton and signing limitations.
