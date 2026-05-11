# M22 Packet Flow Adapter Boundary Design

Date: 2026-05-11

## Goal

M22 adds a deterministic packet-flow adapter boundary that describes how future platform Packet Tunnel code feeds packets into `PacketTunnelRuntime` without importing `NetworkExtension` into shared Swift packages.

The outcome is a small testable seam around packet ingress and egress. It prepares irock for real `NEPacketTunnelFlow` adapters while keeping current SwiftPM tests independent of Apple signing, entitlements, App Groups, and live VPN sessions.

## Context

M21 added `TunnelRuntimeBootstrap.shadowsocksTCP(...)`, which assembles a complete `PacketTunnelRuntime` from a `RuntimeSnapshot`, packet I/O, runtime stores, and plain/TLS transport adapters. The remaining gap before a real Packet Tunnel target is the system edge: platform code must translate packet-flow read/write callbacks into the existing `PacketReader` and `PacketWriter` protocols.

Current shared packages already provide:

```text
TunnelRuntimeBootstrap
  -> PacketTunnelRuntime
  -> PacketReader / PacketWriter
  -> PacketProcessor
  -> ProxyOutbound
  -> RuntimeProxyStack
  -> ShadowsocksProxyAdapter
  -> TCPTLSTransportAdapter
```

M22 should not make this path platform-specific. It should define an adapter-friendly boundary that a future target can use from `NetworkExtension` code without pulling that framework into `IrockTunnelCore`.

## Scope

In scope:

- Add a packet-flow adapter contract in `IrockTunnelCore` that models platform packet ingress and egress without naming `NEPacketTunnelFlow`.
- Add a reusable `PacketFlowRuntimeIO` adapter that conforms to `PacketReader` and `PacketWriter` by delegating to the contract.
- Preserve batch-oriented runtime behavior so `PacketTunnelRuntime.runOnce()` remains the deterministic execution unit.
- Provide deterministic in-memory or recording test doubles for the packet-flow contract.
- Prove successful read/process/write behavior through the new adapter and existing `TunnelRuntimeBootstrap`.
- Prove read and write failures propagate through existing runtime failure reporting.
- Keep `Network`, `NetworkExtension`, and `Security` imports out of `IrockTunnelCore`, `IrockProtocols`, `IrockTransport`, and `Package.swift`.

Out of scope:

- Creating Xcode workspaces, app targets, Packet Tunnel extension targets, signing settings, provisioning profiles, or entitlements.
- Importing or wrapping `NEPacketTunnelFlow` directly in any shared package.
- Real TUN file descriptors, live VPN packet loops, sockets, TLS handshakes, DNS, route installation, or packet response synthesis.
- Long-running runtime loops, cancellation, backpressure policy, or lifecycle orchestration beyond one deterministic batch.
- Credential retrieval or stream encryption.

## Component Design

### PacketFlowIO

Add a protocol to `IrockTunnelCore` that represents the minimal behavior needed from a packet-flow-like system edge:

```swift
public protocol PacketFlowIO: Sendable {
    func readPackets(limit: Int) async throws -> [Packet]
    func writePackets(_ results: [PacketProcessingResult]) async throws
}
```

Behavior:

- `readPackets(limit:)` returns decoded `Packet` values ready for `PacketProcessor`.
- `writePackets(_:)` accepts processed results from the runtime writer side.
- The protocol uses existing domain types, not platform packet representations.
- Platform targets can later implement this protocol by translating `NEPacketTunnelFlow.readPackets` output into `Packet` values and translating writable results back to platform writes.

The `limit` parameter keeps the adapter aligned with `PacketTunnelRuntime` batch behavior. It does not introduce its own buffering policy.

### PacketFlowRuntimeIO

Add a small adapter that bridges `PacketFlowIO` into the runtime's existing protocols:

```swift
public struct PacketFlowRuntimeIO<Flow: PacketFlowIO>: PacketReader, PacketWriter {
    public init(flow: Flow, batchLimit: Int)
    public func readBatch() async throws -> [Packet]
    public func write(_ results: [PacketProcessingResult]) async throws
}
```

Behavior:

- `readBatch()` calls `flow.readPackets(limit: batchLimit)`.
- `write(_:)` calls `flow.writePackets(results)`.
- Initialization validates no external state and performs no I/O.
- The type is generic so tests and future platform adapters can remain strongly typed and `Sendable`.

This keeps the existing `PacketTunnelRuntime<Reader, Writer>` API unchanged. Callers that already have separate reader and writer implementations can continue using them.

### Test doubles

Add local XCTest doubles rather than production-only in-memory helpers:

- `RecordingPacketFlowIO` returns a configured packet batch and records writes.
- `FailingReadPacketFlowIO` throws from `readPackets(limit:)`.
- `FailingWritePacketFlowIO` returns packets but throws from `writePackets(_:)`.

The tests should verify the adapter behavior without introducing general-purpose abstractions that are not yet needed by production code.

## Data Flow

Success path:

```text
Future platform packet flow
  -> platform-specific PacketFlowIO implementation
  -> PacketFlowRuntimeIO.readBatch()
  -> PacketTunnelRuntime.runOnce()
  -> PacketProcessor + ProxyOutbound + RuntimeProxyStack
  -> PacketFlowRuntimeIO.write(results)
  -> platform-specific PacketFlowIO.writePackets(results)
```

M22 tests should use `TunnelRuntimeBootstrap.shadowsocksTCP(...)` with `PacketFlowRuntimeIO` as both reader and writer. That proves the new boundary works with the full M21 runtime assembly instead of only testing the adapter in isolation.

## Error Handling

M22 does not add new error types.

- Read failures propagate from `PacketFlowIO.readPackets(limit:)` through `PacketTunnelRuntime.runOnce()`.
- Write failures propagate from `PacketFlowIO.writePackets(_:)` through `PacketTunnelRuntime.runOnce()`.
- Existing runtime failure reporting publishes the safe message `Packet batch failed` for non-protocol packet I/O failures.
- Reporter failures remain best-effort and must not mask packet-flow failures.
- Protocol and transport failures continue to use existing proxy error mapping.

The packet-flow adapter must not swallow errors or synthesize fallback packet results.

## Testing Strategy

Add `PacketFlowRuntimeIOTests` in `IrockTunnelCoreTests`.

Required tests:

1. `PacketFlowRuntimeIO.readBatch()` delegates to the flow with the configured batch limit.
2. `PacketFlowRuntimeIO.write(_:)` delegates processed results to the flow.
3. A bootstrapped Shadowsocks TCP runtime can use the same `PacketFlowRuntimeIO` value as reader and writer, process one proxy packet, connect through the plain transport child, and record one written result.
4. Read failure publishes failed runtime status/log output and propagates the original error.
5. Write failure publishes failed runtime status/log output and propagates the original error.

Full acceptance requires:

```bash
swift test --filter PacketFlowRuntimeIOTests
swift test --filter IrockTunnelCoreTests
swift test
grep -R "import Network\|import Security\|import NetworkExtension" -n packages/IrockTunnelCore packages/IrockProtocols packages/IrockTransport Package.swift || true
```

## Success Criteria

M22 is complete when:

- Future Packet Tunnel target code has a clear shared-package contract for packet-flow ingress and egress.
- `IrockTunnelCore` can adapt any `PacketFlowIO` implementation into existing `PacketReader` and `PacketWriter` protocols without changing `PacketTunnelRuntime`.
- Tests prove the adapter works with `TunnelRuntimeBootstrap`, not just as a standalone wrapper.
- Packet-flow read/write failures remain visible through existing safe runtime status and log reporting.
- No platform networking frameworks, Xcode targets, signing settings, or live VPN behavior are introduced.
- `swift test` passes.
