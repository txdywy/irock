# M46 UDP Forwarding Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add explicit bounded UDP forwarding decisions and regression coverage for UDP-enabled proxy requests and UDP-unsupported runtime failures.

**Architecture:** Keep UDP logic in `IrockTunnelCore` shared package. Model UDP forwarding decisions without adding platform UDP sockets, protocol datagram relays, or response synthesis.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockProtocols, IrockRouting, IrockTunnelCore.

---

## Files

- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketProcessor.swift`
  - Add `UDPForwardingDecision` and decision derivation from `PacketProcessingResult`.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketProcessorTests.swift`
  - Add UDP forwarding decision tests for direct, proxy enabled, proxy unsupported, reject, and drop.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/ProxyOutboundTests.swift`
  - Add UDP enabled proxy request construction test.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift`
  - Add UDP unsupported runtime failure/status regression test.
- Create: `docs/superpowers/specs/2026-05-12-irock-m46-udp-forwarding-foundation-design.md`
- Create: `docs/superpowers/plans/2026-05-12-irock-m46-udp-forwarding-foundation.md`

## Task 1: UDP forwarding decision model

- [ ] **Step 1: Write failing UDP forwarding decision tests**

Add tests covering:

- UDP direct result maps to `.direct`.
- UDP proxy result with node UDP enabled maps to `.proxy`.
- UDP proxy result with node UDP disabled maps to `.unsupported`.
- UDP rule reject maps to `.reject`.
- Malformed packet drop maps to `.drop`.
- TCP result returns `nil`.

- [ ] **Step 2: Run decision tests to verify RED**

Run: `swift test --filter PacketProcessorTests/testUDPForwardingDecision`

Expected: FAIL because the UDP decision API does not exist.

- [ ] **Step 3: Implement minimal decision model**

Add `UDPForwardingDecision` and a `PacketProcessingResult.udpForwardingDecision(udpPolicy:)` helper.

- [ ] **Step 4: Run decision tests to verify GREEN**

Run: `swift test --filter PacketProcessorTests/testUDPForwardingDecision`

Expected: PASS.

## Task 2: UDP enabled proxy outbound

- [ ] **Step 1: Write failing proxy outbound test**

Add a test that a UDP packet with selected node `udpPolicy: .enabled` calls the proxy adapter with UDP destination and `transportProtocol: udp` metadata.

- [ ] **Step 2: Run proxy outbound test to verify RED/GREEN**

If existing behavior already satisfies the test, record it as an existing-green characterization and keep the test as regression coverage. Otherwise implement the minimal fix.

Run: `swift test --filter ProxyOutboundTests/testConnectBuildsUDPProxyRequestWhenNodeEnablesUDP`

## Task 3: Runtime UDP unsupported failure reporting

- [ ] **Step 1: Write runtime failure regression test**

Add a test where a UDP proxy packet is processed through a node with UDP disabled and runtime reports failed status/log.

- [ ] **Step 2: Run runtime test to verify RED/GREEN**

If existing runtime already satisfies the test, record it as existing-green characterization. Otherwise implement the minimal fix.

Run: `swift test --filter PacketTunnelRuntimeTests/testRuntimePublishesFailedStatusAndLogWhenUDPProxyIsUnsupported`

## Task 4: Full verification

- [ ] Run `swift test --filter IrockTunnelCoreTests`.
- [ ] Run full `swift test`.
- [ ] Run shared package platform import scan.
- [ ] Request independent review against M46 acceptance criteria.
- [ ] Run bounded deslop on M46 changed files only.
- [ ] Re-run post-deslop regression tests/scans.
- [ ] Update Ralph state, commit, and push.

## Self-review

- Scope check: no real UDP socket, protocol datagram relay, DNS proxy, or response packet synthesis was added.
- Boundary check: UDP forwarding foundation remains in `IrockTunnelCore`; platform APIs remain outside shared packages.
- Boundedness check: decisions are per packet/result and do not introduce unbounded buffering, sessions, or logs.
