# M38 Trojan TCP/TLS Foundation Design

Date: 2026-05-11

## Goal

Add the first Trojan protocol adapter foundation so a Trojan node can validate configuration and open TCP or TCP/TLS transport through the existing proxy/transport seams.

## Current State

- `ProxyProtocolType.trojan` already exists in `IrockCore`.
- Existing tests use Trojan through generic recording or transport-backed adapters, but there is no dedicated Trojan adapter with Trojan-specific credential validation or credential-safe opener metadata.
- M36 and M37 added credential-safe VMess and VLESS foundations with protocol-specific opener descriptors and TCP/TLS runtime stack registration.
- `IrockTunnelCore.RuntimeProxyStack` has established protocol-specific TCP/TLS helper patterns.

## Design

Add a narrow `TrojanOpenRequest` and `TrojanProxyAdapter` in `IrockProtocols`, following the foundation pattern while preserving Trojan-specific protocol identity. It validates the Alpha-supported Trojan TCP/TLS shape:

- `node.protocolType == .trojan`
- non-empty server host
- port in `1...65_535`
- non-empty credential account containing the Trojan password/reference value
- `node.transport == .tcp`

The adapter treats the credential account as secret-bearing material and does not expose it in metadata or plaintext synthetic opener bytes. M38 does not claim full Trojan protocol compatibility; it establishes the typed runtime seam, validation rules, credential-safe metadata, and TCP/TLS routing that later milestones can deepen into full Trojan request framing and real-node validation. The synthetic opener marker sent as `TransportRequest.initialPayload` contains only destination and SNI information and deliberately omits credential-derived values.

Add `RuntimeProxyStack.trojanTCP(plain:tls:)` and `TunnelRuntimeConfiguration.trojanTCP(...)` in `IrockTunnelCore`, mirroring VMess/VLESS helper shape. This keeps shared packages platform-neutral and allows later provider/runtime selection to register Trojan without changing packet processing.

## Scope

In scope:

- Trojan configuration validation for TCP/TLS foundation.
- Trojan synthetic opener descriptor with stable credential-safe metadata and initial payload bytes.
- Trojan adapter integration with `TransportAdapterRegistry` and TCP/TLS selector.
- Runtime stack helpers for Trojan TCP/TLS.
- Regression tests for validation, transport requests, TLS selection, credential safety, and runtime stack registration.

Out of scope:

- Full Trojan request framing or authentication handshake compatibility.
- WebSocket, HTTP/2, gRPC, QUIC, UDP, mux, or fallback support.
- UI changes or subscription import changes.
- Real-node Trojan validation without external credentials and reachable test nodes.

## Validation

- `swift test --filter IrockProtocolsTests` passes and covers Trojan validation, credential-safe opener metadata, and transport requests.
- `swift test --filter IrockTunnelCoreTests` passes and covers Trojan runtime stack registration and TLS routing.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
- Trojan credential fixture values appear only in tests/assertions and not in source metadata or synthetic opener payload construction.
