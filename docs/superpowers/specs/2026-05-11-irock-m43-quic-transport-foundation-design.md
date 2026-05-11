# M43 QUIC Transport Foundation Design

Date: 2026-05-11

## Goal

Add a QUIC transport foundation that gives Hysteria2 and TUIC later milestones a stable transport seam without introducing platform networking dependencies into shared packages.

## Current State

- `TransportType.quic` already exists in `IrockCore`.
- `TransportError.quicHandshakeFailed` already exists and maps through protocol adapters.
- `IrockTransport` has TCP, TLS, TCP/TLS selection, WebSocket, HTTP/2, gRPC, and Reality foundation adapters.
- QUIC requests currently fall back to `UnsupportedTransportAdapter`.
- Hysteria2 and TUIC are classified at URI/protocol type level but still use unsupported protocol adapters.

## Design

Add a `QUICDialer` seam and `QUICTransportAdapter` in `IrockTransport`. The adapter supports `.quic`, validates host, port, optional server name, ALPN values, and optional protocol metadata, then delegates to a dialer abstraction. This keeps shared transport tests deterministic and leaves real `Network.framework` / platform QUIC implementation for app or extension targets.

The adapter returns an `EstablishedTransportConnection` with `.quic` transport. It passes deterministic, non-secret initial payload bytes to the dialer so future protocol adapters can prepend Hysteria2/TUIC open bytes without leaking credentials.

Metadata keys:

- `quicServerName` when provided, otherwise normalized host
- `quicProtocol` when provided
- `quicALPN` when ALPN values are provided
- `quicHandshake` set to `foundation`

Input metadata:

- `quicServerName` defaults to the trimmed request host
- `quicProtocol` is optional
- `quicALPN` can be provided in metadata or derived from TLS ALPN when present

Synthetic opener:

- `quic-foundation:<serverName>:<protocol>:<alpn>\n`
- Existing initial payload bytes are appended after the marker.
- The marker must not contain credentials, passwords, tokens, or protocol account identifiers.

## Scope

In scope:

- `QUICDialer` protocol and deterministic recording/failing test implementations.
- `QUICTransportAdapter` validation and dialer delegation.
- Credential-safe QUIC metadata normalization.
- Synthetic QUIC opener bytes preserving existing initial payload bytes.
- Registry selection for `.quic`.
- Tests for validation, metadata, payload preservation, error propagation, and credential-safe descriptions.

Out of scope:

- Real QUIC socket/session implementation.
- `Network.framework`, `NWConnection`, `NWProtocolQUIC`, or platform imports in shared packages.
- Hysteria2 and TUIC protocol handshakes.
- UDP forwarding and packet-loop UDP behavior.
- TLS certificate validation changes.
- UI/subscription import for QUIC fields.
- Real-node QUIC validation without external credentials and reachable nodes.

## Validation

- `swift test --filter IrockTransportTests` passes and covers QUIC validation, metadata, payload, and dialer error propagation.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
- Source exposure scan finds no credential-like values in QUIC metadata or synthetic opener construction.
