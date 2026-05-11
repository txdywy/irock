# M39 WebSocket Transport Binding Design

Date: 2026-05-11

## Goal

Add a WebSocket transport foundation so protocols can request `TransportType.webSocket` and open through an existing TCP/TLS transport seam with credential-safe, deterministic WebSocket handshake metadata.

## Current State

- `TransportType.webSocket` already exists in `IrockCore`.
- `IrockTransport` currently has TCP, TLS, and TCP/TLS selector adapters, but WebSocket falls back to unsupported transport.
- VMess, VLESS, Trojan, and Shadowsocks foundations currently support TCP/TLS paths; M39 establishes the shared transport seam later protocol milestones can bind to.

## Design

Add a `WebSocketTransportAdapter` in `IrockTransport`. It supports `.webSocket`, validates host, port, path, and optional host header metadata, then opens an underlying transport request as `.tcp`. TLS is preserved so the existing TCP/TLS selector can route plain WebSocket to TCP and secure WebSocket to TLS.

The foundation builds deterministic, non-secret metadata and synthetic initial bytes. It does not implement full RFC6455 client masking, frame parsing, stream forwarding, compression, or HTTP upgrade response validation. Those belong in later deepening milestones. The synthetic opener marker contains host/path and optional protocol marker only, and it appends any upstream protocol opener bytes after the marker so protocol adapters can keep their existing credential-safe open descriptors.

Metadata keys:

- `webSocketHost`
- `webSocketPath`
- `webSocketProtocol` when provided
- `webSocketUpgrade` set to `true`

Input metadata:

- `webSocketPath` defaults to `/`
- `webSocketHost` defaults to the trimmed request host
- `webSocketProtocol` is optional

## Scope

In scope:

- WebSocket transport adapter validation.
- WebSocket metadata normalization.
- Synthetic WebSocket opener bytes that preserve existing protocol initial payload bytes.
- Registry selection for `.webSocket`.
- Tests for validation, metadata, payload preservation, TLS preservation, and underlying TCP/TLS routing.

Out of scope:

- Full WebSocket RFC6455 handshake compatibility.
- WebSocket frame encoding/decoding and stream forwarding.
- Per-protocol WebSocket framing differences.
- UI/subscription import changes.
- Real-node WebSocket validation without external credentials and reachable nodes.

## Validation

- `swift test --filter IrockTransportTests` passes and covers WebSocket validation and underlying routing.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
- No credential-like fixture values are introduced into source WebSocket metadata or synthetic opener payload construction.
