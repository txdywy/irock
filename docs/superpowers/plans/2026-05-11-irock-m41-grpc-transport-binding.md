# M41 gRPC Transport Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add a gRPC transport foundation so `TransportType.grpc` requests can open through existing TCP/TLS transport seams with deterministic, credential-safe metadata and synthetic opener bytes.

**Architecture:** Implement `GRPCTransportAdapter` in `IrockTransport` as a transport-level wrapper over an underlying TCP-capable adapter, usually `TCPTLSTransportAdapter`. It validates gRPC-specific metadata, rewrites the underlying request to `.tcp`, preserves TLS options, and prefixes existing initial payload bytes with a synthetic gRPC foundation marker.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockTransport, IrockProtocols.

---

## Files

- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
  - Add `GRPCTransportAdapter`.
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`
  - Add gRPC adapter tests.
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Allow VMess, VLESS, and Trojan foundation adapters to use `.grpc`.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Add protocol foundation `.grpc` routing tests.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m41-grpc-transport-binding-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m41-grpc-transport-binding.md`

## Task 1: gRPC transport validation and opener

- [ ] **Step 1: Write failing gRPC adapter tests**

Add tests to `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift` after the HTTP/2 adapter tests. They should mirror HTTP/2 tests using `GRPCTransportAdapter`, metadata keys `grpcService`, `grpcAuthority`, `grpcProtocol`, `grpcUpgrade`, and synthetic payload prefix `grpc-foundation:<authority>:<service>:<protocol>\n`.

- [ ] **Step 2: Run gRPC adapter tests to verify RED**

Run: `swift test --filter IrockTransportTests/testGRPCTransportAdapter`

Expected: FAIL because `GRPCTransportAdapter` does not exist.

- [ ] **Step 3: Implement `GRPCTransportAdapter`**

Add `GRPCTransportAdapter` after `HTTP2TransportAdapter`. It should support `.grpc`, validate host/port/service/authority, normalize metadata, rewrite underlying request to `.tcp`, preserve TLS, prefix `initialPayload`, and return an `EstablishedTransportConnection` with `.grpc` transport.

- [ ] **Step 4: Run gRPC adapter tests to verify GREEN**

Run: `swift test --filter IrockTransportTests/testGRPCTransportAdapter`

Expected: PASS.

## Task 2: Protocol foundation gRPC routing

- [ ] **Step 1: Write failing protocol routing test**

Add a test to `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` mirroring `testProtocolFoundationAdaptersOpenHTTP2Transport`, but using `.grpc`.

- [ ] **Step 2: Run protocol gRPC routing test to verify RED**

Run: `swift test --filter IrockProtocolsTests/testProtocolFoundationAdaptersOpenGRPCTransport`

Expected: FAIL because VMess, VLESS, and Trojan still reject `.grpc`.

- [ ] **Step 3: Allow `.grpc` in VMess, VLESS, and Trojan foundation adapters**

Update validation guards to accept `.tcp`, `.webSocket`, `.http2`, or `.grpc`.

- [ ] **Step 4: Run protocol gRPC routing test to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testProtocolFoundationAdaptersOpenGRPCTransport`

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

Run platform import scan and gRPC source exposure scan; expected no platform imports in shared packages and no credential fixture leakage.

- [ ] **Step 5: Review, deslop, and commit**

Request independent review against M41 acceptance criteria. If approved, run bounded deslop on changed M41 files, rerun verification, update Ralph state, commit, and push.

## Self-review

- Spec coverage: Tasks cover gRPC validation, metadata normalization, synthetic opener bytes, TLS preservation, and protocol adapter routing.
- Placeholder scan: No TBD/TODO/fill-in placeholders remain; out-of-scope items are explicitly deferred.
- Type consistency: Planned symbol is `GRPCTransportAdapter`.
