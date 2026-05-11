# irock M17 TLS Transport Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a TLS wrapper transport adapter skeleton with deterministic validation and injected underlying transport opening, without real TLS or network I/O.

**Architecture:** M17 stays inside `IrockTransport` and its tests. `TLSTransportAdapter<Underlying>` reports `.tcp`, validates TLS-bearing TCP requests, strips TLS before delegating to an injected underlying adapter, and returns the underlying endpoint as an established TCP connection.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, existing `IrockCore` and `IrockTransport` contracts.

---

## File Structure

M17 modifies these files:

```text
packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift
packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
```

Responsibilities:

- `IrockTransport.swift`: exports `TLSTransportAdapter` and keeps TLS handling in the transport package without importing platform networking/security frameworks.
- `IrockTransportTests.swift`: verifies TLS wrapper identity, validation, underlying request construction, error propagation, and registry selection.

No `Package.swift` dependency changes are expected.

---

### Task 1: Add TLS wrapper happy path

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add failing happy-path tests**

Add these tests inside `IrockTransportTests` before the closing brace:

```swift
    func testTLSTransportAdapterReportsTCPTransport() {
        let adapter = TLSTransportAdapter(underlying: RecordingTransportAdapter(transport: .tcp))

        XCTAssertEqual(adapter.supportedTransport, .tcp)
    }

    func testTLSTransportAdapterStripsTLSAndReturnsUnderlyingConnection() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp, connectionHost: "connected.example.com")
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: nil)
        let request = TransportRequest(host: " example.com ", port: 443, transport: .tcp, tls: tls, metadata: ["source": "unit-test"])

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "connected.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(underlying.requests, [TransportAdapterRequest(host: "example.com", port: 443, transport: .tcp, tls: nil, metadata: ["source": "unit-test"])])
    }
```

Replace `RecordingTransportAdapter` with this request-recording version:

```swift
private struct TransportAdapterRequest: Equatable {
    let host: String
    let port: Int
    let transport: TransportType
    let tls: TLSOptions?
    let metadata: [String: String]
}

private final class RecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    let connectionHost: String
    private let lock = NSLock()
    private var storedRequests: [TransportAdapterRequest] = []

    init(transport: TransportType, connectionHost: String = "example.com") {
        self.supportedTransport = transport
        self.connectionHost = connectionHost
    }

    var requests: [TransportAdapterRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        record(request)
        return EstablishedTransportConnection(host: connectionHost, port: request.port, transport: request.transport)
    }

    private func record(_ request: TransportRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(TransportAdapterRequest(host: request.host, port: request.port, transport: request.transport, tls: request.tls, metadata: request.metadata))
    }
}
```

- [ ] **Step 2: Run happy-path test to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests/testTLSTransportAdapterStripsTLSAndReturnsUnderlyingConnection'
```

Expected: FAIL with missing `TLSTransportAdapter`.

- [ ] **Step 3: Implement minimal TLS wrapper happy path**

Append this to `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift` after `TCPTransportAdapter`:

```swift
public struct TLSTransportAdapter<Underlying: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp
    private let underlying: Underlying

    public init(underlying: Underlying) {
        self.underlying = underlying
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let underlyingRequest = TransportRequest(host: host, port: request.port, transport: request.transport, tls: nil, metadata: request.metadata)
        let connection = try await underlying.open(request: underlyingRequest)
        return EstablishedTransportConnection(host: connection.host, port: connection.port, transport: .tcp)
    }
}
```

- [ ] **Step 4: Run TLS happy-path tests**

Run:

```bash
swift test --filter 'IrockTransportTests/testTLSTransportAdapter'
```

Expected: PASS for the two TLS happy-path tests.

- [ ] **Step 5: Commit TLS happy path**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "feat: add tls transport adapter skeleton"
```

---

### Task 2: Add TLS request validation

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add failing validation tests**

Add these tests inside `IrockTransportTests` before the closing brace:

```swift
    func testTLSTransportAdapterRejectsNonTCPBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .grpc)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(underlying.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTLSTransportAdapterRejectsMissingOrDisabledTLSBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let disabled = TLSOptions.disabled
        let requests = [
            TransportRequest(host: "example.com", port: 443, transport: .tcp),
            TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: disabled)
        ]

        for request in requests {
            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected invalid configuration")
            } catch let error as TransportError {
                XCTAssertEqual(error, .invalidConfiguration("missing tls options"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(underlying.requests, [])
    }

    func testTLSTransportAdapterRejectsEmptyHostBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "   ", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as TransportError {
            XCTAssertEqual(error, .invalidConfiguration("missing tls host"))
            XCTAssertEqual(underlying.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTLSTransportAdapterRejectsInvalidPortBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)

        for port in [0, 65_536] {
            let request = TransportRequest(host: "example.com", port: port, transport: .tcp, tls: tls)

            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected invalid configuration")
            } catch let error as TransportError {
                XCTAssertEqual(error, .invalidConfiguration("invalid tls port"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(underlying.requests, [])
    }

    func testTLSTransportAdapterRejectsEmptyServerNameBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "   ", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as TransportError {
            XCTAssertEqual(error, .invalidConfiguration("invalid tls server name"))
            XCTAssertEqual(underlying.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTLSTransportAdapterRejectsRealityBeforeOpeningUnderlying() async {
        let underlying = RecordingTransportAdapter(transport: .tcp)
        let adapter = TLSTransportAdapter(underlying: underlying)
        let reality = RealityOptions(publicKey: "public", shortID: nil, spiderX: nil)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: reality)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.tcp))
            XCTAssertEqual(underlying.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
```

- [ ] **Step 2: Run validation test to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests/testTLSTransportAdapterRejectsMissingOrDisabledTLSBeforeOpeningUnderlying'
```

Expected: FAIL because `TLSTransportAdapter` does not validate TLS options yet.

- [ ] **Step 3: Implement TLS validation**

Replace `TLSTransportAdapter.open(request:)` with:

```swift
    public func open(request: TransportRequest) async throws -> any TransportConnection {
        try validate(request)
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let underlyingRequest = TransportRequest(host: host, port: request.port, transport: request.transport, tls: nil, metadata: request.metadata)
        let connection = try await underlying.open(request: underlyingRequest)
        return EstablishedTransportConnection(host: connection.host, port: connection.port, transport: .tcp)
    }

    private func validate(_ request: TransportRequest) throws {
        guard request.transport == .tcp else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        guard let tls = request.tls, tls.enabled else {
            throw TransportError.invalidConfiguration("missing tls options")
        }
        guard !request.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransportError.invalidConfiguration("missing tls host")
        }
        guard (1...65_535).contains(request.port) else {
            throw TransportError.invalidConfiguration("invalid tls port")
        }
        if let serverName = tls.serverName, serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TransportError.invalidConfiguration("invalid tls server name")
        }
        guard tls.reality == nil else {
            throw TransportError.unsupportedTransport(.tcp)
        }
    }
```

- [ ] **Step 4: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS.

- [ ] **Step 5: Commit TLS validation**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "feat: validate tls transport requests"
```

---

### Task 3: Add TLS error propagation and registry coverage

**Files:**
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add underlying failure and registry tests**

Add these tests inside `IrockTransportTests` before the closing brace:

```swift
    func testTLSTransportAdapterPropagatesUnderlyingTransportError() async {
        let adapter = TLSTransportAdapter(underlying: FailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("handshake failed")))
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected underlying failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .tlsHandshakeFailed("handshake failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportAdapterRegistryCanSelectTLSTransportAdapter() async throws {
        let adapter = TLSTransportAdapter(underlying: RecordingTransportAdapter(transport: .tcp))
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .tcp)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .tcp)
        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
    }
```

Add this helper after `RecordingTransportAdapter`:

```swift
private struct FailingTransportAdapter: TransportAdapter {
    let supportedTransport: TransportType
    let error: TransportError

    init(transport: TransportType, error: TransportError) {
        self.supportedTransport = transport
        self.error = error
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        throw error
    }
}
```

- [ ] **Step 2: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS.

- [ ] **Step 3: Commit TLS error and registry coverage**

```bash
git add packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "test: cover tls transport adapter edges"
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

- [ ] **Step 5: Commit M17 plan**

```bash
git add docs/superpowers/plans/2026-05-11-irock-m17-tls-transport-foundation.md
git commit -m "docs: add M17 tls transport foundation plan"
```

---

## Self-Review

Spec coverage:

- TLS wrapper identity and happy path: Task 1.
- Structural TLS request validation and Reality rejection: Task 2.
- Underlying error propagation and registry lookup: Task 3.
- Full verification and dependency guard: Task 4.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: all tasks use `TLSTransportAdapter`, `TransportRequest`, `TransportConnection`, `TransportError`, `TLSOptions`, `RealityOptions`, and `TransportAdapterRegistry` consistently.
