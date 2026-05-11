# irock M20 Runtime Proxy Stack Assembly Design

Date: 2026-05-11

## Goal

M20 adds a deterministic runtime proxy stack assembly boundary that composes the existing tunnel, protocol, and transport seams into one injectable structure for future app and Packet Tunnel shells.

M12 proved `PacketTunnelRuntime` can call `ProxyAdapterRegistry`. M15-M19 proved Shadowsocks can bridge to TCP/TLS transport selection. M20 connects those pieces through a small factory so callers do not manually assemble nested registries for the common Shadowsocks-over-TCP/TLS path.

## Scope

In scope:

- Add a SwiftPM-testable assembly type in `IrockTunnelCore` that builds a `ProxyAdapterRegistry` from an injected TCP/TLS transport selector.
- Register `ShadowsocksProxyAdapter` as the supported protocol adapter for the assembled stack.
- Keep plain and TLS transport behavior injectable through `TransportAdapter` children.
- Provide a convenience runtime configuration helper that returns `TunnelRuntimeConfiguration` with the assembled proxy registry.
- Cover tunnel-to-protocol-to-transport composition with deterministic recording/failing test adapters.
- Preserve existing unsupported-protocol and UDP policy behavior.

Out of scope:

- Real TCP sockets, DNS, TLS handshakes, certificate validation, or `Network` / `Security` framework imports.
- Shadowsocks encryption, credential loading, stream forwarding, UDP association, or packet response synthesis.
- Xcode workspace, app targets, Packet Tunnel extension targets, App Groups, signing, or entitlement setup.
- Adding VMess, VLESS, Trojan, Hysteria2, TUIC, or Reality protocol behavior.
- Connection pooling, flow lifecycle management, retry policies, or observability beyond existing runtime summary/status/log behavior.

## Current Context

The latest runtime path is split across three package layers:

```text
PacketTunnelRuntime
  -> PacketProcessor
  -> ProxyOutbound
  -> ProxyAdapterRegistry
  -> ShadowsocksProxyAdapter
  -> TransportBackedProxyAdapter
  -> TransportAdapterRegistry
  -> TCPTLSTransportAdapter
  -> plain or TLS child TransportAdapter
```

Today tests can wire this manually, but production-facing callers would need to know too much about protocol and transport internals. The next safe step is an assembly boundary that encodes the default composition without adding real networking.

## Component Design

### RuntimeProxyStack

`RuntimeProxyStack` lives in `IrockTunnelCore` because `TunnelRuntimeConfiguration` is where the assembled `ProxyAdapterRegistry` is consumed.

It exposes a static factory:

```swift
public struct RuntimeProxyStack: Sendable {
    public static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        plain: Plain,
        tls: TLS
    ) -> ProxyAdapterRegistry
}
```

Behavior:

- Create `TCPTLSTransportAdapter(plain: plain, tls: tls)`.
- Create `TransportAdapterRegistry(adapters: [selector])`.
- Create `ShadowsocksProxyAdapter(transportRegistry: transportRegistry)`.
- Return `ProxyAdapterRegistry(adapters: [shadowsocksAdapter])`.

This keeps protocol registration explicit and deterministic while hiding nested registry construction from tunnel/app shells.

### TunnelRuntimeConfiguration helper

Add a focused helper for call sites that want a complete tunnel runtime configuration with the assembled stack:

```swift
public extension TunnelRuntimeConfiguration {
    static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        routingEngine: any RoutingEngine,
        packetWriter: any PacketWriter,
        plain: Plain,
        tls: TLS,
        statusReporter: (any RuntimeStatusReporting)? = nil,
        logReporter: (any RuntimeLogReporting)? = nil
    ) -> TunnelRuntimeConfiguration
}
```

Behavior:

- Build the proxy registry using `RuntimeProxyStack.shadowsocksTCP(plain:tls:)`.
- Return `TunnelRuntimeConfiguration` with existing dependencies unchanged.
- Pass optional reporters through to the existing initializer.

If the existing `TunnelRuntimeConfiguration` initializer shape differs, the implementation should match the current public initializer rather than adding duplicate state.

## Data Flow

TLS-enabled Shadowsocks node:

```text
PacketTunnelRuntime.runOnce()
  -> ProxyOutbound.connect(result:)
  -> ShadowsocksProxyAdapter.connect(request:)
  -> TransportBackedProxyAdapter builds TransportRequest(tls: TLSOptions)
  -> TCPTLSTransportAdapter routes to TLS child
```

TLS-disabled Shadowsocks node:

```text
PacketTunnelRuntime.runOnce()
  -> ProxyOutbound.connect(result:)
  -> ShadowsocksProxyAdapter.connect(request:)
  -> TransportBackedProxyAdapter builds TransportRequest(tls: nil)
  -> TCPTLSTransportAdapter routes to plain child
```

The tunnel layer remains unaware of TLS routing details; it only receives an assembled `ProxyAdapterRegistry`.

## Error Handling

M20 does not introduce new error types.

- Unsupported protocol behavior continues to come from `ProxyAdapterRegistry` and `UnsupportedProxyAdapter` when callers use an empty or custom registry without a matching adapter.
- Transport errors continue to be mapped by `TransportBackedProxyAdapter` into `ProxyProtocolError`.
- `PacketTunnelRuntime` continues to publish failed status/log entries when proxy adapter calls throw.
- Reporter failures remain best-effort and must not mask successful proxy attempts or underlying adapter failures.

## Testing Strategy

Add SwiftPM tests in `IrockTunnelCoreTests` using deterministic transport adapters:

- `RuntimeProxyStack.shadowsocksTCP` routes a TLS-enabled Shadowsocks proxy packet through the TLS transport child.
- `RuntimeProxyStack.shadowsocksTCP` routes a TLS-disabled Shadowsocks proxy packet through the plain transport child.
- `TunnelRuntimeConfiguration.shadowsocksTCP(...)` wires the assembled registry into `PacketTunnelRuntime` and increments `proxyConnectCount` for proxy traffic.
- A failing TLS child maps through the protocol layer and causes `PacketTunnelRuntime` to publish failed status/log output.
- Existing empty-registry unsupported behavior remains covered by current M12 tests and should not be changed.

Full acceptance requires:

```bash
swift test --filter IrockTunnelCoreTests
swift test --filter IrockProtocolsTests
swift test --filter IrockTransportTests
swift test
grep -R "import Network\|import Security" -n packages/IrockTunnelCore packages/IrockProtocols packages/IrockTransport Package.swift || true
```

## Success Criteria

M20 is complete when:

- Future tunnel/app shell code can obtain the default Shadowsocks TCP/TLS proxy registry through one assembly function.
- Tunnel runtime tests prove the assembled stack reaches the correct transport child for TLS-enabled and TLS-disabled Shadowsocks nodes.
- Runtime failure behavior remains deterministic and visible through existing status/log feedback.
- No real network, TLS, protocol handshake, stream forwarding, Xcode target, or entitlement behavior is added.
- `swift test` passes.
