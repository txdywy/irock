# irock M12 Tunnel Protocol Bridge Design

Date: 2026-05-11

## Goal

M12 connects tunnel proxy routing decisions to the protocol adapter foundation without implementing real proxy handshakes, encryption, stream forwarding, or packet response synthesis.

The milestone turns a `.proxy` packet-processing result into a deterministic protocol adapter attempt using the selected runtime node and destination. Adapter failures are surfaced through the existing runtime status/log feedback path.

## Scope

In scope:

- Add an `IrockTunnelCore` dependency on `IrockProtocols`.
- Define a tunnel-side `ProxyOutbound` component that builds `ProxyRequest` values from proxied packet results.
- Map parsed packet destinations to `ProxyDestination.ipv4` or `.ipv6`.
- Inject a `ProxyAdapterRegistry` into `PacketTunnelRuntime` through `TunnelRuntimeConfiguration`.
- Attempt protocol adapter connections for `.proxy` results after packet processing and before packet writing.
- Record attempted proxy connection count in `PacketTunnelRuntimeSummary`.
- Publish failed runtime status and a user log when a proxy adapter throws.
- Keep direct/reject/drop packet behavior unchanged.
- Cover request construction, adapter invocation, unsupported failure, and reporter best-effort behavior with SwiftPM tests.

Out of scope:

- Real Shadowsocks, Trojan, VMess, VLESS, Hysteria2, or TUIC protocol behavior.
- TCP socket creation, stream reads/writes, UDP association, or packet response generation.
- DNS resolution or hostname recovery from IP packets.
- Connection pooling or flow lifecycle management.
- App UI changes.

## Current Context

M11 added these protocol-layer contracts:

```text
ProxyDestination
ProxyRequest
ProxyConnection
ProxyAdapter
UnsupportedProxyAdapter
ProxyAdapterRegistry
```

`IrockTunnelCore` currently stops at routing decisions:

```text
Packet batch
  -> PacketProcessor
  -> PacketProcessingResult(action: .direct/.proxy/.reject/.drop)
  -> PacketWriter
```

M12 adds the next seam:

```text
Packet batch
  -> PacketProcessor
  -> .proxy result with ParsedPacket
  -> ProxyOutbound.connect(result:)
  -> ProxyAdapterRegistry.adapter(for: selectedNode.protocolType)
  -> ProxyAdapter.connect(request:)
```

## Components

### ProxyOutbound

`ProxyOutbound` lives in `IrockTunnelCore` and owns only the bridge from packet-processing output to protocol adapter input.

It depends on:

- `ProxyNode` from the immutable `RuntimeSnapshot`.
- `ProxyAdapterRegistry` from runtime configuration.
- `PacketProcessingResult` with a parsed packet.

It exposes:

```swift
public struct ProxyOutbound: Sendable {
    public init(node: ProxyNode, registry: ProxyAdapterRegistry)
    public func connect(result: PacketProcessingResult) async throws -> any ProxyConnection?
}
```

Behavior:

- For `.proxy` results with a parsed IPv4 packet, build `.ipv4(packet.destinationIP.stringValue, port: packet.destinationPort)`.
- For `.proxy` results with a parsed IPv6 packet, build `.ipv6(packet.destinationIP.stringValue, port: packet.destinationPort)`.
- Include metadata `packetID` and `transportProtocol` so later protocol implementations can receive basic debug hints.
- Return `nil` for non-proxy actions or malformed proxy results without a parsed packet.
- Select the adapter using `registry.adapter(for: node.protocolType)`.
- Call `adapter.connect(request:)` and return the connection.

### TunnelRuntimeConfiguration

`TunnelRuntimeConfiguration` gains:

```swift
public let proxyAdapterRegistry: ProxyAdapterRegistry
```

Existing initializers default to `ProxyAdapterRegistry(adapters: [])`, preserving deterministic unsupported behavior without requiring call sites to register adapters.

### PacketTunnelRuntime

`PacketTunnelRuntime.runOnce()` processes packets as before, then attempts proxy outbound connections before writing results.

Summary gains:

```swift
public let proxyConnectCount: Int
```

A proxy adapter failure marks the run as failed:

- Status phase: `.failed`
- Status message: `Proxy adapter failed: <safe description>`
- Log message: `Proxy adapter failed: <safe description>`
- Error thrown to caller: original adapter error

Reporter writes remain best-effort. Reporter failures must not mask adapter failures.

## Error Handling

Unsupported or missing adapters are not hidden. The default empty registry returns `UnsupportedProxyAdapter`, which throws `ProxyProtocolError.unsupportedProtocol(selectedNode.protocolType)`.

`PacketTunnelRuntime` uses `CustomStringConvertible.description` for safe user-facing protocol errors. M11 redaction behavior means raw reason strings from credential-like protocol errors are not emitted.

## Testing Strategy

Add SwiftPM tests for:

- `ProxyOutbound` builds an IPv4 `ProxyRequest` from a proxied packet result.
- `ProxyOutbound` returns `nil` for direct/reject/drop results.
- `PacketTunnelRuntime` invokes a registered adapter for proxied packets and reports `proxyConnectCount`.
- Empty registry causes unsupported adapter failure for proxy traffic.
- Proxy adapter failure publishes failed status/log even when packet processing succeeded.
- Reporter failures remain best-effort and do not hide successful adapter invocation.

Full acceptance requires:

```bash
swift test --filter IrockTunnelCoreTests
swift test
```

## Success Criteria

M12 is complete when:

- Tunnel proxy routing decisions invoke the protocol adapter boundary.
- Runtime failures from unsupported protocol adapters are deterministic and visible through runtime feedback.
- Existing direct/reject/drop packet behavior remains unchanged.
- No real protocol handshake, socket, stream, encryption, DNS, or packet response synthesis is introduced.
- `swift test` passes.
