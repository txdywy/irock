# M23 Tunnel Runtime Controller Design

Date: 2026-05-11

## Goal

M23 adds a deterministic tunnel runtime controller that loads the latest `RuntimeSnapshot`, adapts a packet-flow boundary into runtime packet I/O, bootstraps a Shadowsocks TCP runtime, and executes one runtime batch.

The controller is the tunnel-side orchestration seam a future Packet Tunnel extension can call after platform code has provided stores, packet flow, and transport adapters. It remains SwiftPM-testable and does not import `NetworkExtension`, `Network`, or `Security`.

## Context

M21 introduced `TunnelRuntimeBootstrap.shadowsocksTCP(...)`, which builds a fully wired `PacketTunnelRuntime` from a snapshot, packet reader/writer, status/log stores, and plain/TLS transport adapters.

M22 introduced `PacketFlowIO` and `PacketFlowRuntimeIO`, which let a platform-neutral packet-flow source conform to the runtime's `PacketReader` and `PacketWriter` shape.

Callers still need to manually perform the tunnel startup sequence:

```text
RuntimeSnapshotStore.load()
  -> ensure snapshot exists
  -> PacketFlowRuntimeIO(flow:batchLimit:)
  -> TunnelRuntimeBootstrap.shadowsocksTCP(...)
  -> PacketTunnelRuntime.runOnce()
```

M23 closes that gap with a controller that owns this orchestration while preserving the current one-batch runtime execution model.

## Scope

In scope:

- Add a public `TunnelRuntimeController` in `IrockTunnelCore`.
- Load the current `RuntimeSnapshot` from an injected `RuntimeSnapshotStore`.
- Adapt an injected `PacketFlowIO` through `PacketFlowRuntimeIO`.
- Use `TunnelRuntimeBootstrap.shadowsocksTCP(...)` to assemble the runtime.
- Execute one batch through `PacketTunnelRuntime.runOnce()`.
- Return the existing `PacketTunnelRuntimeSummary` to callers.
- Publish safe status/log output when no runtime snapshot is available.
- Preserve existing bootstrap and runtime error behavior for invalid manifests and packet-flow failures.
- Cover success, missing snapshot, invalid manifest, read failure, and write failure behavior with deterministic tests.

Out of scope:

- Long-running packet loops, cancellation, sleep/retry policy, lifecycle state machines, or backpressure.
- Xcode workspace, app targets, Packet Tunnel extension targets, App Groups, signing, entitlements, or `NEPacketTunnelProvider`.
- Real packet flow, sockets, TLS handshakes, DNS, route installation, packet response synthesis, credential retrieval, or encryption.
- Multi-protocol selection beyond the current Shadowsocks TCP/TLS assembly path.

## Component Design

### TunnelRuntimeController

Add `TunnelRuntimeController` to `IrockTunnelCore`:

```swift
public struct TunnelRuntimeController: Sendable {
    public static func runShadowsocksTCPBatch<Flow: PacketFlowIO, Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary
}
```

Behavior:

1. Load the current snapshot through `snapshotStore.load()`.
2. If no snapshot exists, publish failed status/log output with a safe missing-snapshot message and throw `TunnelRuntimeControllerError.missingRuntimeSnapshot`.
3. Create `PacketFlowRuntimeIO(flow:flow,batchLimit:batchLimit)`.
4. Call `TunnelRuntimeBootstrap.shadowsocksTCP(...)` with the loaded snapshot, packet-flow runtime I/O, runtime stores, transport adapters, and limits.
5. Call `runtime.runOnce()` and return its summary.

The controller does not catch bootstrap or runtime errors except for the missing-snapshot case it owns. Invalid routing manifests, packet-flow read/write failures, proxy adapter failures, and transport failures keep their existing error types and reporting behavior.

### TunnelRuntimeControllerError

Add a focused error enum:

```swift
public enum TunnelRuntimeControllerError: Error, Equatable, Sendable {
    case missingRuntimeSnapshot
}
```

The missing-snapshot case is a controller-level precondition failure: the app has not published a runtime snapshot for the tunnel to consume.

### Missing snapshot reporting

When the snapshot is missing, the controller cannot include selected node identity. It should write a generic failed status/log through stores directly:

- Status phase: `.failed`
- Selected node ID: `nil`
- Selected node name: `nil`
- Message: `Runtime snapshot unavailable`
- Log level: `.user`
- Log message: `Runtime snapshot unavailable`
- Log phase: `.failed`

Store failures should not mask the missing-snapshot error. Reporting is best-effort, matching `PacketTunnelRuntime` reporter behavior.

## Data Flow

Success path:

```text
TunnelRuntimeController.runShadowsocksTCPBatch(...)
  -> RuntimeSnapshotStore.load()
  -> PacketFlowRuntimeIO(flow:batchLimit:)
  -> TunnelRuntimeBootstrap.shadowsocksTCP(...)
  -> PacketTunnelRuntime.runOnce()
  -> PacketProcessor + ProxyOutbound + RuntimeProxyStack
  -> PacketFlowIO.writePackets(results)
  -> PacketTunnelRuntimeSummary
```

Missing snapshot path:

```text
TunnelRuntimeController.runShadowsocksTCPBatch(...)
  -> RuntimeSnapshotStore.load() returns nil
  -> RuntimeStatusStore.save(failed, "Runtime snapshot unavailable") best effort
  -> RuntimeLogStore.append("Runtime snapshot unavailable") best effort
  -> throw TunnelRuntimeControllerError.missingRuntimeSnapshot
```

Invalid manifest path:

```text
TunnelRuntimeController.runShadowsocksTCPBatch(...)
  -> RuntimeSnapshotStore.load() returns snapshot
  -> TunnelRuntimeBootstrap.shadowsocksTCP(...)
  -> RuntimeRoutingRuleAdapter throws existing adapter error
  -> caller receives existing error
```

## Error Handling

M23 introduces only `TunnelRuntimeControllerError.missingRuntimeSnapshot`.

- Missing snapshot is owned by the controller and reported before throwing.
- Snapshot store load errors propagate unchanged and are not reported, because the controller cannot know whether the state is missing, unreadable, or corrupted.
- Invalid routing manifests propagate from `TunnelRuntimeBootstrap` unchanged.
- Packet-flow read/write failures propagate from `PacketTunnelRuntime.runOnce()` unchanged and continue to publish `Packet batch failed` through existing runtime reporting.
- Proxy and transport failures continue to use existing protocol error mapping and safe runtime messages.
- Status/log store failures during controller-owned missing-snapshot reporting are ignored.

## Testing Strategy

Add `TunnelRuntimeControllerTests` in `IrockTunnelCoreTests`.

Required tests:

1. Successful `runShadowsocksTCPBatch(...)` loads the snapshot, adapts packet flow, runs one packet batch, connects through the plain transport child, writes one result, and returns the runtime summary.
2. Missing snapshot publishes safe failed status/log output and throws `TunnelRuntimeControllerError.missingRuntimeSnapshot`.
3. Missing snapshot still throws `missingRuntimeSnapshot` when status/log stores fail.
4. Invalid routing manifest propagates the existing `RuntimeRoutingRuleAdapterError` before packet I/O runs.
5. Packet-flow read failure propagates the original error and publishes the existing `Packet batch failed` runtime status/log output.
6. Packet-flow write failure propagates the original error and publishes the existing `Packet batch failed` runtime status/log output.

Full acceptance requires:

```bash
swift test --filter TunnelRuntimeControllerTests
swift test --filter IrockTunnelCoreTests
swift test
grep -R "import Network\|import Security\|import NetworkExtension" -n packages/IrockTunnelCore packages/IrockProtocols packages/IrockTransport Package.swift || true
```

## Success Criteria

M23 is complete when:

- Future Packet Tunnel shell code can trigger one Shadowsocks TCP runtime batch through one controller call.
- The controller uses `RuntimeSnapshotStore`, `PacketFlowRuntimeIO`, and `TunnelRuntimeBootstrap` instead of duplicating their responsibilities.
- Missing snapshot is reported with safe user-facing status/log output.
- Existing invalid-manifest and packet-flow failure behavior remains unchanged.
- No platform networking frameworks, Xcode targets, signing settings, or live VPN behavior are introduced.
- `swift test` passes.
