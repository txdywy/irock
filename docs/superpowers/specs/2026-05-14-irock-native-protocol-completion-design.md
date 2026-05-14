# Native Protocol Completion Design

Date: 2026-05-14

## Goal

Fully implement the planned irock protocol surface with native Swift/C code, without embedding full proxy cores or importing existing protocol libraries. The implementation should prioritize correctness, local testability, runtime performance, and staged real-node validation.

The planned protocol surface is:

- Shadowsocks and Shadowsocks 2022.
- Trojan over TCP+TLS, then WebSocket/gRPC where supported by the transport layer.
- VLESS over TCP+TLS and VLESS Reality.
- VMess over TCP+TLS and common stream transports.
- Hysteria2 over QUIC, including the existing native HY2 work.
- TUIC over QUIC.
- Shared WebSocket, HTTP/2, gRPC, QUIC, Reality, and UDP forwarding foundations needed by those protocols.

## Non-goals

- Do not embed sing-box, xray, clash, or any full proxy core.
- Do not add third-party protocol implementations as dependencies.
- Do not commit real credentials, subscription URLs, server captures, private keys, Apple signing material, or operator-only node details.
- Do not treat URI import, adapter routing, or marker payloads as protocol completion.
- Do not claim automated real-node coverage unless the run uses explicitly supplied external credentials and produces fresh evidence.

## Current state

The repository already has broad protocol scaffolding:

- `ProxyProtocolType` covers Shadowsocks, VMess, VLESS, Trojan, Hysteria2, and TUIC.
- URI import can parse common `ss://`, `vmess://`, `vless://`, `trojan://`, `hy2://`, and `tuic://` forms into node drafts.
- `IrockProtocols` contains protocol open request builders and adapters for the planned protocols.
- `IrockTransport` contains TCP, TLS, WebSocket, HTTP/2, gRPC, QUIC, and Reality transport seams.
- `IrockTunnelCore` has runtime stack helpers for Shadowsocks, VMess, VLESS, Trojan, Hysteria2, and TUIC.
- Hysteria2 has advanced native QUIC/HTTP3 work and macOS local proxy integration.

The gap is depth and runtime completeness. Several protocols have deterministic local wire-format builders, but not all are connected through a real local proxy/runtime stream path and not all planned transport variants have performance-oriented native streaming behavior.

## Design principles

### Layered completion

Each protocol moves through the same completion ladder:

1. Import/config: parse common URI/subscription forms into safe node models.
2. Native wire-format builder: generate protocol-shaped bytes or handshake descriptors without plaintext foundation markers.
3. Transport binding: route the protocol over TCP, TLS, WebSocket, HTTP/2, gRPC, QUIC, or Reality as appropriate.
4. Runtime stream path: connect local SOCKS/HTTP CONNECT or TUN flows through the protocol adapter to the transport stream.
5. Performance path: use bounded buffers, incremental parsers, reusable state machines, and avoid packet hot-path allocations where practical.
6. Real-node validation: verify against external nodes only when credentials are explicitly supplied outside the repository.

A protocol is not considered implemented until its current milestone reaches the runtime stream path. URI import and wire-format tests are necessary but not sufficient.

### Native implementation boundary

All protocol behavior must be implemented in this repository using Swift and focused C shims where low-level networking or crypto integration requires it. Existing system libraries such as Foundation, CryptoKit, Network, OpenSSL, ngtcp2, and nghttp3 may be used as primitives. Full proxy cores and protocol-specific external libraries are not allowed.

### Performance posture

Protocol implementations should be shaped around streaming rather than whole-message buffering:

- Incremental frame parsers for TCP stream protocols.
- Bounded read/write buffers for local proxy and tunnel paths.
- Minimal copying between local proxy, protocol adapter, and transport stream.
- Stable metadata maps that avoid storing raw credentials or large payload dumps.
- Tests for packet/frame boundaries, partial reads, blocked writes, and cancellation.

### Security and privacy posture

Secrets must stay outside runtime snapshots, metadata, diagnostic logs, errors, and committed fixtures. Credentials are resolved only at runtime boundaries and must be redacted before any error or metadata leaves the adapter.

## Implementation order

### Phase 1: Trojan TCP+TLS end-to-end

Trojan is the first post-HY2 protocol to make fully usable because its request format is simple and common in real deployments.

Scope:

- Confirm Trojan URI import covers password, host, port, SNI, ALPN, and transport hints.
- Ensure `TrojanOpenRequest` emits the real Trojan request prefix: SHA224 password hex, CRLF, command, address, port, and trailing CRLF.
- Add or reuse a runtime byte-stream path that can send the Trojan prefix and then proxy bidirectional local SOCKS/HTTP CONNECT data over TLS.
- Wire Trojan into macOS local proxy startup instead of returning “unsupported local proxy”.
- Add local tests for wire bytes, redaction, partial response reads, connection cancellation, and unsupported transport variants.
- Add an optional external validation script or test gated by environment variables for real Trojan nodes.

Acceptance:

- Trojan TCP+TLS can be selected from imported configuration and used by the local proxy when credentials are available.
- Full SwiftPM tests pass.
- Optional real-node verification is documented and credential-gated.

### Phase 2: VLESS TCP+TLS and Reality

VLESS is next because it shares a simple request header model and unlocks the Reality path.

Scope:

- Preserve VLESS UUID validation and secret-safe metadata.
- Implement VLESS request header streaming for TCP+TLS.
- Keep unsupported `flow` values explicit until a native XTLS/Vision design exists.
- Deepen Reality from local descriptor to a native, testable transport prelude/handshake path using repository-owned code and allowed crypto primitives.
- Wire VLESS TCP+TLS into local proxy before Reality real-node validation.

Acceptance:

- VLESS TCP+TLS local proxy path works with native request bytes.
- Reality options are parsed, validated, redacted, and tested; real Reality interop is a separate acceptance gate.

### Phase 3: VMess TCP+TLS and stream transports

VMess follows after Trojan/VLESS because its authenticated request header and time/random inputs are more complex.

Scope:

- Implement deterministic VMess AEAD request generation with injectable time/randomness for tests.
- Validate UUID, alterId/security modes, destination, and transport options.
- Add stream transport bindings for WebSocket first, then HTTP/2/gRPC where the transport layer is ready.
- Keep legacy or unsupported VMess modes explicitly rejected rather than silently accepting unsafe partial behavior.

Acceptance:

- VMess TCP+TLS local proxy path works for the supported modern mode.
- WebSocket VMess has local upgrade/framing tests before real-node validation.

### Phase 4: TUIC over QUIC

TUIC should reuse lessons from HY2 but remain its own native implementation.

Scope:

- Implement TUIC auth/session request bytes and stream open behavior natively.
- Reuse QUIC transport primitives where possible without mixing HY2 protocol state into TUIC state.
- Add tests for auth validation, stream open, blocked read/write behavior, redaction, and cancellation.
- Wire TUIC into local proxy only after local stream tests pass.

Acceptance:

- TUIC local proxy path can open a TCP stream over QUIC with native protocol state.
- Optional real-node validation is environment-gated.

### Phase 5: Shared transports and UDP forwarding

Transport work should support protocol milestones without becoming a separate full proxy core.

Scope:

- WebSocket: RFC6455 upgrade, masking rules where the client writes frames, partial frame parser, and stream adapter.
- HTTP/2: native stream lifecycle over nghttp3/nghttp2-style primitives or repository-owned frame builders where practical.
- gRPC: HTTP/2 stream path plus gRPC message framing for supported proxy modes.
- QUIC: shared native dial/open-stream abstractions used by HY2 and TUIC.
- UDP: bounded datagram forwarding foundation for protocols that support UDP relay.

Acceptance:

- Transport adapters expose byte-stream interfaces suitable for local proxy and TUN forwarding.
- Performance tests cover partial frames, backpressure, and bounded buffers.

## Testing strategy

Every implementation slice must follow test-first development:

- Add failing unit tests for protocol wire bytes before production changes.
- Add adapter tests for validation, redaction, transport selection, and unsupported combinations.
- Add local proxy/runtime tests for bidirectional streaming once a protocol reaches runtime path.
- Add performance or stress tests for high-volume frame parsing and forwarding where hot paths change.
- Run targeted tests after each slice and full `swift test` before committing or merging.

Real-node tests must be opt-in via environment variables and must skip cleanly when credentials are absent.

## Release and Git workflow

Each protocol phase should land as small verified branches or PRs. Routine commits, pushes, PR creation, merge, and local cleanup may be performed autonomously after verification passes. Destructive Git operations, force pushes, credential handling, and signing decisions still require explicit confirmation.

## Acceptance criteria for the full goal

- All planned protocols have native repository-owned implementations at the runtime stream boundary.
- No planned protocol relies on plaintext foundation markers as its claimed implementation.
- No existing full proxy core or protocol library is embedded or imported.
- Local SwiftPM tests cover wire-format generation, adapter routing, redaction, runtime streaming, cancellation, and important partial read/write boundaries.
- Performance-sensitive paths use bounded buffers and avoid unnecessary hot-path allocations.
- Optional real-node validations exist for supported protocols and are credential-gated.
- `swift test` passes before every merge to `main`.
