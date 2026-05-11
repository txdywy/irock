# irock M16 TCP Transport Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a TCP-specific transport adapter skeleton with validation, injectable dialing, and deterministic transport errors without real network I/O.

**Architecture:** M16 stays inside `IrockTransport` and its tests. It introduces `TCPDialResult`, `TCPDialer`, and generic `TCPTransportAdapter<Dialer>`, using injected dialers for tests and future real network integration while keeping stream/socket behavior out of scope.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, existing `IrockCore` and `IrockTransport` contracts.

---

## File Structure

M16 modifies these files:

```text
packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift
packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
```

Responsibilities:

- `IrockTransport.swift`: exports TCP dial result, dialer protocol, and `TCPTransportAdapter`.
- `IrockTransportTests.swift`: verifies TCP adapter validation, dialer injection, error propagation, and registry selection.

No `Package.swift` dependency changes are expected.

---

### Task 1: Add TCP dialer and happy path

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add failing happy-path tests**

Add these tests inside `IrockTransportTests` before the closing brace:

```swift
    func testTCPTransportAdapterReportsSupportedTransport() {
        let adapter = TCPTransportAdapter(dialer: RecordingTCPDialer())

        XCTAssertEqual(adapter.supportedTransport, .tcp)
    }

    func testTCPTransportAdapterDialsHostAndPortAndReturnsConnection() async throws {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(dialer.requests, [TCPDialRequest(host: "example.com", port: 443)])
    }
```

Add these helpers after `RecordingTransportAdapter`:

```swift
private struct TCPDialRequest: Equatable {
    let host: String
    let port: Int
}

private final class RecordingTCPDialer: TCPDialer, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [TCPDialRequest] = []

    var requests: [TCPDialRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func open(host: String, port: Int) async throws -> TCPDialResult {
        record(host: host, port: port)
        return TCPDialResult(host: host, port: port)
    }

    private func record(host: String, port: Int) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(TCPDialRequest(host: host, port: port))
    }
}
```

- [ ] **Step 2: Run happy-path test to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests/testTCPTransportAdapterDialsHostAndPortAndReturnsConnection'
```

Expected: FAIL with missing `TCPTransportAdapter`, `TCPDialer`, and `TCPDialResult`.

- [ ] **Step 3: Implement minimal TCP adapter happy path**

Append this to `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift` after `TransportAdapterRegistry`:

```swift
public struct TCPDialResult: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public protocol TCPDialer: Sendable {
    func open(host: String, port: Int) async throws -> TCPDialResult
}

public struct TCPTransportAdapter<Dialer: TCPDialer>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp
    private let dialer: Dialer

    public init(dialer: Dialer) {
        self.dialer = dialer
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        let result = try await dialer.open(host: request.host, port: request.port)
        return EstablishedTransportConnection(host: result.host, port: result.port, transport: .tcp)
    }
}
```

- [ ] **Step 4: Run happy-path tests**

Run:

```bash
swift test --filter 'IrockTransportTests/testTCPTransportAdapter'
```

Expected: PASS for the two TCP happy-path tests.

- [ ] **Step 5: Commit TCP happy path**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "feat: add tcp transport adapter skeleton"
```

---

### Task 2: Add TCP request validation

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add failing validation tests**

Add these tests inside `IrockTransportTests` before the closing brace:

```swift
    func testTCPTransportAdapterRejectsNonTCPBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(dialer.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTransportAdapterRejectsEmptyHostBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let request = TransportRequest(host: "   ", port: 443, transport: .tcp)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as TransportError {
            XCTAssertEqual(error, .invalidConfiguration("missing tcp host"))
            XCTAssertEqual(dialer.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTransportAdapterRejectsInvalidPortBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)

        for port in [0, 65_536] {
            let request = TransportRequest(host: "example.com", port: port, transport: .tcp)

            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected invalid configuration")
            } catch let error as TransportError {
                XCTAssertEqual(error, .invalidConfiguration("invalid tcp port"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(dialer.requests, [])
    }

    func testTCPTransportAdapterRejectsTLSBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.tcp))
            XCTAssertEqual(dialer.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
```

- [ ] **Step 2: Run validation test to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests/testTCPTransportAdapterRejectsEmptyHostBeforeDialing'
```

Expected: FAIL because the adapter does not validate host/port/transport/TLS yet.

- [ ] **Step 3: Implement validation**

Replace `TCPTransportAdapter.open(request:)` with:

```swift
    public func open(request: TransportRequest) async throws -> any TransportConnection {
        try validate(request)
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await dialer.open(host: host, port: request.port)
        return EstablishedTransportConnection(host: result.host, port: result.port, transport: .tcp)
    }

    private func validate(_ request: TransportRequest) throws {
        guard request.transport == .tcp else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        guard !request.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransportError.invalidConfiguration("missing tcp host")
        }
        guard (1...65_535).contains(request.port) else {
            throw TransportError.invalidConfiguration("invalid tcp port")
        }
        guard request.tls == nil else {
            throw TransportError.unsupportedTransport(.tcp)
        }
    }
```

Add this import to the top of `IrockTransport.swift`:

```swift
import Foundation
```

- [ ] **Step 4: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS.

- [ ] **Step 5: Commit validation**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "feat: validate tcp transport requests"
```

---

### Task 3: Add dialer error propagation and registry coverage

**Files:**
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add dialer failure test**

Add this test inside `IrockTransportTests` before the closing brace:

```swift
    func testTCPTransportAdapterPropagatesDialerTransportError() async {
        let adapter = TCPTransportAdapter(dialer: FailingTCPDialer(error: .tcpConnectFailed("connection refused")))
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected dialer failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .tcpConnectFailed("connection refused"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
```

Add this helper after `RecordingTCPDialer`:

```swift
private struct FailingTCPDialer: TCPDialer {
    let error: TransportError

    func open(host: String, port: Int) async throws -> TCPDialResult {
        throw error
    }
}
```

- [ ] **Step 2: Add registry selection test**

Add this test inside `IrockTransportTests` before the closing brace:

```swift
    func testTransportAdapterRegistryCanSelectTCPTransportAdapter() async throws {
        let adapter = TCPTransportAdapter(dialer: RecordingTCPDialer())
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .tcp)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .tcp)
        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
    }
```

- [ ] **Step 3: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS.

- [ ] **Step 4: Commit dialer and registry coverage**

```bash
git add packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "test: cover tcp transport dialer errors"
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
grep -R "import IrockTunnelCore\|import IrockStorage\|import IrockAppFeature\|import Network" -n packages/IrockTransport Package.swift || true
```

Expected: no forbidden imports from `packages/IrockTransport` source or test files.

- [ ] **Step 5: Commit M16 docs**

```bash
git add docs/superpowers/specs/2026-05-11-irock-m16-tcp-transport-foundation-design.md docs/superpowers/plans/2026-05-11-irock-m16-tcp-transport-foundation.md
git commit -m "docs: add M16 tcp transport foundation plan"
```

---

## Self-Review

Spec coverage:

- TCP adapter identity and happy path: Task 1.
- Structural request validation and no TLS in M16: Task 2.
- Dialer error propagation and registry lookup: Task 3.
- Full verification and dependency guard: Task 4.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: all tasks use `TCPDialResult`, `TCPDialer`, `TCPTransportAdapter`, `TransportRequest`, `TransportConnection`, and `TransportError` consistently.
