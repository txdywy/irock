# M28 Packet Tunnel Long-Running Packet Loop Design

## Goal

Replace the iOS Packet Tunnel extension's one-shot smoke execution with a cancellable provider lifecycle loop that repeatedly runs packet batches after network settings are applied.

## Context

M26 connected `PacketTunnelProvider` to a real `NEPacketTunnelFlow` adapter and App Group runtime stores. M27 added deterministic `NEPacketTunnelNetworkSettings` application before runtime startup. The remaining gap before platform networking work is that `startTunnel(options:)` still awaits one batch and then returns or fails instead of hosting a long-running tunnel task.

M28 keeps the existing shared runtime batch boundary intact. `PacketTunnelRuntime.runOnce()` remains the deterministic unit for tests and future packet/proxy work; the iOS extension adds the lifecycle loop around that unit.

## Scope

- Add an extension-local long-running loop runner.
- Apply tunnel settings before starting the loop.
- Start the loop from `PacketTunnelProvider.startTunnel(options:)` without awaiting normal loop completion forever.
- Cancel the loop from `stopTunnel(with:)`.
- Keep loop pacing bounded with a small configurable delay between batches.
- Stop retrying only when the task is cancelled or a non-cancellation runtime error escapes.
- Extend scaffold/static tests so Xcode source membership and provider wiring are checked.

## Out of scope

- Real TCP socket transport.
- Shadowsocks encryption or remote proxy data exchange.
- UDP forwarding completeness.
- High-throughput tuning, adaptive backpressure, or batching heuristics.
- Signing, provisioning, App Group entitlement activation, and device-only validation.

## Architecture

The extension gains a new `IOSPacketTunnelLoopRunner` type. It depends on the existing `IOSPacketTunnelSmokeRunner` and repeatedly calls `runOnce(packetFlow:)` until cancellation. The runner is extension-local because it directly references `NEPacketTunnelFlow`; shared packages stay platform-neutral.

`PacketTunnelProvider.startTunnel(options:)` applies `PacketTunnelRuntimeSettingsApplicator`, creates a `Task<Void, Error>` that awaits the loop runner, stores it in `startTunnelTask`, and returns after the task is created. `stopTunnel(with:)` cancels and clears the stored task.

The existing `IOSPacketTunnelSmokeRunner` keeps its name for this milestone because it still represents one batch through the current smoke/runtime path. The loop runner gives it a long-running lifecycle without expanding shared runtime scope prematurely.

## Data flow

```text
PacketTunnelProvider.startTunnel
  -> PacketTunnelRuntimeSettingsApplicator.apply(to: provider)
  -> Task { IOSPacketTunnelLoopRunner.run(packetFlow: provider.packetFlow) }
      -> repeat while !Task.isCancelled
          -> IOSPacketTunnelSmokeRunner.runOnce(packetFlow:)
              -> PacketTunnelAppGroupStoreResolver.makeRuntimeStoreBundle()
              -> TunnelRuntimeController.runShadowsocksTCPBatch(...)
          -> Task.sleep(loopDelay)

PacketTunnelProvider.stopTunnel
  -> startTunnelTask?.cancel()
  -> startTunnelTask = nil
```

## Cancellation and errors

The loop checks cancellation before each batch and after each batch delay. `Task.sleep` naturally throws `CancellationError` when the provider stops the tunnel. Runtime errors from `runOnce(packetFlow:)` are not swallowed; they escape the loop task so existing status/log reporting remains truthful and future provider-level recovery can be designed explicitly.

This means M28 does not introduce silent retry of missing snapshots or proxy failures. Missing snapshot is still a startup/runtime configuration problem surfaced through the existing `TunnelRuntimeController` reporting path.

## Testing strategy

Static scaffold tests will verify:

- `IOSPacketTunnelLoopRunner.swift` exists.
- The Xcode project includes it in the tunnel extension source phase.
- The loop runner references `IOSPacketTunnelSmokeRunner`, `Task.isCancelled`, and `Task.sleep`.
- `PacketTunnelProvider` uses `IOSPacketTunnelLoopRunner` instead of directly calling `IOSPacketTunnelSmokeRunner.runOnce`.
- The provider still applies settings before creating the loop runner task.

Build validation will remain:

- `swift test`
- `swift test --filter XcodeScaffoldTests`
- `xcodebuild -list -project apps/irock-iOS/irock.xcodeproj`
- Unsigned iOS Simulator build with `CODE_SIGNING_ALLOWED=NO`
- Import scans proving `NetworkExtension` remains inside the tunnel extension.

## Acceptance criteria

- `startTunnel(options:)` applies settings and starts a stored long-running task.
- `startTunnel(options:)` no longer awaits a single packet batch as the whole tunnel lifetime.
- `stopTunnel(with:)` cancels the stored loop task.
- The extension target compiles with the new loop runner.
- Shared packages still contain no platform imports.
