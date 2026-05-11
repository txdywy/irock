# irock M18 TCP/TLS Transport Selection Design

Date: 2026-05-11

## Goal

M18 adds a TCP transport selection adapter that routes a `.tcp` `TransportRequest` to either a plain TCP adapter or a TLS wrapper adapter based on `request.tls`, without changing `TransportType` or introducing real network/TLS behavior.

M16 introduced `TCPTransportAdapter`, which intentionally rejects TLS. M17 introduced `TLSTransportAdapter`, which also reports `.tcp` because TLS is modeled as an option on a transport request. Since `TransportAdapterRegistry` indexes by `TransportType`, registering both directly would make one overwrite the other. M18 provides the missing composition point: one `.tcp` adapter that owns the plain-vs-TLS decision.

## Scope

In scope:

- Add `TCPTLSTransportAdapter<Plain, TLS>` in `IrockTransport`.
- Report `supportedTransport == .tcp`.
- Accept only `request.transport == .tcp`.
- Route requests with `request.tls?.enabled == true` to the injected TLS adapter.
- Route requests with `request.tls == nil` or `request.tls?.enabled == false` to the injected plain adapter.
- Preserve the original `TransportRequest` when forwarding so the selected child adapter performs its own validation.
- Propagate child `TransportError` unchanged.
- Cover plain routing, TLS routing, disabled-TLS routing, non-TCP rejection, child error propagation, and registry selection with SwiftPM tests.

Out of scope:

- Real sockets, DNS, TLS, ALPN, certificate validation, stream wrapping, or packet forwarding.
- Changing `TransportType` to add `.tls`.
- Changing `TransportAdapterRegistry` indexing semantics.
- Protocol adapter changes.
- Tunnel runtime changes.
- App UI changes.

## Current Context

Transport milestones currently compose like this:

```text
M13 TransportAdapterRegistry.adapter(for: .tcp)
M16 TCPTransportAdapter.open(plain TCP only)
M17 TLSTransportAdapter.open(TLS-bearing TCP only, delegates to underlying plain adapter)
```

The registry can only hold one adapter per `TransportType`, so callers need a single registered `.tcp` adapter:

```text
TransportAdapterRegistry([TCPTLSTransportAdapter])
  -> TCPTLSTransportAdapter.open(request)
      -> if tls.enabled: tls.open(request)
      -> else: plain.open(request)
```

## Component

### TCPTLSTransportAdapter

Public shape:

```swift
public struct TCPTLSTransportAdapter<Plain: TransportAdapter, TLS: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp

    public init(plain: Plain, tls: TLS)
    public func open(request: TransportRequest) async throws -> any TransportConnection
}
```

`Plain` is expected to be a plain `.tcp` adapter such as `TCPTransportAdapter`. `TLS` is expected to be a `.tcp` TLS wrapper such as `TLSTransportAdapter`. M18 does not enforce child `supportedTransport` at init time because that would add runtime validation not needed by the current call path; request routing remains deterministic and tested.

## Routing Rules

Before routing:

1. If `request.transport != .tcp`, throw `.unsupportedTransport(request.transport)`.
2. If `request.tls?.enabled == true`, call `tls.open(request: request)`.
3. Otherwise, call `plain.open(request: request)`.

The adapter does not trim host, validate port, strip TLS, or inspect Reality. Those responsibilities remain in the selected child adapter:

- Plain TCP validation stays in `TCPTransportAdapter`.
- TLS structural validation and TLS stripping stay in `TLSTransportAdapter`.

## Error Handling

All failures remain `TransportError` values.

The selector itself only creates `.unsupportedTransport` for non-TCP requests. Child adapter errors are rethrown unchanged, preserving existing M14 transport-to-protocol mapping and avoiding duplicate error semantics.

## Testing Strategy

Add SwiftPM tests in `IrockTransportTests` for:

- `TCPTLSTransportAdapter.supportedTransport == .tcp`.
- Plain TCP request calls the plain child and not the TLS child.
- TLS-enabled request calls the TLS child and not the plain child.
- TLS-disabled request calls the plain child and not the TLS child.
- Non-TCP request fails before either child is called.
- Plain child `TransportError.tcpConnectFailed` propagates unchanged.
- TLS child `TransportError.tlsHandshakeFailed` propagates unchanged.
- `TransportAdapterRegistry` can register and select `TCPTLSTransportAdapter` for `.tcp`.

Full acceptance requires:

```bash
swift test --filter IrockTransportTests
swift test --filter IrockProtocolsTests
swift test --filter IrockTunnelCoreTests
swift test
grep -R "import IrockTunnelCore\|import IrockStorage\|import IrockAppFeature\|import Network\|import Security" -n packages/IrockTransport Package.swift || true
```

## Success Criteria

M18 is complete when:

- `IrockTransport` exposes a single `.tcp` selector adapter for plain-vs-TLS transport requests.
- The selector preserves request payloads and delegates validation to child adapters.
- Child transport errors propagate unchanged.
- Registry lookup can select the selector as the registered `.tcp` adapter.
- No real network, TLS, security framework, protocol, tunnel, or UI behavior is added.
- `swift test` passes.
