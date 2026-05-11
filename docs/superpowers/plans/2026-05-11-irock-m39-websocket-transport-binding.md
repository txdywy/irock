# M39 WebSocket Transport Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add a WebSocket transport foundation so `TransportType.webSocket` requests can open through existing TCP/TLS transport seams with deterministic, credential-safe metadata and synthetic opener bytes.

**Architecture:** Implement `WebSocketTransportAdapter` in `IrockTransport` as a transport-level wrapper over an underlying TCP-capable adapter, usually `TCPTLSTransportAdapter`. It validates WebSocket-specific metadata, rewrites the underlying request to `.tcp`, preserves TLS options, and prefixes existing initial payload bytes with a synthetic WebSocket foundation marker.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockTransport.

---

## Files

- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
  - Add `WebSocketTransportAdapter`.
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`
  - Add WebSocket adapter tests.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m39-websocket-transport-binding-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m39-websocket-transport-binding.md`

## Task 1: WebSocket transport validation and opener

- [ ] **Step 1: Write failing WebSocket adapter tests**

Add tests to `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift` after the TCP/TLS selector tests:

```swift
func testWebSocketTransportAdapterOpensUnderlyingTCPWithMetadataAndPayload() async throws {
    let underlying = RecordingTransportAdapter(transport: .tcp, connectionHost: "connected.example.com")
    let adapter = WebSocketTransportAdapter(underlying: underlying)
    let payload = Data("protocol-open".utf8)
    let request = TransportRequest(
        host: " example.com ",
        port: 443,
        transport: .webSocket,
        tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
        metadata: ["webSocketPath": "/proxy", "webSocketProtocol": "vmess"],
        initialPayload: payload
    )

    let connection = try await adapter.open(request: request)

    XCTAssertEqual(connection.host, "connected.example.com")
    XCTAssertEqual(connection.port, 443)
    XCTAssertEqual(connection.transport, .webSocket)
    XCTAssertEqual(underlying.requests.count, 1)
    XCTAssertEqual(underlying.requests.first?.host, "example.com")
    XCTAssertEqual(underlying.requests.first?.port, 443)
    XCTAssertEqual(underlying.requests.first?.transport, .tcp)
    XCTAssertEqual(underlying.requests.first?.tls, request.tls)
    XCTAssertEqual(underlying.requests.first?.metadata["webSocketHost"], "example.com")
    XCTAssertEqual(underlying.requests.first?.metadata["webSocketPath"], "/proxy")
    XCTAssertEqual(underlying.requests.first?.metadata["webSocketProtocol"], "vmess")
    XCTAssertEqual(underlying.requests.first?.metadata["webSocketUpgrade"], "true")
    XCTAssertEqual(String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8), "websocket-foundation:example.com:/proxy:vmess\nprotocol-open")
}

func testWebSocketTransportAdapterDefaultsPathAndHostMetadata() async throws {
    let underlying = RecordingTransportAdapter(transport: .tcp)
    let adapter = WebSocketTransportAdapter(underlying: underlying)
    let request = TransportRequest(host: "example.com", port: 80, transport: .webSocket)

    _ = try await adapter.open(request: request)

    XCTAssertEqual(underlying.requests.first?.metadata["webSocketHost"], "example.com")
    XCTAssertEqual(underlying.requests.first?.metadata["webSocketPath"], "/")
    XCTAssertNil(underlying.requests.first?.metadata["webSocketProtocol"])
    XCTAssertEqual(String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8), "websocket-foundation:example.com:/:\n")
}

func testWebSocketTransportAdapterRejectsInvalidConfigurationBeforeOpeningUnderlying() async {
    let cases: [(TransportRequest, TransportError)] = [
        (TransportRequest(host: "example.com", port: 443, transport: .tcp), .unsupportedTransport(.tcp)),
        (TransportRequest(host: "   ", port: 443, transport: .webSocket), .invalidConfiguration("missing websocket host")),
        (TransportRequest(host: "example.com", port: 0, transport: .webSocket), .invalidConfiguration("invalid websocket port")),
        (TransportRequest(host: "example.com", port: 443, transport: .webSocket, metadata: ["webSocketPath": "proxy"]), .invalidConfiguration("invalid websocket path")),
        (TransportRequest(host: "example.com", port: 443, transport: .webSocket, metadata: ["webSocketHost": "   "]), .invalidConfiguration("invalid websocket host header"))
    ]

    for (request, expectedError) in cases {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = WebSocketTransportAdapter(underlying: underlying)
        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected WebSocket validation failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, expectedError)
            XCTAssertEqual(underlying.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run WebSocket adapter tests to verify RED**

Run: `swift test --filter IrockTransportTests/testWebSocketTransportAdapter`

Expected: FAIL because `WebSocketTransportAdapter` does not exist.

- [ ] **Step 3: Implement `WebSocketTransportAdapter`**

Add `WebSocketTransportAdapter` after `TCPTLSTransportAdapter`. It should support `.webSocket`, validate host/port/path/host-header, normalize metadata, rewrite underlying request to `.tcp`, preserve TLS, prefix `initialPayload` with `websocket-foundation:<host>:<path>:<protocol>\n`, and return an `EstablishedTransportConnection` with `.webSocket` transport.

- [ ] **Step 4: Run WebSocket adapter tests to verify GREEN**

Run: `swift test --filter IrockTransportTests/testWebSocketTransportAdapter`

Expected: PASS.

## Task 2: Full verification

- [ ] **Step 1: Run transport tests**

Run: `swift test --filter IrockTransportTests`

Expected: PASS.

- [ ] **Step 2: Run full SwiftPM tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 3: Run platform and credential scans**

Run platform import scan and WebSocket source exposure scan; expected no platform imports in shared packages and no credential fixture leakage.

- [ ] **Step 4: Review, deslop, and commit**

Request independent review against M39 acceptance criteria. If approved, run bounded deslop on changed M39 files, rerun verification, update Ralph state, commit, and push.

## Verification Evidence

Recorded during M39 implementation on 2026-05-11:

- `swift test --filter IrockTransportTests`: passed, 38 tests, 0 failures.
- `swift test --filter IrockProtocolsTests`: passed, 49 tests, 0 failures.
- `swift test`: passed, 266 tests, 0 failures.
- `git diff --check`: passed with no whitespace errors.
- Shared package platform import scan for `Network`, `NetworkExtension`, `UIKit`, `AppKit`, and `Security`: clean.
- M39 source exposure scan: WebSocket source contains no credential fixture values; broader protocol source matches are existing Shadowsocks/Trojan credential handling, not WebSocket metadata or opener construction.
- LSP diagnostics: no error diagnostics in changed `IrockTransport.swift` or `IrockProtocols.swift`.

## Self-review

- Spec coverage: Tasks cover WebSocket validation, metadata normalization, synthetic opener bytes, TLS preservation, and underlying TCP/TLS routing.
- Placeholder scan: No TBD/TODO/fill-in placeholders remain; out-of-scope items are explicitly deferred.
- Type consistency: Planned symbol is `WebSocketTransportAdapter`.
