# irock M18 TCP/TLS Transport Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single `.tcp` transport selector adapter that routes plain TCP requests to a plain child adapter and TLS-enabled TCP requests to a TLS child adapter.

**Architecture:** M18 stays inside `IrockTransport` and its tests. `TCPTLSTransportAdapter<Plain, TLS>` reports `.tcp`, rejects non-TCP requests itself, preserves the original `TransportRequest`, and delegates all plain/TLS validation plus opening to injected child adapters.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, existing `IrockCore` and `IrockTransport` contracts.

---

## File Structure

M18 modifies these files:

```text
packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift
packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
```

Responsibilities:

- `IrockTransport.swift`: exports `TCPTLSTransportAdapter` as the single registry-facing `.tcp` selector for plain-vs-TLS requests.
- `IrockTransportTests.swift`: verifies selector identity, routing decisions, request preservation, child error propagation, and registry selection.

No `Package.swift` dependency changes are expected.

---

### Task 1: Add TCP/TLS selector happy paths

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add failing selector happy-path tests**

Add these tests inside `IrockTransportTests` before the closing brace:

```swift
    func testTCPTLSTransportAdapterReportsTCPTransport() {
        let adapter = TCPTLSTransportAdapter(
            plain: RecordingTransportAdapter(transport: .tcp),
            tls: RecordingTransportAdapter(transport: .tcp)
        )

        XCTAssertEqual(adapter.supportedTransport, .tcp)
    }

    func testTCPTLSTransportAdapterRoutesPlainTCPToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp, connectionHost: "plain.example.com")
        let tls = RecordingTransportAdapter(transport: .tcp, connectionHost: "tls.example.com")
        let adapter = TCPTLSTransportAdapter(plain: plain, tls: tls)
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp, metadata: ["mode": "plain"])

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "plain.example.com")
        XCTAssertEqual(connection.port, 80)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(plain.requests, [TransportAdapterRequest(host: "example.com", port: 80, transport: .tcp, tls: nil, metadata: ["mode": "plain"])])
        XCTAssertEqual(tls.requests, [])
    }

    func testTCPTLSTransportAdapterRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp, connectionHost: "plain.example.com")
        let tlsChild = RecordingTransportAdapter(transport: .tcp, connectionHost: "tls.example.com")
        let adapter = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls, metadata: ["mode": "tls"])

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "tls.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests, [TransportAdapterRequest(host: "example.com", port: 443, transport: .tcp, tls: tls, metadata: ["mode": "tls"])])
    }
```

- [ ] **Step 2: Run selector happy-path test to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests/testTCPTLSTransportAdapterRoutesPlainTCPToPlainChild'
```

Expected: FAIL with missing `TCPTLSTransportAdapter`.

- [ ] **Step 3: Implement minimal selector adapter**

Append this to `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift` after `TLSTransportAdapter`:

```swift
public struct TCPTLSTransportAdapter<Plain: TransportAdapter, TLS: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp
    private let plain: Plain
    private let tls: TLS

    public init(plain: Plain, tls: TLS) {
        self.plain = plain
        self.tls = tls
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        if request.tls?.enabled == true {
            return try await tls.open(request: request)
        }
        return try await plain.open(request: request)
    }
}
```

- [ ] **Step 4: Run selector happy-path tests**

Run:

```bash
swift test --filter 'IrockTransportTests/testTCPTLSTransportAdapter'
```

Expected: PASS for the selector happy-path tests.

- [ ] **Step 5: Commit selector happy path**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "feat: add tcp tls transport selector"
```

---

### Task 2: Add selector routing edge cases

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add failing routing edge tests**

Add these tests inside `IrockTransportTests` before the closing brace:

```swift
    func testTCPTLSTransportAdapterRoutesDisabledTLSToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp, connectionHost: "plain.example.com")
        let tlsChild = RecordingTransportAdapter(transport: .tcp, connectionHost: "tls.example.com")
        let adapter = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp, tls: .disabled)

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "plain.example.com")
        XCTAssertEqual(plain.requests, [TransportAdapterRequest(host: "example.com", port: 80, transport: .tcp, tls: .disabled, metadata: [:])])
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testTCPTLSTransportAdapterRejectsNonTCPBeforeOpeningChildren() async {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let adapter = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(plain.requests, [])
            XCTAssertEqual(tlsChild.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
```

- [ ] **Step 2: Run non-TCP edge test to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests/testTCPTLSTransportAdapterRejectsNonTCPBeforeOpeningChildren'
```

Expected: FAIL because the selector currently delegates non-TCP requests instead of rejecting first.

- [ ] **Step 3: Add selector transport validation**

Replace `TCPTLSTransportAdapter.open(request:)` with:

```swift
    public func open(request: TransportRequest) async throws -> any TransportConnection {
        guard request.transport == .tcp else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        if request.tls?.enabled == true {
            return try await tls.open(request: request)
        }
        return try await plain.open(request: request)
    }
```

- [ ] **Step 4: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS.

- [ ] **Step 5: Commit selector edge routing**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "feat: validate tcp tls transport selection"
```

---

### Task 3: Add child error propagation and registry coverage

**Files:**
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add child error and registry tests**

Add these tests inside `IrockTransportTests` before the closing brace:

```swift
    func testTCPTLSTransportAdapterPropagatesPlainChildError() async {
        let adapter = TCPTLSTransportAdapter(
            plain: FailingTransportAdapter(transport: .tcp, error: .tcpConnectFailed("plain refused")),
            tls: RecordingTransportAdapter(transport: .tcp)
        )
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected plain child failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .tcpConnectFailed("plain refused"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTLSTransportAdapterPropagatesTLSChildError() async {
        let adapter = TCPTLSTransportAdapter(
            plain: RecordingTransportAdapter(transport: .tcp),
            tls: FailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("tls refused"))
        )
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected TLS child failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .tlsHandshakeFailed("tls refused"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportAdapterRegistryCanSelectTCPTLSTransportAdapter() async throws {
        let adapter = TCPTLSTransportAdapter(
            plain: RecordingTransportAdapter(transport: .tcp, connectionHost: "plain.example.com"),
            tls: RecordingTransportAdapter(transport: .tcp, connectionHost: "tls.example.com")
        )
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .tcp)
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .tcp)
        XCTAssertEqual(connection.host, "plain.example.com")
        XCTAssertEqual(connection.port, 80)
        XCTAssertEqual(connection.transport, .tcp)
    }
```

- [ ] **Step 2: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS.

- [ ] **Step 3: Commit selector error and registry coverage**

```bash
git add packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "test: cover tcp tls transport selector edges"
```

---

### Task 4: Final verification

**Files:**
- Verify only; no source edits expected unless verification exposes a bug.

- [ ] **Step 1: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS.

- [ ] **Step 2: Run protocol and tunnel tests**

Run:

```bash
swift test --filter IrockProtocolsTests
swift test --filter IrockTunnelCoreTests
```

Expected: PASS.

- [ ] **Step 3: Run full SwiftPM suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Verify no forbidden transport imports**

Run:

```bash
grep -R "import IrockTunnelCore\|import IrockStorage\|import IrockAppFeature\|import Network\|import Security" -n packages/IrockTransport Package.swift || true
```

Expected: no forbidden imports from `packages/IrockTransport` source or test files.

- [ ] **Step 5: Commit M18 plan**

```bash
git add docs/superpowers/plans/2026-05-11-irock-m18-tcp-tls-transport-selection.md
git commit -m "docs: add M18 tcp tls transport selection plan"
```

---

## Self-Review

Spec coverage:

- Selector identity and plain/TLS happy paths: Task 1.
- Disabled TLS routing and non-TCP rejection: Task 2.
- Child error propagation and registry lookup: Task 3.
- Full verification and dependency guard: Task 4.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: all tasks use `TCPTLSTransportAdapter`, `TransportRequest`, `TransportConnection`, `TransportError`, `TLSOptions`, and `TransportAdapterRegistry` consistently.
