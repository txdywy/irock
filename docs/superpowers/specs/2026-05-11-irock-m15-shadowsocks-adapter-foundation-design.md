# irock M15 Shadowsocks Adapter Foundation Design

Date: 2026-05-11

## Goal

M15 adds the first protocol-specific adapter skeleton: `ShadowsocksProxyAdapter`.

This milestone does not implement Shadowsocks encryption, AEAD methods, stream framing, TCP forwarding, UDP association, credential lookup, SIP002 parsing, or real proxy handshakes. It validates that a selected node is structurally suitable for a future Shadowsocks implementation, delegates transport opening to the M14 transport-backed adapter path, and returns a proxy connection through the existing protocol boundary.

## Scope

In scope:

- Add `ShadowsocksProxyAdapter` in `IrockProtocols`.
- Ensure it reports `supportedProtocol == .shadowsocks`.
- Validate the request node uses `.shadowsocks` before opening transport.
- Validate Shadowsocks Alpha configuration shape:
  - `serverHost` is not empty after trimming whitespace.
  - `serverPort` is in `1...65535`.
  - `credentialReference.account` is not empty after trimming whitespace.
  - `transport` is `.tcp` for M15.
- Delegate successful connection setup to `TransportBackedProxyAdapter` using an injected `TransportAdapterRegistry`.
- Preserve protocol-layer error semantics with `ProxyProtocolError`.
- Cover success, protocol mismatch, invalid host, invalid port, missing credential account, unsupported transport, and transport error propagation in tests.

Out of scope:

- Reading credentials from Keychain.
- Validating Shadowsocks method names or passwords.
- Encrypting or decrypting traffic.
- TCP stream read/write APIs.
- UDP support.
- SIP002 plugin support.
- URI import changes.
- Tunnel runtime changes.
- App UI changes.

## Current Context

M11 created generic protocol adapter contracts.
M13 created generic transport adapter contracts.
M14 connected generic protocol adapters to transport opening.

M15 adds the first protocol-specific layer:

```text
ShadowsocksProxyAdapter.connect(request)
  -> validate request.node.protocolType == .shadowsocks
  -> validate Shadowsocks Alpha config shape
  -> require TCP transport for now
  -> delegate to TransportBackedProxyAdapter(.shadowsocks)
  -> return EstablishedProxyConnection
```

## Component

### ShadowsocksProxyAdapter

Public shape:

```swift
public struct ShadowsocksProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .shadowsocks

    public init(transportRegistry: TransportAdapterRegistry)
    public func connect(request: ProxyRequest) async throws -> any ProxyConnection
}
```

The adapter owns only Shadowsocks-specific validation and composition. It does not know how to open sockets directly; it uses `TransportBackedProxyAdapter` so protocol-specific adapters all share the same transport boundary.

## Validation Rules

Before opening transport:

1. If `request.node.protocolType != .shadowsocks`, throw `.unsupportedProtocol(request.node.protocolType)`.
2. If `serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`, throw `.invalidConfiguration("missing shadowsocks server host")`.
3. If `serverPort` is outside `1...65535`, throw `.invalidConfiguration("invalid shadowsocks server port")`.
4. If `credentialReference.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`, throw `.invalidConfiguration("missing shadowsocks credential account")`.
5. If `transport != .tcp`, throw `.unsupportedTransport(request.node.transport)`.

These checks are intentionally structural. M15 cannot validate method/password because credentials are referenced, not loaded.

## Error Handling

All errors remain `ProxyProtocolError` values:

- Protocol mismatch: `.unsupportedProtocol(actual)`.
- Invalid structural config: `.invalidConfiguration(...)`.
- Non-TCP transport: `.unsupportedTransport(transport)`.
- Transport open failures: delegated M14 transport-to-protocol mapping.

No raw credential values are included in error descriptions.

## Testing Strategy

Add SwiftPM tests in `IrockProtocolsTests` for:

- `ShadowsocksProxyAdapter.supportedProtocol == .shadowsocks`.
- Valid Shadowsocks TCP node opens transport and returns a proxy connection.
- Transport request uses node server host, port, transport, TLS, and metadata from `ProxyRequest`.
- Protocol mismatch fails before transport invocation.
- Empty server host fails before transport invocation.
- Invalid port fails before transport invocation.
- Empty credential account fails before transport invocation.
- Non-TCP transport fails with `.unsupportedTransport` before transport invocation.
- Transport failures propagate as mapped `ProxyProtocolError` values through the delegated M14 path.

Full acceptance requires:

```bash
swift test --filter IrockProtocolsTests
swift test
```

## Success Criteria

M15 is complete when:

- `IrockProtocols` exposes a Shadowsocks-specific adapter skeleton.
- The adapter validates Shadowsocks Alpha node shape before transport opening.
- The adapter delegates transport opening through M14 rather than duplicating transport logic.
- Unsupported and invalid configurations fail deterministically with protocol-layer errors.
- No real Shadowsocks cryptography, credential loading, stream forwarding, UDP, plugin, tunnel, or UI behavior is added.
- `swift test` passes.
