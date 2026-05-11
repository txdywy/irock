# irock M16 TCP Transport Foundation Design

Date: 2026-05-11

## Goal

M16 adds the first transport-specific adapter skeleton: `TCPTransportAdapter`.

This milestone does not perform real socket dialing, DNS resolution, TLS negotiation, stream reads/writes, proxy protocol handshakes, or packet forwarding. It establishes a testable TCP transport adapter boundary with structural request validation, an injectable dialer abstraction, and deterministic transport errors.

## Scope

In scope:

- Add `TCPTransportAdapter` in `IrockTransport`.
- Ensure it reports `supportedTransport == .tcp`.
- Validate `TransportRequest` before dialing:
  - `transport == .tcp`.
  - `host` is not empty after trimming whitespace.
  - `port` is in `1...65535`.
  - `tls == nil`; TLS wrapping belongs to a later TLS transport milestone.
- Add a lightweight `TCPDialer` protocol so tests can verify dialing behavior without real network access.
- Add a `TCPDialResult` value returned by the dialer.
- Return `EstablishedTransportConnection` when the dialer succeeds.
- Map dialer failures to existing `TransportError` cases.
- Cover success, unsupported transport, invalid host, invalid port, TLS rejection, and dialer failure behavior with SwiftPM tests.

Out of scope:

- `Network.framework`, `NWConnection`, BSD sockets, or any real network I/O.
- DNS resolution.
- TLS wrapping or ALPN.
- WebSocket, HTTP/2, gRPC, QUIC.
- Stream APIs.
- Connection pooling or lifecycle management.
- Protocol adapter changes.
- Tunnel runtime changes.

## Current Context

M13 established generic transport contracts:

```text
TransportRequest(host, port, transport, tls, metadata)
TransportConnection
EstablishedTransportConnection
TransportError
TransportAdapter
TransportAdapterRegistry
```

M16 adds the first transport-specific implementation shape:

```text
TCPTransportAdapter.open(request)
  -> validate request is plain TCP
  -> call injected TCPDialer.open(host, port)
  -> return EstablishedTransportConnection(host, port, .tcp)
```

The injected dialer keeps this milestone deterministic and testable. Later milestones can provide a `Network.framework` dialer behind the same interface.

## Components

### TCPDialResult

```swift
public struct TCPDialResult: Equatable, Sendable {
    public let host: String
    public let port: Int
}
```

This is intentionally minimal. It records the endpoint the dialer accepted; it does not expose sockets or streams.

### TCPDialer

```swift
public protocol TCPDialer: Sendable {
    func open(host: String, port: Int) async throws -> TCPDialResult
}
```

M16 tests use recording/failing dialers. No production real network dialer is added in this milestone.

### TCPTransportAdapter

```swift
public struct TCPTransportAdapter<Dialer: TCPDialer>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp

    public init(dialer: Dialer)
    public func open(request: TransportRequest) async throws -> any TransportConnection
}
```

Behavior:

- Reject non-TCP requests with `.unsupportedTransport(request.transport)`.
- Reject empty host with `.invalidConfiguration("missing tcp host")`.
- Reject invalid port with `.invalidConfiguration("invalid tcp port")`.
- Reject TLS options with `.unsupportedTransport(.tcp)` for M16 because TLS is a separate transport layer milestone.
- Call `dialer.open(host: request.host, port: request.port)` after validation.
- Return `EstablishedTransportConnection(host: result.host, port: result.port, transport: .tcp)`.
- If the dialer throws `TransportError`, rethrow it unchanged.

## Error Handling

All failures remain typed `TransportError` values.

The adapter never embeds raw credential material in errors. Structural validation messages are fixed strings, and `TransportError.description` already redacts associated reason strings except for enumerated transport type.

## Testing Strategy

Add SwiftPM tests in `IrockTransportTests` for:

- `TCPTransportAdapter.supportedTransport == .tcp`.
- Valid TCP request calls the dialer and returns an established TCP connection.
- Dialer receives trimmed host and port as requested.
- Non-TCP request fails with `.unsupportedTransport` before dialing.
- Empty host fails with `.invalidConfiguration("missing tcp host")` before dialing.
- Port `0` and `65536` fail with `.invalidConfiguration("invalid tcp port")` before dialing.
- TLS-enabled request fails before dialing.
- Dialer `TransportError.tcpConnectFailed` propagates unchanged.
- `TransportAdapterRegistry` can register and select `TCPTransportAdapter`.

Full acceptance requires:

```bash
swift test --filter IrockTransportTests
swift test
```

## Success Criteria

M16 is complete when:

- `IrockTransport` exposes a TCP-specific adapter skeleton.
- TCP request validation is deterministic and tested.
- Dialing is injectable and no real network I/O is introduced.
- Dialer errors propagate as `TransportError`.
- Registry lookup can select the TCP adapter.
- No TLS, DNS, stream, proxy protocol, tunnel, or UI behavior is added.
- `swift test` passes.
