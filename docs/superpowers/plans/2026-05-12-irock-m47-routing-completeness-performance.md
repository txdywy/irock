# M47 Routing Completeness and Performance Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Harden routing completeness and add automatable rule-matching performance evidence suitable for Packet Tunnel hot paths.

**Architecture:** Keep routing semantics in `IrockRouting`. Keep performance budget evidence in tests/tooling without introducing platform APIs or speculative routing data structures.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockRouting, IrockPerformanceKit.

---

## Files

- Modify: `packages/IrockRouting/Tests/IrockRoutingTests/IrockRoutingTests.swift`
  - Add completeness tests for direct/proxy/reject actions, precedence, malformed input, default behavior, and CIDR boundaries.
- Modify: `packages/IrockPerformanceKit/Tests/IrockPerformanceKitTests/IrockPerformanceKitTests.swift`
  - Add routing lookup performance budget evidence test.
- Modify if needed: `Package.swift`
  - Add `IrockRouting` as a test-only dependency of `IrockPerformanceKitTests` if the performance test uses the real routing engine.
- Create: `docs/superpowers/specs/2026-05-12-irock-m47-routing-completeness-performance-design.md`
- Create: `docs/superpowers/plans/2026-05-12-irock-m47-routing-completeness-performance.md`

## Task 1: Routing semantic completeness

- [ ] **Step 1: Add routing completeness tests**

Add tests covering:

- Domain, suffix, keyword, CIDR, final, and default paths can return direct/proxy/reject.
- Domain suffix matches the root suffix host and subdomains.
- `/0` CIDR matches any valid IPv4 address.
- `/32` CIDR matches only the exact IPv4 address.
- Invalid IP input does not match CIDR rules and falls through.
- First matching rule wins even when a later rule is more specific.
- `FINAL` terminates evaluation before later rules.

- [ ] **Step 2: Run routing completeness tests**

Run: `swift test --filter IrockRoutingTests/testRoutingCompleteness`

Expected: PASS if existing behavior satisfies the stronger characterization; otherwise implement minimal routing fix.

## Task 2: Malformed routing input hardening

- [ ] **Step 1: Add malformed input tests**

Add tests covering:

- `FINAL,` rejects empty action.
- `FINAL,PROXY,extra` rejects invalid field count.
- `DOMAIN,example.com,DIRECT,extra` rejects invalid field count.
- Empty non-final value rejects with line number.
- Invalid CIDR rejects with line number and value.
- Lowercase/mixed-case supported type/action parse successfully.

- [ ] **Step 2: Run malformed input tests**

Run: `swift test --filter IrockRoutingTests/testRoutingParser`

Expected: PASS if current parser already satisfies the behavior; otherwise implement minimal fix.

## Task 3: Routing performance evidence

- [ ] **Step 1: Add performance budget test**

Add a SwiftPM test that builds a deterministic generated ruleset and resolves many routing contexts through the real `RoutingEngine`, recording average lookup nanoseconds and asserting it stays under a conservative Alpha budget.

- [ ] **Step 2: Run performance test**

Run: `swift test --filter IrockPerformanceKitTests/testRoutingLookupPerformanceBudget`

Expected: RED if `IrockPerformanceKitTests` cannot import/use routing yet, then add minimal test dependency wiring; GREEN after wiring and/or minimal budget adjustment.

## Task 4: Full verification

- [ ] Run `swift test --filter IrockRoutingTests`.
- [ ] Run `swift test --filter IrockPerformanceKitTests`.
- [ ] Run full `swift test`.
- [ ] Run shared package platform import scan.
- [ ] Request independent review against M47 acceptance criteria.
- [ ] Run bounded deslop on M47 changed files only.
- [ ] Re-run post-deslop regression tests/scans.
- [ ] Update Ralph state, commit, and push.

## Self-review

- Scope check: no GeoIP/geosite provider, UI editor, platform Packet Tunnel integration, or speculative routing trie/radix implementation was added.
- Boundary check: routing behavior remains in `IrockRouting`; performance evidence remains automatable and platform-neutral.
- Hot-path check: tests protect first-match semantics before future lookup optimization work.
