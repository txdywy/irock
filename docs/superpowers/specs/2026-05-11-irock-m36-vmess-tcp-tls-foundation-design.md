# M36 VMess TCP/TLS Foundation Design

Date: 2026-05-11

## Goal

Add the first VMess protocol adapter foundation so a VMess node can validate configuration and open TCP or TCP/TLS transport through the existing proxy/transport seams.

## Current State

- `ProxyProtocolType.vmess` already exists in `IrockCore`.
- `IrockProtocols` has generic `ProxyAdapter`, `TransportBackedProxyAdapter`, registry, and Shadowsocks-specific adapter patterns.
- `IrockTunnelCore.RuntimeProxyStack` wires Shadowsocks through `TCPTLSTransportAdapter` for plain TCP versus TLS selection.
- No VMess-specific validation, opener metadata, or runtime stack registration exists yet.

## Design

Add a narrow `VMessProxyAdapter` in `IrockProtocols`. It validates only the Alpha-supported VMess TCP/TLS shape:

- `node.protocolType == .vmess`
- non-empty server host
- port in `1...65_535`
- non-empty credential account containing a UUID
- `node.transport == .tcp`

The adapter validates the credential account as a VMess UUID but does not expose it in metadata or plaintext transport payloads. M36 does not claim full VMess cryptographic handshake compatibility; it establishes the typed runtime seam, validation rules, credential-safe metadata, and TCP/TLS routing that later milestones can deepen into full VMess framing/encryption. The synthetic opener marker sent as `TransportRequest.initialPayload` contains only destination/security/alterId information and deliberately omits credential-derived values.

Add `RuntimeProxyStack.vmessTCP(plain:tls:)` and `TunnelRuntimeConfiguration.vmessTCP(...)` in `IrockTunnelCore`, mirroring the Shadowsocks TCP/TLS stack. This keeps shared packages platform-neutral and lets future provider wiring select protocol-specific stacks without changing packet processing.

## Scope

In scope:

- VMess configuration validation for TCP/TLS foundation.
- VMess opener descriptor with stable metadata and initial payload bytes.
- VMess adapter integration with `TransportAdapterRegistry` and TCP/TLS selector.
- Runtime stack helpers for VMess TCP/TLS.
- Regression tests for validation, transport requests, TLS selection, and runtime stack registration.

Out of scope:

- Full VMess AEAD/non-AEAD cryptographic handshake implementation.
- WebSocket, HTTP/2, gRPC, Reality, QUIC, UDP, or mux support.
- UI changes or subscription import changes.
- Real-node VMess validation without external credentials and reachable test nodes.

## Validation

- `swift test --filter IrockProtocolsTests` passes and covers VMess validation and transport requests.
- `swift test --filter IrockTunnelCoreTests` passes and covers VMess runtime stack registration and TLS routing.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
