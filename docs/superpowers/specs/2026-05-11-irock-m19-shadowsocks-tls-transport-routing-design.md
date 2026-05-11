# irock M19 Shadowsocks TLS Transport Routing Design

Date: 2026-05-11

## Goal

M19 proves that the existing Shadowsocks protocol adapter can use the M18 TCP/TLS transport selector to route TLS-enabled Shadowsocks nodes to the TLS child transport path while routing TLS-disabled nodes to plain TCP, without adding Shadowsocks encryption, real TLS, or real network I/O.

M15 created `ShadowsocksProxyAdapter`. M17/M18 created the transport-layer TLS wrapper and TCP/TLS selector. M19 connects those pieces through tests and small helper refinements only if needed.

## Scope

In scope:

- Add protocol-layer tests in `IrockProtocolsTests` showing `ShadowsocksProxyAdapter` with a `TransportAdapterRegistry` containing `TCPTLSTransportAdapter`:
  - Routes TLS-enabled Shadowsocks TCP nodes to the selector TLS child.
  - Routes TLS-disabled Shadowsocks TCP nodes to the selector plain child.
  - Maps TLS child `TransportError.tlsHandshakeFailed` to `.tlsHandshakeFailed("transport tls handshake failed")`.
  - Maps plain child `TransportError.tcpConnectFailed` to `.tcpConnectFailed("transport tcp connect failed")`.
- Preserve existing `TransportBackedProxyAdapter` metadata behavior: `proxyProtocol`, `destination`, and caller metadata remain present on forwarded requests.
- Keep all behavior deterministic with recording/failing test adapters.

Out of scope:

- Real Shadowsocks handshake, AEAD encryption, credential loading, stream forwarding, or UDP.
- Real TCP sockets, TLS handshakes, certificate validation, ALPN, Reality, or Network/Security framework imports.
- Changing `ShadowsocksProxyAdapter` public API unless tests expose a bug.
- Tunnel runtime integration.
- App UI changes.

## Current Context

Current flow for a Shadowsocks node is:

```text
ShadowsocksProxyAdapter.connect(request)
  -> validate Shadowsocks node shape
  -> TransportBackedProxyAdapter.connect(request)
      -> build TransportRequest(host, port, .tcp, tls if enabled, metadata)
      -> transportRegistry.adapter(for: .tcp).open(request)
      -> map TransportError to ProxyProtocolError
```

After M18, the registered `.tcp` adapter can be:

```text
TCPTLSTransportAdapter(plain: plainChild, tls: tlsChild)
```

M19 verifies the protocol layer and selector layer compose correctly without adding production networking.

## Test Fixtures

Existing `IrockProtocolsTests` already has:

- `RecordingTransportAdapter` that records `TransportRequest` values.
- `FailingTransportAdapter` that throws a configured `TransportError`.
- `makeNode(...)` helper with configurable TLS.

M19 can use these directly with `TCPTLSTransportAdapter` from `IrockTransport`.

## Error Handling

No new protocol errors are added.

`TransportBackedProxyAdapter.proxyProtocolError(for:)` already maps:

- `.tlsHandshakeFailed` -> `.tlsHandshakeFailed("transport tls handshake failed")`
- `.tcpConnectFailed` -> `.tcpConnectFailed("transport tcp connect failed")`

M19 locks these mappings in the Shadowsocks + selector path specifically.

## Testing Strategy

Add SwiftPM tests in `IrockProtocolsTests` for:

- TLS-enabled Shadowsocks TCP node routes to selector TLS child and records a TLS-bearing transport request.
- TLS-disabled Shadowsocks TCP node routes to selector plain child and records a request with `tls == nil`.
- TLS child failure maps to Shadowsocks caller as `.tlsHandshakeFailed("transport tls handshake failed")`.
- Plain child failure maps to Shadowsocks caller as `.tcpConnectFailed("transport tcp connect failed")`.

Full acceptance requires:

```bash
swift test --filter IrockProtocolsTests
swift test --filter IrockTransportTests
swift test --filter IrockTunnelCoreTests
swift test
grep -R "import Network\|import Security" -n packages/IrockProtocols packages/IrockTransport Package.swift || true
```

## Success Criteria

M19 is complete when:

- Shadowsocks protocol tests prove TLS-enabled nodes reach the TLS child through the M18 selector.
- Shadowsocks protocol tests prove TLS-disabled nodes reach the plain child through the M18 selector.
- Transport child failures still map to protocol-layer errors.
- No real network, TLS, protocol handshake, tunnel, or UI behavior is added.
- `swift test` passes.
