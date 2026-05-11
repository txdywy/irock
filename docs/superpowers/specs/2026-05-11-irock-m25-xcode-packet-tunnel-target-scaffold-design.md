# M25 Xcode Packet Tunnel Target Scaffold Design

Date: 2026-05-11

## Goal

M25 adds a reviewable Xcode scaffold for the iOS container app and Packet Tunnel extension so future platform work has concrete target files, bundle metadata, entitlement templates, and a provider entry point.

The scaffold is intentionally not a signed, device-runnable VPN app. It avoids local Apple Developer Team choices, provisioning profiles, real App Group identifiers, and live VPN execution.

## Context

The repository currently has SwiftPM packages for reusable logic and placeholder app directories under `apps/irock-iOS` and `apps/irock-macOS`.

M22 added a platform-neutral packet-flow boundary. M23 added `TunnelRuntimeController.runShadowsocksTCPBatch(...)`, the shared orchestration seam a future Packet Tunnel provider can call. M24 added `RuntimeStoreBundle` and `AppGroupRuntimeStoreDirectory`, giving future platform shells a neutral storage construction path once they resolve a real App Group container URL.

The next boundary is an Xcode-facing shell. This milestone should create enough structure for future Xcode work without pretending to solve signing or live Network Extension execution in an automated SwiftPM-only environment.

## Scope

In scope:

- Add a minimal iOS Xcode project scaffold under `apps/irock-iOS/irock.xcodeproj`.
- Add iOS app shell files under `apps/irock-iOS/irockApp`.
- Add iOS Packet Tunnel extension shell files under `apps/irock-iOS/irockTunnelExtension`.
- Add entitlement template files for the app and extension using placeholder App Group values.
- Add Info.plist files for the app and extension.
- Add a `PacketTunnelProvider.swift` lifecycle scaffold that imports `NetworkExtension` only inside the extension target directory.
- Add an app entry point that imports `SwiftUI` only inside the app target directory.
- Reference existing SwiftPM products from the Xcode project scaffold so future Xcode build work has a clear dependency map.
- Add static tests/scripts or XCTest coverage where practical to validate scaffold files, plist contents, entitlements, and platform import boundaries.

Out of scope:

- Real Apple Developer Team IDs, provisioning profiles, code signing identities, or automatic signing mutation.
- Real App Group identifiers beyond placeholder template strings.
- Running `xcodebuild` as a required acceptance gate, because no local team/scheme signing setup is guaranteed.
- macOS app/extension scaffold; M25 focuses on iOS first.
- Real `NEPacketTunnelFlow` packet adaptation, route installation, tunnel settings, DNS settings, packet loops, cancellation policy, or long-running runtime execution.
- Calling `TunnelRuntimeController.runShadowsocksTCPBatch(...)` from the provider; that is reserved for M26 after the platform adapter and runtime dependencies can be wired safely.
- Moving shared package code into Xcode app directories.

## Component Design

### iOS Xcode project scaffold

Create `apps/irock-iOS/irock.xcodeproj/project.pbxproj` as a minimal, reviewable project file with two targets:

- `irockApp`: iOS application target.
- `irockTunnelExtension`: iOS Packet Tunnel extension target.

The project should encode the intended relationship:

```text
irockApp
  -> embeds irockTunnelExtension
  -> depends on IrockAppFeature, IrockCore, IrockStorage

irockTunnelExtension
  -> depends on IrockTunnelCore, IrockCore, IrockStorage, IrockTransport, IrockProtocols
```

The project may use placeholder signing settings such as:

- `DEVELOPMENT_TEAM = ""`
- `CODE_SIGN_STYLE = Automatic`
- `PRODUCT_BUNDLE_IDENTIFIER = dev.irock.app`
- `PRODUCT_BUNDLE_IDENTIFIER = dev.irock.app.tunnel`

This file is a scaffold and is statically reviewed. It is not required to pass `xcodebuild` until signing decisions are made.

### iOS app shell

Create these files:

```text
apps/irock-iOS/irockApp/IrockApp.swift
apps/irock-iOS/irockApp/ContentView.swift
apps/irock-iOS/irockApp/Info.plist
apps/irock-iOS/irockApp/irockApp.entitlements
```

`IrockApp.swift` should define a minimal SwiftUI `App` entry point. `ContentView.swift` should host the shared `IrockAppFeature.RootView` if that is available to the target, or a minimal placeholder view if Xcode package wiring remains scaffold-only.

The app entitlement template should include:

- `com.apple.security.application-groups` with placeholder value `group.dev.irock.shared`.

### iOS Packet Tunnel extension shell

Create these files:

```text
apps/irock-iOS/irockTunnelExtension/PacketTunnelProvider.swift
apps/irock-iOS/irockTunnelExtension/Info.plist
apps/irock-iOS/irockTunnelExtension/irockTunnelExtension.entitlements
```

`PacketTunnelProvider.swift` should contain a minimal `NEPacketTunnelProvider` subclass:

```swift
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(options: [String: NSObject]?) async throws {
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
    }
}
```

It should not create packet loops or call the runtime controller yet. The goal is to establish the extension entry point and lifecycle method shape.

The extension `Info.plist` should identify the extension point:

- `NSExtensionPointIdentifier = com.apple.networkextension.packet-tunnel`
- `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).PacketTunnelProvider`

The extension entitlement template should include:

- `com.apple.security.application-groups` with placeholder value `group.dev.irock.shared`.
- `com.apple.developer.networking.networkextension` with `packet-tunnel-provider`.

## Import Boundary

M25 permits platform imports only in platform target directories:

- `apps/irock-iOS/irockApp`: `SwiftUI` is allowed.
- `apps/irock-iOS/irockTunnelExtension`: `NetworkExtension` is allowed.

Shared tunnel, protocol, transport, and storage packages must remain platform-neutral except for their existing Foundation usage. `IrockAppFeature` may continue to use SwiftUI because it is the reusable app-facing UI package. The verification scan must continue to forbid these imports in shared packages:

- `Network`
- `NetworkExtension`
- `Security`
- `UIKit`
- `AppKit`

## Data Flow

M25 establishes file and target boundaries only:

```text
Xcode project scaffold
  -> irockApp target
      -> future app feature UI and runtime snapshot publishing
      -> embeds irockTunnelExtension
  -> irockTunnelExtension target
      -> PacketTunnelProvider lifecycle entry point
      -> future AppGroupRuntimeStoreDirectory + PacketFlowIO adapter + TunnelRuntimeController
```

M26 will wire runtime execution. M25 only creates the location where that wiring will live.

## Error Handling

M25 introduces no runtime error handling because it does not execute tunnel logic.

- `PacketTunnelProvider.startTunnel(options:)` is intentionally empty.
- `PacketTunnelProvider.stopTunnel(with:)` is intentionally empty.
- Signing misconfiguration is not handled in code; placeholder entitlements and bundle identifiers make that state explicit in files.
- Static validation should fail if required scaffold files disappear, plist keys are missing, or forbidden imports leak into shared packages.

## Testing and Validation Strategy

Add static validation under SwiftPM tests, likely in a new test target or an existing lightweight test file, to avoid relying on local signing.

Required validation:

1. The Xcode project scaffold file exists.
2. App and extension Info.plist files exist and contain required keys.
3. App and extension entitlement templates contain `group.dev.irock.shared`.
4. Extension entitlements include `packet-tunnel-provider`.
5. `PacketTunnelProvider.swift` exists and imports `NetworkExtension`.
6. `NetworkExtension` does not appear in shared packages.
7. `SwiftUI` appears only in app target files, not shared packages.
8. `swift test` still passes.

Full acceptance requires:

```bash
swift test
grep -R "import NetworkExtension\|import Network\|import Security\|import UIKit\|import AppKit" -n packages Package.swift || true
grep -R "import NetworkExtension" -n apps/irock-iOS/irockTunnelExtension
grep -R "group.dev.irock.shared" -n apps/irock-iOS
```

## Success Criteria

M25 is complete when:

- The repository contains a concrete iOS app + Packet Tunnel extension Xcode scaffold.
- Placeholder bundle IDs, App Group entitlements, and Network Extension entitlement templates are explicit and reviewable.
- The Packet Tunnel provider entry point exists but does not execute runtime logic yet.
- Shared SwiftPM packages remain free of platform UI, Network Extension, Network, and Security imports.
- Static validation and `swift test` pass.
