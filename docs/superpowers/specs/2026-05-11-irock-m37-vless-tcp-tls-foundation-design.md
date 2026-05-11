# M37 VLESS TCP/TLS Foundation Design

Date: 2026-05-11

## Goal

Add the first VLESS protocol adapter foundation so a VLESS node can validate configuration and open TCP or TCP/TLS transport through the existing proxy/transport seams.

## Current State

- `ProxyProtocolType.vless` already exists in `IrockCore`.
- Unsupported VLESS requests currently fall back to `UnsupportedProxyAdapter`.
- M36 added a credential-safe VMess foundation with UUID validation, synthetic non-secret opener payload, and TCP/TLS runtime stack registration.
- `IrockTunnelCore.RuntimeProxyStack` now has established patterns for protocol-specific TCP/TLS stacks.

## Design

Add a narrow `VLESSProxyAdapter` in `IrockProtocols`, mirroring the M36 VMess foundation while preserving VLESS-specific protocol identity. It validates the Alpha-supported VLESS TCP/TLS shape:

- `node.protocolType == .vless`
- non-empty server host
- port in `1...65_535`
- non-empty credential account containing a UUID
- `node.transport == .tcp`

The adapter validates the credential account as a VLESS UUID but does not expose it in metadata or plaintext transport payloads. M37 does not claim full VLESS cryptographic or Reality compatibility; it establishes the typed runtime seam, validation rules, credential-safe metadata, and TCP/TLS routing that later milestones can deepen into full VLESS request framing and Reality support. The synthetic opener marker sent as `TransportRequest.initialPayload` contains only destination/security/flow information and deliberately omits credential-derived values.

Add `RuntimeProxyStack.vlessTCP(plain:tls:)` and `TunnelRuntimeConfiguration.vlessTCP(...)` in `IrockTunnelCore`, mirroring the VMess helper shape. This keeps shared packages platform-neutral and allows later provider/runtime selection to register VLESS without changing packet processing.

## Scope

In scope:

- VLESS configuration validation for TCP/TLS foundation.
- VLESS synthetic opener descriptor with stable credential-safe metadata and initial payload bytes.
- VLESS adapter integration with `TransportAdapterRegistry` and TCP/TLS selector.
- Runtime stack helpers for VLESS TCP/TLS.
- Regression tests for validation, transport requests, TLS selection, credential safety, and runtime stack registration.

Out of scope:

- Full VLESS request encryption/framing compatibility.
- Reality options and VLESS Reality path.
- WebSocket, HTTP/2, gRPC, QUIC, UDP, or mux support.
- UI changes or subscription import changes.
- Real-node VLESS validation without external credentials and reachable test nodes.

## Validation

- `swift test --filter IrockProtocolsTests` passes and covers VLESS validation, credential-safe opener metadata, and transport requests.
- `swift test --filter IrockTunnelCoreTests` passes and covers VLESS runtime stack registration and TLS routing.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
