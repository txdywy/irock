# M49 macOS App and Packet Tunnel Scaffold Design

Date: 2026-05-12

## Goal

Add a committed macOS app and Packet Tunnel target scaffold after the iOS path has proven the shared runtime architecture.

## Design

Create a thin macOS SwiftUI app shell and a thin macOS Packet Tunnel extension shell under `apps/irock-macOS`. The scaffold mirrors the proven iOS target shape while keeping reusable app, storage, routing, transport, protocol, and tunnel runtime behavior in shared Swift packages.

The macOS scaffold includes:

- `irockMacApp` SwiftUI container app hosting `IrockRootView`.
- App Group runtime store resolver for shared snapshot/status/log storage.
- VPN manager boundary using `NETunnelProviderManager`.
- `irockMacTunnelExtension` Packet Tunnel provider shell.
- Packet-flow adapter, runtime settings helpers, smoke runner, loop runner, App Group store resolver, and platform TCP dialer seams.
- Placeholder-only signing configuration and macOS device smoke runbook.
- Xcode project scaffold with macOS app and app-extension target shape.

## Scope

In scope:

- macOS scaffold files, plists, entitlements, signing placeholders, and project shape.
- Tooling tests that verify target files, entitlements, Packet Tunnel extension point, placeholder signing, platform import boundaries, and project markers.

Out of scope:

- Real Apple signing, provisioning profile creation, or Developer Team selection.
- Full macOS runtime validation against real nodes.
- Replacing shared runtime logic or duplicating business behavior in platform targets.
- UI redesign.

## Validation

- `XcodeScaffoldTests` cover required macOS files, Info.plist, entitlements, signing placeholders, and project shape.
- Shared packages remain free of platform imports.
- Signing credential artifact scans remain clean.
- Full SwiftPM tests pass.
