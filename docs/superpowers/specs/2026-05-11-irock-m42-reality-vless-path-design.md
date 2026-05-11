# M42 Reality Options and VLESS Reality Path Design

Date: 2026-05-11

## Goal

Model Reality as a VLESS-specific transport foundation path without weakening the existing standard TLS adapter boundary.

## Current State

- `RealityOptions` already exists in `IrockCore` and is nested under `TLSOptions`.
- `TLSTransportAdapter` currently rejects `tls.reality != nil`, preserving the M17 decision that Reality is not standard TLS behavior.
- VLESS foundation adapters can open TCP, WebSocket, HTTP/2, and gRPC transports through the transport registry.
- VLESS request metadata is credential-safe and does not expose UUID credential material.

## Design

Add a `RealityTransportAdapter` in `IrockTransport`. It supports `TransportType.tcp` requests that carry enabled TLS options with non-nil `RealityOptions`. It validates host, port, TLS enabled state, server name, Reality public key, optional short ID, and optional spiderX before opening an underlying TCP request.

The adapter rewrites the underlying request to plain `.tcp` with `tls: nil`, because the foundation does not perform a real Reality handshake yet. It prefixes existing protocol opener bytes with deterministic, non-secret Reality foundation bytes and passes normalized Reality metadata to the underlying transport.

Metadata keys:

- `realityServerName`
- `realityPublicKeyPresent` set to `true`
- `realityShortIDPresent` set to `true` or `false`
- `realitySpiderX` when provided
- `realityFingerprint` when provided
- `realityALPN` when ALPN values are provided

Synthetic opener:

- `reality-foundation:<serverName>:public-key-present:<shortIDPresent>:<spiderX>\n`
- Existing VLESS opener bytes are appended after the marker.
- The Reality public key, VLESS UUID, and other credential-like values are not copied into metadata or opener bytes.

Wire VLESS Reality through a new protocol adapter path by allowing `VLESSProxyAdapter` to accept `.tcp` nodes whose TLS options include Reality, then relying on the transport registry to select a Reality-capable TCP adapter in runtime assembly. Standard VMess, Trojan, Shadowsocks, and plain TLS paths remain unchanged.

## Scope

In scope:

- Reality transport adapter validation and metadata normalization.
- Credential-safe synthetic Reality opener bytes preserving VLESS initial payload bytes.
- VLESS adapter acceptance for TCP + Reality TLS options.
- Runtime stack helper for VLESS Reality over TCP using the Reality transport adapter and existing TCP dialer seam.
- Tests for validation, metadata safety, payload preservation, standard TLS rejection behavior, and VLESS Reality routing.

Out of scope:

- Full Reality cryptographic handshake compatibility.
- X25519/key schedule implementation.
- uTLS/client fingerprint emulation beyond carrying the existing fingerprint string as non-secret metadata.
- Server certificate validation changes.
- Reality over WebSocket, HTTP/2, gRPC, or QUIC.
- UI/subscription import for Reality fields.
- Real-node Reality validation without external credentials and reachable nodes.

## Validation

- `swift test --filter IrockCoreTests` passes and covers `RealityOptions` codability where needed.
- `swift test --filter IrockTransportTests` passes and covers `RealityTransportAdapter` validation and underlying TCP rewrite.
- `swift test --filter IrockProtocolsTests` passes and covers VLESS Reality routing while VMess/Trojan behavior remains unchanged.
- `swift test --filter IrockTunnelCoreTests` passes and covers runtime VLESS Reality stack assembly.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
- Source scan finds no Reality public key, VLESS UUID, or password values in synthetic opener bytes or normalized metadata keys.
