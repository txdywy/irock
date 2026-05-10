# irock M11 Protocol Adapter Foundation Design

Date: 2026-05-11

## Goal

M11 establishes the protocol adapter foundation in `IrockProtocols`. It turns the current placeholder protocol package into a stable boundary for future Shadowsocks, Trojan, VMess, VLESS, Hysteria2, and TUIC implementations.

M11 does not implement real proxy handshakes, encryption, TCP forwarding, UDP forwarding, or protocol-lab comparison runs. It defines the shared request, destination, connection, error, adapter, and registry contracts that M12+ protocol implementations will use.

## Scope

In scope:

- Define a protocol-layer destination model for TCP and UDP-like outbound targets.
- Define a `ProxyRequest` that carries the selected `ProxyNode`, destination, and optional metadata.
- Define a lightweight `ProxyConnection` protocol representing an established adapter connection.
- Define a `ProxyAdapter` protocol with an async `connect(request:)` method.
- Define `ProxyProtocolError` with the Alpha error taxonomy needed by protocol and transport adapters.
- Provide an `UnsupportedProxyAdapter` that fails deterministically for not-yet-implemented protocols.
- Provide a `ProxyAdapterRegistry` that selects adapters by `ProxyProtocolType` and falls back to `UnsupportedProxyAdapter`.
- Preserve the existing `NoopProxyAdapter` behavior only if needed as a compatibility alias during this milestone.
- Cover request modeling, error descriptions/equality where appropriate, unsupported behavior, and registry lookup with SwiftPM tests.

Out of scope:

- Shadowsocks AEAD methods or stream ciphers.
- Trojan TLS handshake.
- VMess/VLESS serialization.
- TCP socket implementation.
- WebSocket, HTTP/2, gRPC, Reality, or QUIC transports.
- DNS resolution.
- Packet-to-proxy stream bridging in `IrockTunnelCore`.
- Keychain credential lookup.

## Current Context

M5-M10 established the app/tunnel runtime control plane:

```text
App editable node/rules
  -> RuntimeSnapshot
  -> TunnelRuntimeConfiguration
  -> PacketProcessor and RoutingEngine
  -> RuntimeConnectionStatus / RuntimeLogEntry feedback
```

The protocol data plane remains intentionally thin. `IrockProtocols` currently needs a real contract before individual protocols can be added safely.

M11 creates this target shape:

```text
Packet/flow decision says PROXY
  -> build ProxyRequest(selected node, destination)
  -> ProxyAdapterRegistry.adapter(for: node.protocolType)
  -> ProxyAdapter.connect(request:)
  -> ProxyConnection
```

M11 only builds and tests the contract and selection behavior; later milestones fill in concrete adapters.

## Models

### ProxyDestination

`ProxyDestination` represents the remote endpoint requested by the packet/proxy layer:

```swift
public enum ProxyDestination: Equatable, Sendable {
    case host(String, port: Int)
    case ipv4(String, port: Int)
    case ipv6(String, port: Int)
}
```

M11 stores IP addresses as strings rather than introducing an IP address value type in `IrockProtocols`; packet parsing already owns binary packet interpretation in `IrockTunnelCore`.

### ProxyRequest

`ProxyRequest` carries the selected node and destination:

```swift
public struct ProxyRequest: Equatable, Sendable {
    public let node: ProxyNode
    public let destination: ProxyDestination
    public let metadata: [String: String]
}
```

`metadata` is intentionally string-only and optional-by-default so future adapters can receive small hints without creating an unbounded typed context object.

### ProxyConnection

`ProxyConnection` is intentionally minimal in M11:

```swift
public protocol ProxyConnection: Sendable {
    var nodeID: NodeID { get }
    var destination: ProxyDestination { get }
}
```

It does not expose read/write streams yet. Stream shape should be driven by the first real protocol adapter and transport implementation instead of guessed now.

A small `EstablishedProxyConnection` value type supports tests and future simple adapters:

```swift
public struct EstablishedProxyConnection: ProxyConnection, Equatable, Sendable {
    public let nodeID: NodeID
    public let destination: ProxyDestination
}
```

## Adapter Contract

`ProxyAdapter` is the protocol package boundary:

```swift
public protocol ProxyAdapter: Sendable {
    var supportedProtocol: ProxyProtocolType { get }
    func connect(request: ProxyRequest) async throws -> ProxyConnection
}
```

Adapters validate that `request.node.protocolType` matches `supportedProtocol`. Concrete adapters may perform deeper configuration checks later.

`UnsupportedProxyAdapter` implements this contract by always throwing `.unsupportedProtocol` for the requested node protocol. This gives `IrockTunnelCore` and app-facing code a deterministic failure path before real protocol adapters exist.

## Error Model

`ProxyProtocolError` uses the Alpha taxonomy from the project design:

```swift
public enum ProxyProtocolError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case dnsFailed(String)
    case tcpConnectFailed(String)
    case tlsHandshakeFailed(String)
    case authenticationFailed(String)
    case unsupportedTransport(TransportType)
    case unsupportedProtocol(ProxyProtocolType)
    case protocolHandshakeFailed(String)
    case quicHandshakeFailed(String)
    case udpUnsupported
    case remoteClosed
    case timeout
}
```

Descriptions should be stable and user-log-safe: they may include protocol, transport, or short failure reason, but not raw credentials, passwords, UUID secrets, tokens, or full node URLs.

## Adapter Registry

`ProxyAdapterRegistry` maps `ProxyProtocolType` to adapters:

```swift
public struct ProxyAdapterRegistry: Sendable {
    public init(adapters: [any ProxyAdapter])
    public func adapter(for protocolType: ProxyProtocolType) -> any ProxyAdapter
}
```

If no adapter is registered, the registry returns an `UnsupportedProxyAdapter` for the requested protocol. Duplicate adapter registrations should use last-wins behavior; this makes tests and future override injection simple.

The registry does not own credentials, transport adapters, or connection pools.

## Package Boundaries

M11 stays inside `IrockProtocols` and its tests unless `Package.swift` needs dependency cleanup.

Expected files:

```text
packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift
packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
```

`IrockProtocols` already depends on `IrockCore` and `IrockTransport`. M11 should not make it depend on `IrockTunnelCore`, `IrockStorage`, or `IrockAppFeature`.

## Error Handling

Unsupported protocols and transports are not silent fallbacks. They throw typed `ProxyProtocolError` values.

The registry fallback exists to make failure deterministic, not to hide missing implementations. Later runtime code should log these failures through the M10 runtime feedback path.

## Testing Strategy

Add SwiftPM tests for:

- `ProxyDestination` equality for host/IPv4/IPv6 cases.
- `ProxyRequest` stores node, destination, and metadata.
- `EstablishedProxyConnection` stores node ID and destination.
- `UnsupportedProxyAdapter.connect(request:)` throws `.unsupportedProtocol(request.node.protocolType)`.
- `ProxyAdapterRegistry` returns a registered adapter for its protocol.
- Registry fallback returns an unsupported adapter for missing protocols.
- Duplicate registrations use last-wins behavior.
- `ProxyProtocolError.description` is stable for representative cases and does not include credential material from nodes.

Full acceptance requires `swift test` passing.

## Success Criteria

M11 is complete when:

- `IrockProtocols` exposes stable protocol adapter foundation types.
- Unsupported protocols fail through a typed, deterministic error.
- Adapter lookup is injectable and testable.
- No real protocol handshake, encryption, or transport behavior is prematurely implemented.
- The package dependency graph remains one-way and does not pull tunnel/app/storage code into protocol code.
- `swift test` passes.
