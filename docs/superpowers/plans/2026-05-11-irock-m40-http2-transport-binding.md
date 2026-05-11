# M40 HTTP/2 Transport Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add an HTTP/2 transport foundation so `TransportType.http2` requests can open through existing TCP/TLS transport seams with deterministic, credential-safe metadata and synthetic opener bytes.

**Architecture:** Implement `HTTP2TransportAdapter` in `IrockTransport` as a transport-level wrapper over an underlying TCP-capable adapter, usually `TCPTLSTransportAdapter`. It validates HTTP/2-specific metadata, rewrites the underlying request to `.tcp`, preserves TLS options, and prefixes existing initial payload bytes with a synthetic HTTP/2 foundation marker.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockTransport, IrockProtocols.

---

## Files

- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
  - Add `HTTP2TransportAdapter`.
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`
  - Add HTTP/2 adapter tests.
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Allow VMess, VLESS, and Trojan foundation adapters to use `.http2`.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Add protocol foundation `.http2` routing tests.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m40-http2-transport-binding-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m40-http2-transport-binding.md`

## Task 1: HTTP/2 transport validation and opener

- [ ] **Step 1: Write failing HTTP/2 adapter tests**

Add tests to `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift` after the WebSocket adapter tests. They should mirror WebSocket tests using `HTTP2TransportAdapter`, metadata keys `http2Path`, `http2Authority`, `http2Protocol`, `http2Upgrade`, and synthetic payload prefix `http2-foundation:<authority>:<path>:<protocol>\n`.

- [ ] **Step 2: Run HTTP/2 adapter tests to verify RED**

Run: `swift test --filter IrockTransportTests/testHTTP2TransportAdapter`

Expected: FAIL because `HTTP2TransportAdapter` does not exist.

- [ ] **Step 3: Implement `HTTP2TransportAdapter`**

Add `HTTP2TransportAdapter` after `WebSocketTransportAdapter`. It should support `.http2`, validate host/port/path/authority, normalize metadata, rewrite underlying request to `.tcp`, preserve TLS, prefix `initialPayload`, and return an `EstablishedTransportConnection` with `.http2` transport.

- [ ] **Step 4: Run HTTP/2 adapter tests to verify GREEN**

Run: `swift test --filter IrockTransportTests/testHTTP2TransportAdapter`

Expected: PASS.

## Task 2: Protocol foundation HTTP/2 routing

- [ ] **Step 1: Write failing protocol routing test**

Add a test to `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` mirroring `testProtocolFoundationAdaptersOpenWebSocketTransport`, but using `.http2`.

- [ ] **Step 2: Run protocol HTTP/2 routing test to verify RED**

Run: `swift test --filter IrockProtocolsTests/testProtocolFoundationAdaptersOpenHTTP2Transport`

Expected: FAIL because VMess, VLESS, and Trojan still reject `.http2`.

- [ ] **Step 3: Allow `.http2` in VMess, VLESS, and Trojan foundation adapters**

Update validation guards to accept `.tcp`, `.webSocket`, or `.http2`.

- [ ] **Step 4: Run protocol HTTP/2 routing test to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testProtocolFoundationAdaptersOpenHTTP2Transport`

Expected: PASS.

## Task 3: Full verification

- [ ] **Step 1: Run transport tests**

Run: `swift test --filter IrockTransportTests`

Expected: PASS.

- [ ] **Step 2: Run protocol tests**

Run: `swift test --filter IrockProtocolsTests`

Expected: PASS.

- [ ] **Step 3: Run full SwiftPM tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 4: Run platform and source exposure scans**

Run platform import scan and HTTP/2 source exposure scan; expected no platform imports in shared packages and no credential fixture leakage.

- [ ] **Step 5: Review, deslop, and commit**

Request independent review against M40 acceptance criteria. If approved, run bounded deslop on changed M40 files, rerun verification, update Ralph state, commit, and push.

## Self-review

- Spec coverage: Tasks cover HTTP/2 validation, metadata normalization, synthetic opener bytes, TLS preservation, and protocol adapter routing.
- Placeholder scan: No TBD/TODO/fill-in placeholders remain; out-of-scope items are explicitly deferred.
- Type consistency: Planned symbol is `HTTP2TransportAdapter`.
