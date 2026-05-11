# M44 Hysteria2 Foundation Design

Date: 2026-05-12

## Goal

Add a Hysteria2 protocol foundation that validates Hysteria2 node configuration and routes through the QUIC transport seam introduced in M43 without implementing the full Hysteria2 cryptographic handshake.

## Current State

- `ProxyProtocolType.hysteria2` and `TransportType.quic` already exist in `IrockCore`.
- URI import classifies `hysteria2://` as Hysteria2 but does not parse full node fields.
- `IrockTransport` now has a platform-neutral `QUICDialer` and `QUICTransportAdapter` foundation.
- Hysteria2 currently falls back to `UnsupportedProxyAdapter`.

## Design

Add `Hysteria2OpenRequest` and `Hysteria2ProxyAdapter` in `IrockProtocols`.

`Hysteria2OpenRequest` validates the credential account as a non-empty authentication secret but does not expose that value in metadata or synthetic opener bytes. It records destination, SNI, and obfuscation presence as credential-safe metadata.

`Hysteria2ProxyAdapter` accepts only Hysteria2 nodes using `.quic`, validates host, port, credential account, and QUIC transport, then opens a `TransportRequest` with:

- `transport: .quic`
- metadata merged from packet metadata, `proxyProtocol: hysteria2`, and credential-safe Hysteria2 metadata
- initial payload prefixed with deterministic Hysteria2 foundation bytes

Synthetic opener:

- `hysteria2-foundation:<destination>:<sni>:auth-present:<obfsPresent>`
- Hysteria2 password/auth material is never copied into metadata or opener bytes.

Add runtime stack helpers so future tunnel assembly can explicitly choose Hysteria2 over QUIC:

- `RuntimeProxyStack.hysteria2QUIC(quic:)`
- `TunnelRuntimeConfiguration.hysteria2QUIC(...)`

## Scope

In scope:

- Hysteria2 configuration validation.
- Credential-safe Hysteria2 metadata and synthetic opener bytes.
- Hysteria2 proxy adapter routing through `.quic` transport registry.
- Runtime stack/configuration helper for Hysteria2 over QUIC.
- Tests for validation, metadata safety, transport routing, error mapping, and runtime assembly.

Out of scope:

- Full Hysteria2 cryptographic handshake compatibility.
- Real QUIC socket/session implementation beyond the M43 `QUICDialer` seam.
- UDP forwarding and packet-loop UDP behavior.
- Hysteria2 URI parsing beyond existing scheme classification.
- Congestion control, bandwidth hints, or advanced Hysteria2 settings.
- TUIC support, which remains M45.
- UI/subscription import changes.
- Real-node Hysteria2 validation without external credentials and reachable nodes.

## Validation

- `swift test --filter IrockProtocolsTests` passes and covers Hysteria2 open request and adapter behavior.
- `swift test --filter IrockTunnelCoreTests` passes and covers Hysteria2 QUIC runtime stack assembly.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
- Source exposure scan finds no Hysteria2 credential value in metadata or synthetic opener construction.
