# M32 Container App VPN Manager Integration Design

Date: 2026-05-11

## Goal

Let the iOS container app install, update, start, stop, and query the Packet Tunnel configuration through `NETunnelProviderManager` while keeping reusable state and runtime snapshot logic in shared packages.

## Current State

- The iOS app target contains only `IrockApp.swift`, `ContentView.swift`, `Info.plist`, and entitlements.
- The app target already depends on `IrockAppFeature`, `IrockCore`, and `IrockStorage`.
- The Packet Tunnel extension target exists and is embedded in the app target.
- The app and extension entitlements both declare placeholder App Group `group.dev.irock.shared`.
- The extension bundle identifier is `dev.irock.app.tunnel`.
- Shared packages deliberately do not import `NetworkExtension`, `Network`, `UIKit`, `AppKit`, or `Security`.

## Design

Add a small iOS-only VPN manager boundary in the app target:

- `IOSVPNManagerConfiguration`: deterministic placeholder configuration values.
- `IOSVPNManager`: async wrapper around `NETunnelProviderManager` for install/update/start/stop/status.
- `IOSVPNConnectionStatus`: small app-local status enum that avoids leaking NetworkExtension types into shared packages.

Keep `NetworkExtension` imports only in `apps/irock-iOS/irockApp`, not in shared packages. The shared `AppViewModel` remains platform-neutral and continues to publish runtime snapshots. The thin app shell can call the iOS manager after snapshot publication in a later UI wiring pass.

Update `ContentView` to host `IrockRootView` with an `AppViewModel`, preserving the thin shell pattern. This does not yet add production UI controls for start/stop; it ensures the container app is wired to the shared feature surface while M32 establishes the platform manager boundary.

## Scope

In scope:

- Add deterministic `NETunnelProviderManager` installation/update logic.
- Add start/stop/status methods behind an iOS app-local type.
- Use placeholder provider bundle identifier and localized description from project settings.
- Ensure new app files are included in the Xcode app target sources.
- Keep shared packages platform-neutral.
- Validate with static scaffold tests, SwiftPM tests, and unsigned iOS simulator build.

Out of scope:

- Real Apple Developer Team selection.
- Real provisioning profile or signed device validation.
- App Store distribution readiness.
- Full production UI for VPN permission flows.
- Persisting secrets or credentials in repo.

## Validation

- Tooling tests assert the iOS app owns the `NetworkExtension` import and manager files.
- Tooling tests assert the Xcode project includes the new manager files in app sources.
- Tooling tests assert shared packages remain free of platform imports.
- Full `swift test` passes.
- Unsigned iOS simulator build passes with `CODE_SIGNING_ALLOWED=NO`.
