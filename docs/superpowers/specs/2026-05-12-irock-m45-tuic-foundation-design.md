# M45 TUIC Foundation Design

Date: 2026-05-12

## Goal

Add a TUIC protocol foundation that validates TUIC node configuration and routes through the QUIC transport seam introduced in M43 without implementing the full TUIC cryptographic handshake.

## Current State

- `ProxyProtocolType.tuic` and `TransportType.quic` already exist in `IrockCore`.
- URI import classifies `tuic://` as TUIC but does not parse full node fields.
- `IrockTransport` has a platform-neutral `QUICDialer` and `QUICTransportAdapter` foundation.
- TUIC currently falls back to `UnsupportedProxyAdapter`.

## Design

Add `TUICOpenRequest` and `TUICProxyAdapter` in `IrockProtocols`.

`TUICOpenRequest` validates the credential account as UUID/password material encoded as `<uuid>:<password>`. It validates that the UUID is syntactically valid and that the password is non-empty, but it never exposes either value in metadata or synthetic opener bytes. It records destination, SNI, and credential-presence flags as safe metadata.

`TUICProxyAdapter` accepts only TUIC nodes using `.quic`, validates host, port, credential account, and QUIC transport, then opens a `TransportRequest` with:

- `transport: .quic`
- metadata merged from packet metadata, `proxyProtocol: tuic`, and credential-safe TUIC metadata
- initial payload prefixed with deterministic TUIC foundation bytes

Synthetic opener:

- `tuic-foundation:<destination>:<sni>:uuid-present:password-present`
- TUIC UUID and password values are never copied into metadata or opener bytes.

Add runtime stack helpers so future tunnel assembly can explicitly choose TUIC over QUIC:

- `RuntimeProxyStack.tuicQUIC(quic:)`
- `TunnelRuntimeConfiguration.tuicQUIC(...)`

## Scope

In scope:

- TUIC configuration validation.
- Credential-safe TUIC metadata and synthetic opener bytes.
- TUIC proxy adapter routing through `.quic` transport registry.
- Runtime stack/configuration helper for TUIC over QUIC.
- Tests for validation, metadata safety, transport routing, error mapping, and runtime assembly.

Out of scope:

- Full TUIC cryptographic handshake compatibility.
- Real QUIC socket/session implementation beyond the M43 `QUICDialer` seam.
- UDP forwarding and packet-loop UDP behavior.
- TUIC URI parsing beyond existing scheme classification.
- Congestion control, multiplexed stream lifecycle, or token derivation.
- UI/subscription import changes.
- Real-node TUIC validation without external credentials and reachable nodes.

## Validation

- `swift test --filter IrockProtocolsTests` passes and covers TUIC open request and adapter behavior.
- `swift test --filter IrockTunnelCoreTests` passes and covers TUIC QUIC runtime stack assembly.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
- Source exposure scan finds no TUIC UUID/password credential value in metadata or synthetic opener construction.
