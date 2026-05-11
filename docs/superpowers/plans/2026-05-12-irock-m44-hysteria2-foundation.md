# M44 Hysteria2 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add Hysteria2 protocol foundation that validates configuration and routes through the M43 QUIC transport seam with credential-safe metadata and synthetic opener bytes.

**Architecture:** Add `Hysteria2OpenRequest` and `Hysteria2ProxyAdapter` in `IrockProtocols`, plus `RuntimeProxyStack.hysteria2QUIC` and `TunnelRuntimeConfiguration.hysteria2QUIC` in `IrockTunnelCore`. Keep full Hysteria2 cryptographic handshake, UDP forwarding, URI parsing, and real QUIC sockets out of scope.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockProtocols, IrockTransport, IrockTunnelCore.

---

## Files

- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Add `Hysteria2OpenRequest` and `Hysteria2ProxyAdapter`.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Add Hysteria2 open request and adapter tests.
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift`
  - Add Hysteria2 QUIC runtime stack/configuration helpers.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`
  - Add Hysteria2 QUIC runtime assembly test.
- Create/Update: `docs/superpowers/specs/2026-05-12-irock-m44-hysteria2-foundation-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-12-irock-m44-hysteria2-foundation.md`

## Task 1: Hysteria2 open request

- [ ] **Step 1: Write failing Hysteria2 open request tests**

Add tests:

- `testHysteria2OpenRequestBuildsCredentialSafeMetadataAndPayload`
- `testHysteria2OpenRequestRejectsEmptyAuthenticationSecret`

Expected behavior:

- Non-empty auth secret is required.
- Destination description is included.
- Optional SNI is trimmed.
- Optional obfuscation value is represented only by presence.
- Metadata includes `hysteria2AuthPresent`, `hysteria2Destination`, `hysteria2SNI`, `hysteria2ObfsPresent`.
- Open bytes equal `hysteria2-foundation:<destination>:<sni>:auth-present:<obfsPresent>`.
- Open bytes and metadata do not contain the auth secret or obfuscation secret value.

- [ ] **Step 2: Run open request tests to verify RED**

Run: `swift test --filter IrockProtocolsTests/testHysteria2OpenRequest`

Expected: FAIL because `Hysteria2OpenRequest` does not exist.

- [ ] **Step 3: Implement `Hysteria2OpenRequest`**

Add minimal implementation near other protocol open request structs.

- [ ] **Step 4: Run open request tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testHysteria2OpenRequest`

Expected: PASS.

## Task 2: Hysteria2 proxy adapter

- [ ] **Step 1: Write failing adapter tests**

Add tests:

- `testHysteria2ProxyAdapterOpensQUICTransportAndReturnsProxyConnection`
- `testHysteria2ProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen`

Expected behavior:

- Protocol must be `.hysteria2`.
- Transport must be `.quic`.
- Host, port, and credential account must be valid.
- Adapter opens registry adapter for `.quic` with merged metadata and initial payload.
- Transport errors map through existing protocol error mapping.

- [ ] **Step 2: Run adapter tests to verify RED**

Run: `swift test --filter IrockProtocolsTests/testHysteria2ProxyAdapter`

Expected: FAIL because `Hysteria2ProxyAdapter` does not exist.

- [ ] **Step 3: Implement `Hysteria2ProxyAdapter`**

Use existing adapter structure from VMess/VLESS/Trojan but keep Hysteria2 limited to QUIC.

- [ ] **Step 4: Run adapter tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testHysteria2ProxyAdapter`

Expected: PASS.

## Task 3: Runtime Hysteria2 QUIC assembly

- [ ] **Step 1: Write failing runtime stack test**

Add `testHysteria2QUICStackRoutesThroughQUICTransport` to `RuntimeProxyStackTests.swift`.

Expected behavior:

- `RuntimeProxyStack.hysteria2QUIC(quic:)` registers `Hysteria2ProxyAdapter` over a `.quic` transport adapter.
- A Hysteria2 node routes through the QUIC child.
- Metadata contains `proxyProtocol: hysteria2` and Hysteria2 credential-safe keys.
- Payload does not include auth secret.

- [ ] **Step 2: Run runtime stack test to verify RED**

Run: `swift test --filter RuntimeProxyStackTests/testHysteria2QUICStackRoutesThroughQUICTransport`

Expected: FAIL because runtime helper does not exist.

- [ ] **Step 3: Implement runtime helper**

Add `RuntimeProxyStack.hysteria2QUIC` and `TunnelRuntimeConfiguration.hysteria2QUIC` helpers.

- [ ] **Step 4: Run runtime stack test to verify GREEN**

Run: `swift test --filter RuntimeProxyStackTests/testHysteria2QUICStackRoutesThroughQUICTransport`

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

Run shared package platform import scan and Hysteria2 source exposure scan. Expected no platform imports and no auth secret or obfuscation secret values in metadata/opener construction.

- [ ] **Step 5: Review, deslop, and commit**

Request independent review against M44 acceptance criteria. If approved, run bounded deslop on M44 changed files, rerun verification, update Ralph state, commit, and push.

## Self-review

- Placeholder scan: No TBD/TODO/fill-in placeholders remain.
- Scope check: Plan is limited to Hysteria2 foundation over QUIC; TUIC, UDP forwarding, platform QUIC sockets, and real-node validation remain later milestones.
- Boundary check: Hysteria2 protocol logic lives in `IrockProtocols`; QUIC transport behavior remains behind `IrockTransport` registry.
- Credential safety: Hysteria2 auth/obfs values are only validated for presence and never copied into metadata or opener bytes.
