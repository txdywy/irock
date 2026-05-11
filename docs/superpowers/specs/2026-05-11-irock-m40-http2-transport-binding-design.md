# M40 HTTP/2 Transport Binding Design

Date: 2026-05-11

## Goal

Add an HTTP/2 transport foundation so protocols can request `TransportType.http2` and open through the existing TCP/TLS transport seam with deterministic, credential-safe HTTP/2 metadata.

## Current State

- `TransportType.http2` already exists in `IrockCore`.
- `IrockTransport` has TCP, TLS, TCP/TLS selector, and M39 WebSocket adapter foundations.
- VMess, VLESS, and Trojan foundations can now use TCP/TLS and WebSocket transport paths.
- HTTP/2 requests currently fall back to unsupported transport.

## Design

Add an `HTTP2TransportAdapter` in `IrockTransport`. It supports `.http2`, validates host, port, path, authority, and optional protocol metadata, then opens an underlying request as `.tcp`. TLS options are preserved so the existing TCP/TLS selector can route secure HTTP/2 to TLS where configured.

The foundation builds deterministic, non-secret metadata and synthetic initial bytes. It does not implement real HTTP/2 connection preface, SETTINGS negotiation, HPACK, stream multiplexing, flow control, or response validation. Those belong in later deepening milestones. The synthetic opener marker contains authority/path/protocol only, and it appends any upstream protocol opener bytes after the marker.

Metadata keys:

- `http2Authority`
- `http2Path`
- `http2Protocol` when provided
- `http2Upgrade` set to `true`

Input metadata:

- `http2Path` defaults to `/`
- `http2Authority` defaults to the trimmed request host
- `http2Protocol` is optional

## Scope

In scope:

- HTTP/2 transport adapter validation.
- HTTP/2 metadata normalization.
- Synthetic HTTP/2 opener bytes that preserve existing protocol initial payload bytes.
- Registry selection for `.http2`.
- VMess, VLESS, and Trojan foundation adapters accepting `.http2` transport.
- Tests for validation, metadata, payload preservation, TLS preservation, and protocol adapter routing.

Out of scope:

- Full HTTP/2 protocol compatibility.
- HPACK, stream multiplexing, flow control, and response validation.
- Per-protocol HTTP/2 framing differences.
- UI/subscription import changes.
- Real-node HTTP/2 validation without external credentials and reachable nodes.

## Validation

- `swift test --filter IrockTransportTests` passes and covers HTTP/2 validation and underlying routing.
- `swift test --filter IrockProtocolsTests` passes and covers applicable protocol foundation adapters routing `.http2`.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
- No credential-like fixture values are introduced into source HTTP/2 metadata or synthetic opener payload construction.
