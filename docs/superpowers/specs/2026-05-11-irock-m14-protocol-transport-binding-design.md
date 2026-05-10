# irock M14 Protocol Transport Binding Design

Date: 2026-05-11

## Goal

M14 adds the first protocol-layer adapter that uses the M13 transport registry before returning a proxy connection.

It still does not implement any real proxy protocol handshake, encryption, stream forwarding, UDP forwarding, or packet response synthesis. The milestone creates a testable bridge from `ProxyAdapter.connect(request:)` to `TransportAdapterRegistry.adapter(for:)` so future Shadowsocks/Trojan/VMess/VLESS adapters can share the same transport opening path.

## Scope

In scope:

- Add a protocol-layer adapter helper that builds `TransportRequest` from `ProxyRequest.node`.
- Inject a `TransportAdapterRegistry` into that adapter.
- Open the selected node transport before returning an established proxy connection.
- Preserve unsupported behavior when no transport adapter is registered.
- Map transport errors into `ProxyProtocolError` where needed so protocol callers receive protocol-layer errors.
- Add tests proving transport request construction, transport invocation, unsupported transport failure, and connection result modeling.

Out of scope:

- Real Shadowsocks/Trojan/VMess/VLESS/Hysteria2/TUIC protocol implementations.
- Real TCP, TLS, WebSocket, HTTP/2, gRPC, or QUIC networking.
- Stream read/write APIs.
- Credential loading or Keychain access.
- Tunnel runtime changes.
- App UI changes.

## Current Context

M11 created protocol adapter contracts:

```text
ProxyAdapterRegistry
ProxyAdapter.connect(request:)
ProxyRequest(node, destination, metadata)
ProxyConnection
ProxyProtocolError
```

M13 created transport adapter contracts:

```text
TransportAdapterRegistry
TransportAdapter.open(request:)
TransportRequest(host, port, transport, tls, metadata)
TransportConnection
TransportError
```

M14 connects these boundaries inside `IrockProtocols`:

```text
ProxyAdapter.connect(request)
  -> build TransportRequest from request.node
  -> transportRegistry.adapter(for: request.node.transport)
  -> transportAdapter.open(request:)
  -> EstablishedProxyConnection
```

## Component

### TransportBackedProxyAdapter

`TransportBackedProxyAdapter` is a protocol-layer adapter skeleton for future real protocol adapters. It supports one `ProxyProtocolType` and delegates transport opening to `TransportAdapterRegistry`.

Public shape:

```swift
public struct TransportBackedProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType

    public init(protocolType: ProxyProtocolType, transportRegistry: TransportAdapterRegistry)
    public func connect(request: ProxyRequest) async throws -> any ProxyConnection
}
```

Behavior:

- If `request.node.protocolType` does not match `supportedProtocol`, throw `.unsupportedProtocol(request.node.protocolType)`.
- Build `TransportRequest` with:
  - `host`: `request.node.serverHost`
  - `port`: `request.node.serverPort`
  - `transport`: `request.node.transport`
  - `tls`: `request.node.tls.enabled ? request.node.tls : nil`
  - metadata copied from `ProxyRequest.metadata`, plus `proxyProtocol` and `destination` string hints.
- Open transport through `transportRegistry.adapter(for: request.node.transport)`.
- Return `EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)` after transport opens.

The returned proxy connection does not expose the transport connection yet. M14 only verifies the dependency path and failure semantics.

## Error Mapping

Transport errors are translated into protocol-layer errors:

| TransportError | ProxyProtocolError |
|---|---|
| `.invalidConfiguration` | `.invalidConfiguration("transport invalid")` |
| `.dnsFailed` | `.dnsFailed("transport dns failed")` |
| `.tcpConnectFailed` | `.tcpConnectFailed("transport tcp connect failed")` |
| `.tlsHandshakeFailed` | `.tlsHandshakeFailed("transport tls handshake failed")` |
| `.unsupportedTransport(type)` | `.unsupportedTransport(type)` |
| `.quicHandshakeFailed` | `.quicHandshakeFailed("transport quic handshake failed")` |
| `.remoteClosed` | `.remoteClosed` |
| `.timeout` | `.timeout` |

Descriptions remain safe because `ProxyProtocolError.description` redacts sensitive reason strings for non-enumerated cases.

## Testing Strategy

Add SwiftPM tests in `IrockProtocolsTests` for:

- `TransportBackedProxyAdapter` opens the selected node transport and returns an established proxy connection.
- Transport request includes node server host, port, transport, TLS when enabled, and metadata hints.
- TLS is omitted when node TLS is disabled.
- Protocol mismatch fails with `.unsupportedProtocol(request.node.protocolType)` before opening transport.
- Missing transport adapter maps to `.unsupportedTransport(request.node.transport)`.
- Representative `TransportError` values map to protocol errors.

Full acceptance requires:

```bash
swift test --filter IrockProtocolsTests
swift test
```

## Success Criteria

M14 is complete when:

- `IrockProtocols` can open the transport boundary through `TransportAdapterRegistry` before returning a proxy connection.
- Protocol adapter callers receive `ProxyProtocolError`, not raw `TransportError`.
- Unsupported protocol and unsupported transport failures are deterministic.
- No real protocol handshake, socket, stream, encryption, credential lookup, tunnel, or app behavior is added.
- `swift test` passes.
