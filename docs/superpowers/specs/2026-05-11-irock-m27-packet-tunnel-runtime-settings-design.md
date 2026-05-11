# M27 Packet Tunnel Runtime Settings Design

Date: 2026-05-11

## Goal

M27 adds the first real `NEPacketTunnelNetworkSettings` construction and application path to the iOS Packet Tunnel extension, so provider startup configures deterministic tunnel settings before entering the existing M26 smoke runner.

## Context

M26 proved that the iOS Packet Tunnel provider can compile with extension-local `NetworkExtension` code, resolve the App Group runtime store boundary, adapt `NEPacketTunnelFlow` to `PacketFlowIO`, and invoke `TunnelRuntimeController` once. It still starts without applying tunnel network settings, so it is not yet shaped like a real Packet Tunnel lifecycle.

The next safe milestone is to set network settings inside the extension target while keeping routing policy, DNS strategy, signing, and long-running packet loops out of scope.

## Scope

In scope:

- Add extension-local runtime settings types under `apps/irock-iOS/irockTunnelExtension`.
- Build `NEPacketTunnelNetworkSettings` with deterministic defaults:
  - tunnel remote address: `127.0.0.1`
  - IPv4 address: `10.255.0.2`
  - subnet mask: `255.255.255.0`
  - included route: default IPv4 route
  - DNS servers: `1.1.1.1`, `8.8.8.8`
  - MTU: `1500`
- Apply settings through `setTunnelNetworkSettings(_:)` before running the M26 smoke path.
- Extend static validation to ensure settings files exist, are included in the Xcode extension target, and provider startup calls the settings applicator before the smoke runner.
- Keep all `NetworkExtension` imports inside `apps/irock-iOS/irockTunnelExtension`.
- Preserve unsigned iOS Simulator build validation.

Out of scope:

- Real signing, provisioning, Team ID, or production App Group values.
- Long-running packet loops.
- Production DNS selection.
- Split routing, excluded routes, per-app VPN, IPv6, captive portal handling, or advanced MTU discovery.
- UI for editing tunnel settings.
- macOS Packet Tunnel settings.

## Approach Decision

Considered approaches:

1. **Extension-local defaults and applicator**
   - Add small helper types in the extension target only.
   - Provider applies settings before calling `IOSPacketTunnelSmokeRunner`.
   - Static tests and unsigned Xcode build validate the wiring.
   - Chosen because it advances real Packet Tunnel lifecycle shape without coupling to routing policy or app UI.

2. **Shared package settings model**
   - Define cross-platform settings in SwiftPM and convert to `NEPacketTunnelNetworkSettings` in extension code.
   - Useful later, but premature before real route policy exists.

3. **Full route/DNS policy from runtime snapshot**
   - Derive settings from selected node and routing rules.
   - Too broad for M27 because it couples Packet Tunnel lifecycle with app/runtime policy before the basic provider setup is proven.

Chosen approach: option 1.

## Component Design

### `PacketTunnelRuntimeSettingsConfiguration`

An extension-local `Sendable` value containing deterministic defaults:

- `tunnelRemoteAddress`
- `ipv4Address`
- `ipv4SubnetMask`
- `dnsServers`
- `mtu`

This type is not placed in a shared package because it exists only to build `NetworkExtension` settings for the iOS shell.

### `PacketTunnelRuntimeSettingsFactory`

An extension-local factory that imports `NetworkExtension` and returns `NEPacketTunnelNetworkSettings`.

Responsibilities:

- Create `NEPacketTunnelNetworkSettings(tunnelRemoteAddress:)`.
- Assign `NEIPv4Settings(addresses:subnetMasks:)`.
- Set `includedRoutes = [.default()]`.
- Assign `NEDNSSettings(servers:)`.
- Set `mtu` from configuration.

### `PacketTunnelRuntimeSettingsApplicator`

An extension-local applicator that owns the async call to `setTunnelNetworkSettings(_:)`.

Responsibilities:

- Build settings with the factory.
- Call `provider.setTunnelNetworkSettings(settings)`.
- Let errors propagate to `startTunnel(options:)` so provider startup fails explicitly if settings application fails.

### `PacketTunnelProvider`

Provider startup sequence becomes:

```text
PacketTunnelProvider.startTunnel
  -> PacketTunnelRuntimeSettingsApplicator.apply(to: self)
  -> IOSPacketTunnelSmokeRunner.runOnce(packetFlow: packetFlow)
```

`stopTunnel(with:)` keeps the M26 cancellation behavior.

## Data Flow

```text
PacketTunnelProvider.startTunnel
  -> PacketTunnelRuntimeSettingsApplicator.apply(to:)
      -> PacketTunnelRuntimeSettingsFactory.makeNetworkSettings()
          -> NEPacketTunnelNetworkSettings
          -> NEIPv4Settings.default route
          -> NEDNSSettings
      -> NEPacketTunnelProvider.setTunnelNetworkSettings
  -> IOSPacketTunnelSmokeRunner.runOnce
```

## Error Handling

- Settings construction is deterministic and should not throw.
- `setTunnelNetworkSettings(_:)` can throw; the provider should propagate the error rather than falling back silently.
- The smoke runner should not start if settings application fails.
- Stop behavior remains cancellation-only for M27.

## Testing and Validation Strategy

SwiftPM tests cannot instantiate and inspect `NetworkExtension` runtime behavior from shared packages, so M27 uses static validation plus Xcode build validation.

Static validation in `XcodeScaffoldTests` should assert:

1. M27 settings files exist.
2. M27 settings files are included in the Xcode extension source phase.
3. The settings factory contains `NEPacketTunnelNetworkSettings`, `NEIPv4Settings`, `NEDNSSettings`, `.default()`, DNS defaults, and MTU default.
4. `PacketTunnelProvider.startTunnel` references `PacketTunnelRuntimeSettingsApplicator` before `IOSPacketTunnelSmokeRunner` in source order.
5. Shared packages remain free of forbidden platform imports.

Command validation:

```bash
swift test --filter XcodeScaffoldTests
swift test
xcodebuild -list -project apps/irock-iOS/irock.xcodeproj
xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
grep -R "import NetworkExtension\|import Network\|import Security\|import UIKit\|import AppKit" -n packages Package.swift || true
grep -R "import NetworkExtension" -n apps/irock-iOS/irockTunnelExtension
```

## Success Criteria

M27 is complete when:

- The extension target contains runtime settings configuration, factory, and applicator helpers.
- `PacketTunnelProvider.startTunnel(options:)` applies tunnel network settings before starting the smoke runner.
- The Xcode project includes the new settings files in the extension target.
- Static tests cover the settings files, provider ordering, and import boundaries.
- `swift test` and unsigned iOS Simulator `xcodebuild` pass.
