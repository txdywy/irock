# irock M13 Transport Adapter Foundation Design

Date: 2026-05-11

## Goal

M13 establishes a stable `IrockTransport` adapter foundation for future TCP, TLS, WebSocket, HTTP/2, gRPC, and QUIC implementations.

It does not implement real sockets, TLS handshakes, HTTP framing, gRPC streams, QUIC sessions, DNS resolution, proxy protocol handshakes, or packet forwarding. It replaces the current minimal placeholder transport API with request, connection, error, unsupported adapter, and registry contracts that protocol adapters can depend on in later milestones.

## Scope

In scope:

- Expand `TransportRequest` with host, port, transport type, optional TLS options, and string metadata.
- Define a minimal `TransportConnection` protocol and value type for established test connections.
- Define `TransportError` with Alpha transport failure cases and stable safe descriptions.
- Define a `TransportAdapter` protocol with `supportedTransport` and async `open(request:)`.
- Provide `UnsupportedTransportAdapter` that throws `.unsupportedTransport(request.transport)` deterministically.
- Preserve `NoopTransportAdapter` as an unsupported compatibility alias.
- Add `TransportAdapterRegistry` with last-wins registration and unsupported fallback.
- Cover request modeling, connection modeling, error descriptions, unsupported behavior, and registry lookup with SwiftPM tests.

Out of scope:

- Real `Network.framework`, `NWConnection`, socket, TLS, HTTP/2, gRPC, or QUIC implementation.
- DNS resolution.
- ALPN negotiation.
- Stream read/write APIs.
- Connection pooling.
- Protocol adapter integration.
- Tunnel runtime integration.

## Current Context

`IrockTransport` currently exposes:

```text
TransportRequest(host, port, transport)
TransportConnection value placeholder
TransportError.unsupportedTransport
TransportAdapter.open(_ request)
NoopTransportAdapter
```

M11 established protocol adapter contracts. M12 connects tunnel proxy decisions to protocol adapters. M13 now prepares the lower boundary so future protocol adapters can request transport connections through a stable registry instead of constructing transports directly.

Target shape:

```text
Protocol adapter validates protocol config
  -> build TransportRequest(server host, port, transport, TLS options, metadata)
  -> TransportAdapterRegistry.adapter(for: node.transport)
  -> TransportAdapter.open(request:)
  -> TransportConnection
```

## Models

### TransportRequest

`TransportRequest` represents an outbound transport connection attempt:

```swift
public struct TransportRequest: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let transport: TransportType
    public let tls: TLSOptions?
    public let metadata: [String: String]
}
```

`tls` is optional because plain TCP, WebSocket without TLS, and some development fixtures do not require TLS. `metadata` remains string-only to avoid creating an unbounded typed context object before real transport implementations exist.

The existing initializer remains source-compatible by defaulting `tls` to `nil` and `metadata` to `[:]`.

### TransportConnection

`TransportConnection` becomes a protocol:

```swift
public protocol TransportConnection: Sendable {
    var host: String { get }
    var port: Int { get }
    var transport: TransportType { get }
}
```

No read/write stream shape is exposed in M13. Stream APIs should be driven by the first real transport implementation rather than guessed now.

A test/support value type is added:

```swift
public struct EstablishedTransportConnection: TransportConnection, Equatable, Sendable {
    public let host: String
    public let port: Int
    public let transport: TransportType
}
```

## Adapter Contract

```swift
public protocol TransportAdapter: Sendable {
    var supportedTransport: TransportType { get }
    func open(request: TransportRequest) async throws -> any TransportConnection
}
```

Adapters are selected by `TransportAdapterRegistry`, not by protocol adapters hard-coding switch statements. Concrete adapters may later validate TLS and metadata in their own implementations.

## Error Model

`TransportError` supports the Alpha transport taxonomy:

```swift
public enum TransportError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case dnsFailed(String)
    case tcpConnectFailed(String)
    case tlsHandshakeFailed(String)
    case unsupportedTransport(TransportType)
    case quicHandshakeFailed(String)
    case remoteClosed
    case timeout
}
```

Descriptions must be stable and log-safe. Reason strings are redacted from description output for credential-sensitive categories, matching M11 protocol error behavior. `unsupportedTransport` may include the transport raw value.

## Adapter Registry

`TransportAdapterRegistry` maps `TransportType` to adapters:

```swift
public struct TransportAdapterRegistry: Sendable {
    public init(adapters: [any TransportAdapter])
    public func adapter(for transport: TransportType) -> any TransportAdapter
}
```

If no adapter is registered, the registry returns `UnsupportedTransportAdapter(transport:)`. Duplicate registrations use last-wins behavior for test and future override injection.

## Testing Strategy

Add SwiftPM tests for:

- `TransportRequest` stores host, port, transport, TLS options, and metadata.
- Existing request initializer defaults TLS to `nil` and metadata to empty.
- `EstablishedTransportConnection` stores host, port, and transport.
- `UnsupportedTransportAdapter.open(request:)` throws `.unsupportedTransport(request.transport)`.
- `NoopTransportAdapter` remains an unsupported alias.
- `TransportAdapterRegistry` returns registered adapters.
- Registry fallback returns unsupported adapters.
- Duplicate registrations use last-wins behavior.
- `TransportError.description` is stable and does not include credential-like reason text.

Full acceptance requires:

```bash
swift test --filter IrockTransportTests
swift test
```

## Success Criteria

M13 is complete when:

- `IrockTransport` exposes stable transport adapter foundation contracts.
- Unsupported transports fail through typed deterministic errors.
- Adapter lookup is injectable and testable.
- No real socket, TLS, HTTP/2, gRPC, QUIC, DNS, stream, or protocol behavior is prematurely implemented.
- Existing users of `TransportRequest(host:port:transport:)` continue to compile.
- `swift test` passes.
