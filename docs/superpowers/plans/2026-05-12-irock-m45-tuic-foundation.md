# M45 TUIC Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add TUIC protocol foundation that validates configuration and routes through the M43 QUIC transport seam with credential-safe metadata and synthetic opener bytes.

**Architecture:** Add `TUICOpenRequest` and `TUICProxyAdapter` in `IrockProtocols`, plus `RuntimeProxyStack.tuicQUIC` and `TunnelRuntimeConfiguration.tuicQUIC` in `IrockTunnelCore`. Keep full TUIC cryptographic handshake, UDP forwarding, URI parsing, and real QUIC sockets out of scope.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockProtocols, IrockTransport, IrockTunnelCore.

---

## Files

- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Add `TUICOpenRequest` and `TUICProxyAdapter`.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Add TUIC open request and adapter tests.
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift`
  - Add TUIC QUIC runtime stack/configuration helpers.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`
  - Add TUIC QUIC runtime assembly test.
- Create: `docs/superpowers/specs/2026-05-12-irock-m45-tuic-foundation-design.md`
- Create: `docs/superpowers/plans/2026-05-12-irock-m45-tuic-foundation.md`

## Task 1: TUIC open request

- [ ] **Step 1: Write failing TUIC open request tests**

Add tests:

- `testTUICOpenRequestBuildsCredentialSafeMetadataAndPayload`
- `testTUICOpenRequestRejectsInvalidCredentials`

Expected behavior:

- Credential format is `<uuid>:<password>`.
- UUID must be syntactically valid.
- Password must be non-empty.
- Destination description is included.
- Optional SNI is trimmed.
- Metadata includes `tuicUUIDPresent`, `tuicPasswordPresent`, `tuicDestination`, `tuicSNI`.
- Open bytes equal `tuic-foundation:<destination>:<sni>:uuid-present:password-present`.
- Open bytes and metadata do not contain UUID or password values.

- [ ] **Step 2: Run open request tests to verify RED**

Run: `swift test --filter IrockProtocolsTests/testTUICOpenRequest`

Expected: FAIL because `TUICOpenRequest` does not exist.

- [ ] **Step 3: Implement `TUICOpenRequest`**

Add minimal implementation near other protocol open request structs.

- [ ] **Step 4: Run open request tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testTUICOpenRequest`

Expected: PASS.

## Task 2: TUIC proxy adapter

- [ ] **Step 1: Write failing adapter tests**

Add tests:

- `testTUICProxyAdapterOpensQUICTransportAndReturnsProxyConnection`
- `testTUICProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen`

Expected behavior:

- Protocol must be `.tuic`.
- Transport must be `.quic`.
- Host, port, UUID/password credential, and QUIC transport must be valid.
- Adapter opens registry adapter for `.quic` with merged metadata and initial payload.
- Transport errors map through existing protocol error mapping.

- [ ] **Step 2: Run adapter tests to verify RED**

Run: `swift test --filter IrockProtocolsTests/testTUICProxyAdapter`

Expected: FAIL because `TUICProxyAdapter` does not exist.

- [ ] **Step 3: Implement `TUICProxyAdapter`**

Use the Hysteria2 adapter structure but keep TUIC limited to QUIC and credential-safe UUID/password handling.

- [ ] **Step 4: Run adapter tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testTUICProxyAdapter`

Expected: PASS.

## Task 3: Runtime TUIC QUIC assembly

- [ ] **Step 1: Write failing runtime stack test**

Add `testTUICQUICStackRoutesThroughQUICTransport` to `RuntimeProxyStackTests.swift`.

Expected behavior:

- `RuntimeProxyStack.tuicQUIC(quic:)` registers `TUICProxyAdapter` over a `.quic` transport adapter.
- A TUIC node routes through the QUIC child.
- Metadata contains `proxyProtocol: tuic` and TUIC credential-safe keys.
- Payload does not include UUID or password.

- [ ] **Step 2: Run runtime stack test to verify RED**

Run: `swift test --filter RuntimeProxyStackTests/testTUICQUICStackRoutesThroughQUICTransport`

Expected: FAIL because runtime helper does not exist.

- [ ] **Step 3: Implement runtime helper**

Add `RuntimeProxyStack.tuicQUIC` and `TunnelRuntimeConfiguration.tuicQUIC` helpers.

- [ ] **Step 4: Run runtime stack test to verify GREEN**

Run: `swift test --filter RuntimeProxyStackTests/testTUICQUICStackRoutesThroughQUICTransport`

Expected: PASS.

## Task 4: Full verification

- [ ] **Step 1: Run protocol tests**

Run: `swift test --filter IrockProtocolsTests`

Expected: PASS.

- [ ] **Step 2: Run tunnel core tests**

Run: `swift test --filter IrockTunnelCoreTests`

Expected: PASS.

- [ ] **Step 3: Run full SwiftPM tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 4: Run static scans**

Run shared package platform import scan and TUIC source exposure scan. Expected no platform imports and no UUID/password credential values in metadata/opener construction.

- [ ] **Step 5: Review, deslop, and commit**

Request independent review against M45 acceptance criteria. If approved, run bounded deslop on M45 changed files, rerun verification, update Ralph state, commit, and push.

## Self-review

- Placeholder scan: No TBD/TODO/fill-in placeholders remain.
- Scope check: Plan is limited to TUIC foundation over QUIC; UDP forwarding, platform QUIC sockets, and real-node validation remain later milestones.
- Boundary check: TUIC protocol logic lives in `IrockProtocols`; QUIC transport behavior remains behind `IrockTransport` registry.
- Credential safety: TUIC UUID/password values are only validated and never copied into metadata or opener bytes.
