# M26 Real Packet Tunnel Smoke Path Design

Date: 2026-05-11

## Goal

M26 connects the iOS Packet Tunnel extension scaffold to the existing runtime seams with a narrow, reviewable smoke path that builds and reports deterministic failure states without attempting real VPN traffic forwarding.

The milestone proves that the extension target can see the shared SwiftPM products from M22-M24, adapt `NEPacketTunnelFlow` to the platform-neutral packet-flow boundary, resolve the App Group storage boundary from platform code, and invoke the shared runtime controller once.

## Context

M22 introduced the platform-neutral packet-flow boundary through `PacketFlowIO` and `PacketFlowRuntimeIO`. M23 added `TunnelRuntimeController.runShadowsocksTCPBatch(...)`, which loads a runtime snapshot, constructs the Shadowsocks TCP runtime, and runs one batch. M24 added `RuntimeStoreBundle` and `AppGroupRuntimeStoreDirectory`, giving platform shells a way to construct shared stores after they obtain a real App Group container URL. M25 added the iOS Xcode app and Packet Tunnel extension scaffold, with an empty `PacketTunnelProvider` entry point.

M26 should not turn the scaffold into a production VPN. The next safe step is to wire the provider to the existing seams in a way that is static-testable and unsigned-simulator-buildable, while preserving all platform-framework imports inside the iOS extension directory.

## Scope

In scope:

- Add extension-local code under `apps/irock-iOS/irockTunnelExtension` for the provider smoke path.
- Add an `NEPacketTunnelFlow` adapter that conforms to `PacketFlowIO` and converts `NEPacket` arrays to existing `Packet` values.
- Add an App Group store resolver that calls `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` only from the extension target.
- Add a small smoke runner that builds a `RuntimeStoreBundle` and invokes `TunnelRuntimeController.runShadowsocksTCPBatch(...)` once.
- Update `PacketTunnelProvider.startTunnel(options:)` to call the smoke runner.
- Update `PacketTunnelProvider.stopTunnel(with:)` only enough to cancel any smoke task if the provider is stopped while starting.
- Update the Xcode project scaffold so any new extension Swift files are members of the extension target.
- Extend static validation tests so SwiftPM catches missing smoke-path files, missing Xcode source membership, and platform import leakage into shared packages.
- Preserve unsigned simulator build verification with `CODE_SIGNING_ALLOWED=NO`.

Out of scope:

- Real Apple Developer Team IDs, provisioning profiles, signing identities, or production App Group identifiers.
- Required live device VPN execution.
- `setTunnelNetworkSettings`, DNS configuration, routes, MTU, or system proxy settings.
- A long-running packet loop, cancellation/backpressure policy, or throughput tuning.
- Production `NEPacketTunnelFlow` packet response synthesis.
- Real TCP/TLS sockets or `Network.framework` transport implementation.
- Calling private APIs or adding platform imports to shared SwiftPM packages.
- macOS Packet Tunnel wiring.

## Approach Decision

Considered approaches:

1. **Provider smoke path with deterministic unsupported transport failure**
   - Wire the provider, flow adapter, App Group store resolver, and runtime controller.
   - Use existing `UnsupportedTransportAdapter` / `NoopTransportAdapter` so runtime execution can fail deterministically before real networking.
   - Best fit for M26 because it proves target wiring and storage/runtime integration without pretending the app can carry live VPN traffic.

2. **Full live packet loop inside `PacketTunnelProvider`**
   - Start tunnel settings, read packets continuously, run runtime batches repeatedly, and write packet results back.
   - Too much for M26 because signing, routes, DNS, cancellation, and packet semantics would all become coupled.

3. **Shared package abstraction for platform packet flow**
   - Add a new reusable adapter abstraction in `IrockTunnelCore` and hide `NetworkExtension` behind protocols.
   - Premature for M26 because `NetworkExtension` types cannot enter shared packages, and the immediate need is only one iOS shell adapter.

Chosen approach: option 1.

## Component Design

### `PacketTunnelProvider`

`PacketTunnelProvider` remains the iOS extension entry point and the only type subclassing `NEPacketTunnelProvider`.

Responsibilities:

- Create an `IOSPacketTunnelSmokeRunner` during `startTunnel(options:)`.
- Pass `self.packetFlow` and `FileManager.default` to the runner.
- Store a `Task<Void, Never>?` if the smoke run is launched asynchronously.
- Cancel the task in `stopTunnel(with:)`.

The provider should not contain packet conversion logic, App Group URL resolution details, or runtime bootstrap code. Those responsibilities belong in extension-local helper types so the provider stays thin.

### `NEPacketTunnelFlowPacketFlowIO`

Create an extension-local adapter under `apps/irock-iOS/irockTunnelExtension` that conforms to `PacketFlowIO`.

Responsibilities:

- Hold an `NEPacketTunnelFlow` reference.
- Implement `readPackets(limit:)` by calling `readPacketObjects()` and mapping up to `limit` packets into `Packet` values.
- Implement `writePackets(_:)` by converting forwarded `PacketProcessingResult` values back to `NEPacket` objects and calling `writePacketObjects(_:)`.
- Drop or ignore non-forwarding results in the write path because existing packet processor results can represent dropped packets.

The adapter should live only in the extension target because it imports `NetworkExtension`.

### `PacketTunnelAppGroupStoreResolver`

Create an extension-local resolver that turns the placeholder App Group identifier into a `RuntimeStoreBundle`.

Responsibilities:

- Store the App Group identifier string, defaulting to `group.dev.irock.shared`.
- Call `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` from platform code.
- Return `nil` or throw a small extension-local error if the container URL is unavailable.
- Construct `AppGroupRuntimeStoreDirectory(containerURL:)` and call `makeRuntimeStoreBundle()`.

This keeps real App Group API calls out of `IrockStorage` while proving the intended boundary.

### `IOSPacketTunnelSmokeRunner`

Create an extension-local runner that owns the one-shot smoke flow.

Responsibilities:

- Resolve the runtime store bundle.
- Construct `NEPacketTunnelFlowPacketFlowIO` with the provider flow and a small batch limit.
- Invoke `TunnelRuntimeController.runShadowsocksTCPBatch(...)` once.
- Use existing unsupported/noop transport adapters for both plain TCP and TLS paths.
- Let errors propagate to `PacketTunnelProvider.startTunnel(options:)` so the provider fails start in a deterministic, diagnosable way when prerequisites are missing.

The runner intentionally does not set tunnel network settings or loop forever. A missing runtime snapshot should be reported by `TunnelRuntimeController` through the existing status/log stores once the App Group container resolves.

## Data Flow

```text
PacketTunnelProvider.startTunnel
  -> IOSPacketTunnelSmokeRunner.runOnce(packetFlow:)
      -> PacketTunnelAppGroupStoreResolver.makeRuntimeStoreBundle()
          -> FileManager.containerURL(forSecurityApplicationGroupIdentifier:)
          -> AppGroupRuntimeStoreDirectory.makeRuntimeStoreBundle()
      -> NEPacketTunnelFlowPacketFlowIO(packetFlow:batchLimit:)
      -> TunnelRuntimeController.runShadowsocksTCPBatch(...)
          -> RuntimeSnapshotStore.load()
          -> PacketFlowRuntimeIO.readBatch()
          -> TunnelRuntimeBootstrap.shadowsocksTCP(...)
          -> PacketTunnelRuntime.runOnce()
```

Expected smoke outcomes:

- If the App Group container is unavailable, `startTunnel` throws an extension-local App Group error.
- If the container exists but no runtime snapshot has been written, `TunnelRuntimeController` records a failed runtime status and user log, then throws `missingRuntimeSnapshot`.
- If a snapshot exists, the one-shot runtime path may reach unsupported/noop transport behavior. That is acceptable for M26 because real network transport is not in scope.

## Error Handling

M26 should prefer explicit failure over silent fallback.

- Missing App Group container: throw an extension-local error with a stable message.
- Missing runtime snapshot: rely on existing `TunnelRuntimeControllerError.missingRuntimeSnapshot` behavior.
- Packet read/write errors: propagate from `NEPacketTunnelFlow` adapter to the runtime caller.
- Stop during smoke startup: cancel the stored task; do not attempt cleanup beyond cancellation.

No user-facing UI error surface is added in M26. Status and log stores remain the runtime reporting path once the App Group container is available.

## Testing and Validation Strategy

SwiftPM cannot import `NetworkExtension` in package tests without moving platform code into shared packages, so M26 validation should combine static tests and Xcode build checks.

Static validation in `XcodeScaffoldTests` should assert:

1. New extension smoke-path files exist.
2. New extension files are present in the Xcode project group and source build phase.
3. `PacketTunnelProvider.swift` references the smoke runner rather than remaining empty.
4. `NetworkExtension` imports remain confined to `apps/irock-iOS/irockTunnelExtension`.
5. Shared packages still avoid `NetworkExtension`, `Network`, `Security`, `UIKit`, and `AppKit` imports.
6. The Xcode project still embeds the Packet Tunnel extension and references the existing SwiftPM products.

Manual/command validation:

```bash
swift test --filter XcodeScaffoldTests
swift test
xcodebuild -list -project apps/irock-iOS/irock.xcodeproj
xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
grep -R "import NetworkExtension\|import Network\|import Security\|import UIKit\|import AppKit" -n packages Package.swift || true
grep -R "import NetworkExtension" -n apps/irock-iOS/irockTunnelExtension
```

Expected validation result: SwiftPM tests pass, unsigned simulator build succeeds, and forbidden platform imports do not appear in shared packages.

## Success Criteria

M26 is complete when:

- `PacketTunnelProvider.startTunnel(options:)` invokes an extension-local smoke runner.
- The extension target contains a real `NEPacketTunnelFlow` to `PacketFlowIO` adapter.
- The extension target resolves the App Group container and constructs `RuntimeStoreBundle` through the M24 boundary.
- The smoke runner calls `TunnelRuntimeController.runShadowsocksTCPBatch(...)` once using existing M22-M23 seams.
- New extension Swift files are included in the Xcode project source phase.
- Shared packages remain platform-neutral with no forbidden platform imports.
- `swift test` and unsigned iOS Simulator `xcodebuild` validation pass.
