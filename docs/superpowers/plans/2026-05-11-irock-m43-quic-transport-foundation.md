# M43 QUIC Transport Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add a QUIC transport foundation so later Hysteria2 and TUIC milestones can depend on a stable `TransportType.quic` seam without platform imports in shared packages.

**Architecture:** Add `QUICDialer`, `QUICDialResult`, and `QUICTransportAdapter` to `IrockTransport`. The adapter validates `.quic` requests, normalizes credential-safe metadata, prefixes existing initial payload bytes with deterministic QUIC foundation bytes, delegates to the dialer, and returns an established `.quic` connection.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockTransport.

---

## Files

- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
  - Add `QUICDialer`, `QUICDialResult`, `QUICTransportAdapter`, and private descriptor.
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`
  - Add QUIC adapter tests and test dialers.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m43-quic-transport-foundation-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m43-quic-transport-foundation.md`

## Task 1: QUIC adapter validation and dialer delegation

- [ ] **Step 1: Write failing QUIC adapter tests**

Add tests to `IrockTransportTests.swift` after the TCP/TLS/Reality transport tests:

- `testQUICTransportAdapterDialsWithMetadataAndPayload`
- `testQUICTransportAdapterDefaultsServerNameAndALPNMetadata`
- `testQUICTransportAdapterRejectsInvalidConfigurationBeforeDialing`
- `testQUICTransportAdapterPropagatesDialerTransportError`

Expected behavior:

- Request must be `.quic`.
- Host must trim to non-empty.
- Port must be 1...65535.
- `quicServerName` defaults to trimmed host and must be non-empty if provided.
- `quicProtocol` is optional and trimmed.
- ALPN comes from metadata `quicALPN` if present, otherwise from `request.tls?.alpn` if non-empty.
- Dialer receives normalized host, port, metadata, and initial payload prefixed with `quic-foundation:<serverName>:<protocol>:<alpn>\n`.
- Returned connection transport is `.quic`.
- Dialer errors propagate unchanged.

- [ ] **Step 2: Run QUIC adapter tests to verify RED**

Run: `swift test --filter IrockTransportTests/testQUICTransportAdapter`

Expected: FAIL because `QUICTransportAdapter` and `QUICDialer` do not exist.

- [ ] **Step 3: Implement QUIC foundation types**

Add minimal production code in `IrockTransport.swift`:

- `QUICDialResult`
- `QUICDialer`
- `QUICTransportAdapter<Dialer: QUICDialer>`
- private `QUICOpenDescriptor`

Do not import platform frameworks or implement real QUIC sockets.

- [ ] **Step 4: Run QUIC adapter tests to verify GREEN**

Run: `swift test --filter IrockTransportTests/testQUICTransportAdapter`

Expected: PASS.

## Task 2: Full verification

- [ ] **Step 1: Run transport tests**

Run: `swift test --filter IrockTransportTests`

Expected: PASS.

- [ ] **Step 2: Run full SwiftPM tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 3: Run static scans**

Run shared package platform import scan and QUIC source exposure scan. Expected no platform imports and no credential-like fixture values in QUIC metadata/opener construction.

- [ ] **Step 4: Review, deslop, and commit**

Request independent review against M43 acceptance criteria. If approved, run bounded deslop on M43 changed files, rerun verification, update Ralph state, commit, and push.

## Self-review

- Placeholder scan: No TBD/TODO/fill-in placeholders remain.
- Scope check: Plan is limited to QUIC transport foundation; Hysteria2, TUIC, UDP forwarding, and platform QUIC sockets remain later milestones.
- Boundary check: No Network/NetworkExtension/UIKit/AppKit/Security imports are added to shared packages.
- Credential safety: QUIC opener and metadata contain only server name/protocol/ALPN foundation values, never credentials or account identifiers.
