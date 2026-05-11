# irock M17 TLS Transport Foundation Design

Date: 2026-05-11

## Goal

M17 adds a TLS transport adapter skeleton that validates TLS options and composes with an injected underlying transport adapter without performing real TLS handshakes, socket I/O, certificate validation, ALPN negotiation, or stream wrapping.

The milestone exists because M14 already forwards node TLS configuration into `TransportRequest`, M15 can build Shadowsocks requests with TLS-enabled nodes, and M16 intentionally rejects TLS in the plain TCP adapter. M17 provides the next transport-layer seam: a deterministic TLS wrapper that can sit in front of TCP today and later be backed by a real TLS implementation.

## Scope

In scope:

- Add `TLSTransportAdapter` in `IrockTransport`.
- Report `supportedTransport == .tcp` because TLS is an option over an underlying transport, not a separate `TransportType` in `IrockCore`.
- Accept only requests where:
  - `transport == .tcp`.
  - `tls` exists and `tls.enabled == true`.
  - `host` is not empty after trimming whitespace.
  - `port` is in `1...65535`.
  - `tls.serverName`, when present, is not empty after trimming whitespace.
  - `tls.reality == nil` because Reality is a later protocol-specific TLS variant.
- Open the injected underlying adapter with a sanitized plain transport request: same host/port/transport/metadata, but `tls == nil`.
- Return an `EstablishedTransportConnection` whose endpoint comes from the underlying connection and whose transport remains `.tcp`.
- Propagate `TransportError` from the underlying adapter unchanged.
- Cover validation, underlying request construction, error propagation, and registry selection with SwiftPM tests.

Out of scope:

- Real TLS, trust evaluation, SNI handling, certificate pinning, fingerprints, ALPN negotiation, or stream wrapping.
- `Network.framework`, `NWConnection`, `Security.framework`, or socket APIs.
- Reality TLS behavior.
- WebSocket, HTTP/2, gRPC, or QUIC transport behavior.
- Protocol adapter changes.
- Tunnel runtime changes.
- App UI changes.

## Current Context

M13 established generic transport contracts. M14 forwards `ProxyRequest.node.tls` into `TransportRequest.tls` when TLS is enabled. M15 creates Shadowsocks-specific requests through that path. M16 adds a plain `TCPTransportAdapter` and rejects TLS-bearing requests so plain TCP remains explicit.

M17 adds a composition layer:

```text
TLSTransportAdapter.open(request with tls enabled)
  -> validate TCP + TLS option shape
  -> build underlying TransportRequest(tls: nil)
  -> underlying.open(request: plain request)
  -> return EstablishedTransportConnection(..., .tcp)
```

This keeps TLS opt-in and testable without pretending real encryption exists.

## Component

### TLSTransportAdapter

Public shape:

```swift
public struct TLSTransportAdapter<Underlying: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp

    public init(underlying: Underlying)
    public func open(request: TransportRequest) async throws -> any TransportConnection
}
```

The adapter is generic over the underlying transport so tests can inject recording/failing adapters and future production code can inject a plain TCP adapter or other compatible transport adapter.

## Validation Rules

Before opening the underlying adapter:

1. If `request.transport != .tcp`, throw `.unsupportedTransport(request.transport)`.
2. If `request.tls == nil` or `request.tls?.enabled != true`, throw `.invalidConfiguration("missing tls options")`.
3. If `request.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`, throw `.invalidConfiguration("missing tls host")`.
4. If `request.port` is outside `1...65_535`, throw `.invalidConfiguration("invalid tls port")`.
5. If `tls.serverName` exists but trims to empty, throw `.invalidConfiguration("invalid tls server name")`.
6. If `tls.reality != nil`, throw `.unsupportedTransport(.tcp)` for M17.

`allowInsecure`, `alpn`, and `fingerprint` are accepted as structural values but not acted on until a real TLS implementation exists.

## Error Handling

All failures remain `TransportError` values.

Validation uses fixed strings and never embeds hostnames, SNI, fingerprints, or credential-like values into error descriptions. Underlying transport errors are rethrown unchanged so callers can preserve existing M14 transport-to-protocol mapping behavior.

## Testing Strategy

Add SwiftPM tests in `IrockTransportTests` for:

- `TLSTransportAdapter.supportedTransport == .tcp`.
- Valid TLS-over-TCP request opens the underlying adapter and returns a TCP connection.
- Underlying request receives trimmed host, same port, `.tcp`, copied metadata, and `tls == nil`.
- Non-TCP request fails before underlying invocation.
- Missing or disabled TLS fails before underlying invocation.
- Empty host fails before underlying invocation.
- Invalid port fails before underlying invocation.
- Empty server name fails before underlying invocation.
- Reality options fail before underlying invocation.
- Underlying `TransportError.tlsHandshakeFailed` propagates unchanged.
- `TransportAdapterRegistry` can register and select `TLSTransportAdapter` for `.tcp`.

Full acceptance requires:

```bash
swift test --filter IrockTransportTests
swift test --filter IrockProtocolsTests
swift test --filter IrockTunnelCoreTests
swift test
grep -R "import IrockTunnelCore\|import IrockStorage\|import IrockAppFeature\|import Network\|import Security" -n packages/IrockTransport Package.swift || true
```

## Success Criteria

M17 is complete when:

- `IrockTransport` exposes a TLS wrapper adapter skeleton.
- TLS request validation is deterministic and tested.
- The adapter strips TLS before delegating to the underlying plain transport boundary.
- No real TLS, network, security framework, stream, protocol, tunnel, or UI behavior is added.
- Registry lookup can select the TLS wrapper for `.tcp` when registered.
- `swift test` passes.
