# M48 Diagnostics and User-Facing Failure Taxonomy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add a stable, credential-safe diagnostics taxonomy and wire app-facing failure paths to it.

**Architecture:** Keep taxonomy in `IrockDiagnostics`; use it at app/runtime presentation boundaries. Do not replace internal protocol, transport, routing, or storage error types.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockDiagnostics, IrockAppFeature, IrockProtocols, IrockTransport, IrockRouting.

---

## Files

- Modify: `Package.swift`
  - Add minimal diagnostics dependencies needed for taxonomy tests/implementation.
- Modify: `packages/IrockDiagnostics/Sources/IrockDiagnostics/IrockDiagnostics.swift`
  - Add failure source/message taxonomy and credential-safe mappers.
- Modify: `packages/IrockDiagnostics/Tests/IrockDiagnosticsTests/IrockDiagnosticsTests.swift`
  - Add taxonomy and redaction regression tests.
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`
  - Replace raw error interpolation in routing/status/log failure paths with taxonomy messages.
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/RuntimeSnapshotPublisher.swift`
  - Replace raw storage error interpolation with taxonomy message.
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`
  - Add/adjust app-facing diagnostics regression tests.
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/RuntimeSnapshotPublisherTests.swift`
  - Add/adjust storage failure regression test.
- Create: `docs/superpowers/specs/2026-05-12-irock-m48-diagnostics-failure-taxonomy-design.md`
- Create: `docs/superpowers/plans/2026-05-12-irock-m48-diagnostics-failure-taxonomy.md`

## Task 1: Diagnostics taxonomy

- [ ] Write failing taxonomy tests for protocol, transport, routing, storage, and runtime messages.
- [ ] Run: `swift test --filter IrockDiagnosticsTests/testDiagnosticTaxonomy`
- [ ] Implement minimal taxonomy.
- [ ] Re-run focused diagnostics tests to GREEN.

## Task 2: App-facing failure mapping

- [ ] Write failing AppFeature tests proving routing/status/log/storage failures return stable messages and do not contain secret-like associated strings.
- [ ] Run focused AppFeature tests to verify RED.
- [ ] Replace raw `String(describing: error)` usage at user-facing boundaries.
- [ ] Re-run focused AppFeature tests to GREEN.

## Task 3: Verification

- [ ] Run `swift test --filter IrockDiagnosticsTests`.
- [ ] Run `swift test --filter IrockAppFeatureTests`.
- [ ] Run full `swift test`.
- [ ] Run source exposure scan for representative secret strings.
- [ ] Run signing/credential artifact scan.
- [ ] Request independent review against M48 acceptance criteria.
- [ ] Run bounded deslop on M48 changed files only.
- [ ] Re-run post-deslop regression tests/scans.
- [ ] Update Ralph state, commit, and push.

## Self-review

- Scope check: no telemetry, analytics, localization catalog, or UI redesign was added.
- Boundary check: taxonomy is presentation-facing and does not replace internal error enums.
- Credential safety: user-facing messages do not copy raw associated strings, rule text, credentials, URLs, or tokens.
