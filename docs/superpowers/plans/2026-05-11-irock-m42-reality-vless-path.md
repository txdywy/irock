# M42 Reality Options and VLESS Reality Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add a credential-safe Reality foundation path for VLESS over TCP while preserving the standard TLS adapter's Reality rejection boundary.

**Architecture:** Implement `RealityTransportAdapter` in `IrockTransport` as a TCP transport adapter for requests with enabled TLS and non-nil `RealityOptions`. It validates Reality fields, strips TLS before opening the underlying TCP adapter, emits non-secret Reality metadata, and prefixes existing VLESS opener bytes. Wire VLESS Reality through runtime stack assembly by registering the Reality adapter for TCP when building a VLESS Reality stack.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockTransport, IrockProtocols, IrockTunnelCore.

---

## Files

- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
  - Add `RealityTransportAdapter` and private descriptor.
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`
  - Add Reality adapter tests.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Add VLESS Reality protocol routing tests and VMess/Trojan non-claim tests if needed.
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/IrockTunnelCore.swift`
  - Add VLESS Reality runtime stack/configuration helper if current stack assembly cannot register the Reality adapter.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`
  - Add VLESS Reality runtime stack tests.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m42-reality-vless-path-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m42-reality-vless-path.md`

## Task 1: Reality transport validation and opener

- [ ] **Step 1: Write failing Reality adapter tests**

Add tests to `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift` near the TLS adapter tests:

- `testRealityTransportAdapterOpensUnderlyingTCPWithCredentialSafeMetadataAndPayload`
- `testRealityTransportAdapterRejectsInvalidConfigurationBeforeOpeningUnderlying`
- `testTLSTransportAdapterStillRejectsRealityBeforeOpeningUnderlying` should remain green.

Expected behavior:

- Request must be `.tcp`.
- `tls.enabled == true` and `tls.reality != nil` are required.
- Host and port are validated.
- TLS server name is required and non-empty.
- Reality public key is required and non-empty but is not copied into metadata or opener bytes.
- Optional short ID is represented only as `realityShortIDPresent`.
- Optional spiderX and fingerprint may appear in metadata/opener because they are non-secret route/shape hints.
- Underlying request uses `.tcp`, `tls: nil`, normalized metadata, and opener prefix `reality-foundation:<serverName>:public-key-present:<shortIDPresent>:<spiderX>\n` before existing payload.

- [ ] **Step 2: Run Reality adapter tests to verify RED**

Run: `swift test --filter IrockTransportTests/testRealityTransportAdapter`

Expected: FAIL because `RealityTransportAdapter` does not exist.

- [ ] **Step 3: Implement `RealityTransportAdapter`**

Add the adapter after `TLSTransportAdapter` or near TCP/TLS selector code. Keep it explicit rather than sharing a generic descriptor abstraction with WebSocket/HTTP2/gRPC.

- [ ] **Step 4: Run Reality adapter tests to verify GREEN**

Run: `swift test --filter IrockTransportTests/testRealityTransportAdapter`

Expected: PASS.

## Task 2: VLESS Reality protocol routing

- [ ] **Step 1: Write failing VLESS Reality protocol test**

Add a test to `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` proving `VLESSProxyAdapter` can open a `.tcp` node with `tls.reality` through a TCP registry adapter and still emits credential-safe VLESS metadata and initial payload.

- [ ] **Step 2: Run VLESS Reality protocol test to verify RED or existing GREEN**

Run: `swift test --filter IrockProtocolsTests/testVLESSProxyAdapterOpensRealityTCPTransport`

Expected: If it already passes because VLESS uses `.tcp` and preserves TLS, record that as existing behavior; otherwise update VLESS validation minimally.

- [ ] **Step 3: Preserve VMess/Trojan boundaries**

If current VMess/Trojan behavior also accepts TCP + Reality incidentally, add tests documenting that M42 does not wire dedicated runtime Reality stacks for them. Do not add protocol rejection unless needed by existing architecture.

## Task 3: Runtime VLESS Reality stack assembly

- [ ] **Step 1: Write failing runtime stack test**

Add `testVLESSRealityTCPStackRoutesThroughRealityAdapter` to `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`. It should build a VLESS node with `TLSOptions(reality:)`, use the runtime helper, and assert the plain TCP child receives a request with Reality metadata and no raw public key or UUID in the synthetic opener.

- [ ] **Step 2: Run runtime Reality test to verify RED**

Run: `swift test --filter IrockTunnelCoreTests/testVLESSRealityTCPStackRoutesThroughRealityAdapter`

Expected: FAIL because no VLESS Reality runtime helper exists.

- [ ] **Step 3: Implement runtime helper**

Add `RuntimeProxyStack.vlessRealityTCP` and `TunnelRuntimeConfiguration.vlessRealityTCP` or equivalent names matching existing stack helpers. Register `RealityTransportAdapter(underlying: plainTCP)` as the `.tcp` adapter for VLESS Reality path. Keep standard `vlessTCP` unchanged.

- [ ] **Step 4: Run runtime Reality test to verify GREEN**

Run: `swift test --filter IrockTunnelCoreTests/testVLESSRealityTCPStackRoutesThroughRealityAdapter`

Expected: PASS.

## Task 4: Full verification

- [ ] **Step 1: Run transport tests**

Run: `swift test --filter IrockTransportTests`

Expected: PASS.

- [ ] **Step 2: Run protocol tests**

Run: `swift test --filter IrockProtocolsTests`

Expected: PASS.

- [ ] **Step 3: Run tunnel core tests**

Run: `swift test --filter IrockTunnelCoreTests`

Expected: PASS.

- [ ] **Step 4: Run full SwiftPM tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 5: Run platform and exposure scans**

Run shared package platform import scan and Reality source exposure scan. Expected no platform imports and no raw Reality public key, VLESS UUID, password, token, or secret values in normalized metadata/opener construction.

- [ ] **Step 6: Review, deslop, and commit**

Request independent review against M42 acceptance criteria. If approved, run bounded deslop on changed M42 files, rerun verification, update Ralph state, commit, and push.

## Self-review

- Placeholder scan: No TBD/TODO/fill-in placeholders remain.
- Scope check: Plan is limited to VLESS Reality over TCP; QUIC/Hysteria2/TUIC and UI/subscription parsing remain later milestones.
- Boundary check: Standard TLS adapter continues to reject Reality; Reality-specific behavior lives in a dedicated adapter/runtime helper.
- Credential safety: Public key presence is represented without copying key material; VLESS UUID remains omitted from metadata and opener bytes.
