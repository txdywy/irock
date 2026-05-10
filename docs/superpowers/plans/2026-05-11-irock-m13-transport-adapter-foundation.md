# irock M13 Transport Adapter Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder transport API with stable request, connection, error, unsupported adapter, and registry contracts.

**Architecture:** M13 stays inside `IrockTransport` and its tests. It expands `TransportRequest`, turns `TransportConnection` into a minimal protocol with an established value type, adds typed safe transport errors, preserves `NoopTransportAdapter` as an unsupported alias, and adds an injectable `TransportAdapterRegistry` with unsupported fallback.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, existing `IrockCore` domain types.

---

## File Structure

M13 modifies these files:

```text
packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift
packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
```

Responsibilities:

- `IrockTransport.swift`: exports transport adapter foundation API.
- `IrockTransportTests.swift`: verifies request/connection modeling, safe errors, unsupported adapter behavior, and registry lookup.

No `Package.swift` dependency changes are expected because `IrockTransport` already depends on `IrockCore`.

---

### Task 1: Expand transport request and connection models

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Replace request test with failing request and connection tests**

Replace `testTransportRequestStoresEndpointAndKind()` in `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift` with:

```swift
    func testTransportRequestStoresEndpointTLSAndMetadata() {
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc, tls: tls, metadata: ["source": "unit-test"])

        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 443)
        XCTAssertEqual(request.transport, .grpc)
        XCTAssertEqual(request.tls, tls)
        XCTAssertEqual(request.metadata, ["source": "unit-test"])
    }

    func testTransportRequestDefaultsTLSAndMetadata() {
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp)

        XCTAssertNil(request.tls)
        XCTAssertEqual(request.metadata, [:])
    }

    func testEstablishedTransportConnectionStoresEndpointAndKind() {
        let connection = EstablishedTransportConnection(host: "example.com", port: 443, transport: .tcp)

        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
    }
```

- [ ] **Step 2: Run model test to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests/testTransportRequestStoresEndpointTLSAndMetadata'
```

Expected: FAIL because `TransportRequest` has no `tls` or `metadata` fields and `EstablishedTransportConnection` does not exist.

- [ ] **Step 3: Implement request and connection models**

In `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`, replace the current `TransportRequest` and `TransportConnection` definitions with:

```swift
public struct TransportRequest: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let transport: TransportType
    public let tls: TLSOptions?
    public let metadata: [String: String]

    public init(host: String, port: Int, transport: TransportType, tls: TLSOptions? = nil, metadata: [String: String] = [:]) {
        self.host = host
        self.port = port
        self.transport = transport
        self.tls = tls
        self.metadata = metadata
    }
}

public protocol TransportConnection: Sendable {
    var host: String { get }
    var port: Int { get }
    var transport: TransportType { get }
}

public struct EstablishedTransportConnection: TransportConnection, Equatable, Sendable {
    public let host: String
    public let port: Int
    public let transport: TransportType

    public init(host: String, port: Int, transport: TransportType) {
        self.host = host
        self.port = port
        self.transport = transport
    }
}
```

- [ ] **Step 4: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: FAIL only where `TransportAdapter.open` still returns the old concrete `TransportConnection` placeholder. Task 2 fixes that.

- [ ] **Step 5: Commit model migration**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "feat: model transport adapter requests"
```

---

### Task 2: Add transport errors and unsupported adapter

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Replace Noop test with failing unsupported/error tests**

Replace `testNoopTransportFailsWithUnsupportedTransport()` with:

```swift
    func testUnsupportedTransportAdapterFailsWithRequestedTransport() async {
        let adapter = UnsupportedTransportAdapter(transport: .quic)
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.quic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNoopTransportAdapterRemainsUnsupportedAlias() async {
        let adapter = NoopTransportAdapter()
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportErrorDescriptionsAreStableAndCredentialSafe() {
        let errors: [(TransportError, String)] = [
            (.invalidConfiguration("secret missing server host"), "Invalid configuration"),
            (.dnsFailed("secret.example.com"), "DNS failed"),
            (.tcpConnectFailed("password refused"), "TCP connect failed"),
            (.tlsHandshakeFailed("token rejected"), "TLS handshake failed"),
            (.unsupportedTransport(.quic), "Unsupported transport: quic"),
            (.quicHandshakeFailed("secret timeout"), "QUIC handshake failed"),
            (.remoteClosed, "Remote closed"),
            (.timeout, "Timeout")
        ]

        for (error, description) in errors {
            XCTAssertEqual(error.description, description)
            XCTAssertFalse(error.description.contains("secret"))
            XCTAssertFalse(error.description.contains("password"))
            XCTAssertFalse(error.description.contains("token"))
        }
    }
```

- [ ] **Step 2: Run unsupported adapter test to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests/testUnsupportedTransportAdapterFailsWithRequestedTransport'
```

Expected: FAIL with missing `UnsupportedTransportAdapter` and expanded `TransportError` cases.

- [ ] **Step 3: Implement `TransportError`, `TransportAdapter`, unsupported adapter, and Noop alias**

Replace the current `TransportError`, `TransportAdapter`, and `NoopTransportAdapter` definitions with:

```swift
public enum TransportError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case dnsFailed(String)
    case tcpConnectFailed(String)
    case tlsHandshakeFailed(String)
    case unsupportedTransport(TransportType)
    case quicHandshakeFailed(String)
    case remoteClosed
    case timeout

    public var description: String {
        switch self {
        case .invalidConfiguration:
            return "Invalid configuration"
        case .dnsFailed:
            return "DNS failed"
        case .tcpConnectFailed:
            return "TCP connect failed"
        case .tlsHandshakeFailed:
            return "TLS handshake failed"
        case let .unsupportedTransport(transport):
            return "Unsupported transport: \(transport.rawValue)"
        case .quicHandshakeFailed:
            return "QUIC handshake failed"
        case .remoteClosed:
            return "Remote closed"
        case .timeout:
            return "Timeout"
        }
    }
}

public protocol TransportAdapter: Sendable {
    var supportedTransport: TransportType { get }
    func open(request: TransportRequest) async throws -> any TransportConnection
}

public struct UnsupportedTransportAdapter: TransportAdapter {
    public let supportedTransport: TransportType

    public init(transport: TransportType) {
        self.supportedTransport = transport
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        throw TransportError.unsupportedTransport(request.transport)
    }
}

public struct NoopTransportAdapter: TransportAdapter {
    public let supportedTransport: TransportType

    public init(transport: TransportType = .tcp) {
        self.supportedTransport = transport
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        throw TransportError.unsupportedTransport(request.transport)
    }
}
```

- [ ] **Step 4: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS for model and unsupported/error tests.

- [ ] **Step 5: Commit unsupported adapter and error model**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "feat: add transport adapter errors"
```

---

### Task 3: Add transport adapter registry

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Add failing registry tests**

Append these tests inside `IrockTransportTests` before the final closing brace:

```swift
    func testTransportAdapterRegistryReturnsRegisteredAdapter() async throws {
        let adapter = RecordingTransportAdapter(transport: .grpc)
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .grpc)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .grpc)
        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .grpc)
    }

    func testTransportAdapterRegistryFallsBackToUnsupportedAdapter() async {
        let registry = TransportAdapterRegistry(adapters: [])
        let selected = registry.adapter(for: .quic)
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        do {
            _ = try await selected.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.quic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportAdapterRegistryUsesLastRegisteredAdapterForDuplicates() async throws {
        let first = RecordingTransportAdapter(transport: .tcp, connectionHost: "first.example.com")
        let second = RecordingTransportAdapter(transport: .tcp, connectionHost: "second.example.com")
        let registry = TransportAdapterRegistry(adapters: [first, second])
        let selected = registry.adapter(for: .tcp)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(connection.host, "second.example.com")
    }
```

Add this helper after the test class closing brace:

```swift
private struct RecordingTransportAdapter: TransportAdapter {
    let supportedTransport: TransportType
    let connectionHost: String

    init(transport: TransportType, connectionHost: String = "example.com") {
        self.supportedTransport = transport
        self.connectionHost = connectionHost
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        EstablishedTransportConnection(host: connectionHost, port: request.port, transport: request.transport)
    }
}
```

- [ ] **Step 2: Run registry test to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests/testTransportAdapterRegistryReturnsRegisteredAdapter'
```

Expected: FAIL with missing `TransportAdapterRegistry`.

- [ ] **Step 3: Implement `TransportAdapterRegistry`**

Append this after `NoopTransportAdapter` in `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`:

```swift
public struct TransportAdapterRegistry: Sendable {
    private let adapters: [TransportType: any TransportAdapter]

    public init(adapters: [any TransportAdapter]) {
        var indexed: [TransportType: any TransportAdapter] = [:]
        for adapter in adapters {
            indexed[adapter.supportedTransport] = adapter
        }
        self.adapters = indexed
    }

    public func adapter(for transport: TransportType) -> any TransportAdapter {
        adapters[transport] ?? UnsupportedTransportAdapter(transport: transport)
    }
}
```

- [ ] **Step 4: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS with all transport tests passing.

- [ ] **Step 5: Commit transport registry**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "feat: add transport adapter registry"
```

---

### Task 4: Final verification and dependency guard

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
grep -R "import IrockTunnelCore\|import IrockStorage\|import IrockAppFeature" -n packages/IrockTransport Package.swift || true
```

Expected: no output from `packages/IrockTransport` source or test files. `Package.swift` should not add tunnel, storage, or app feature dependencies to the `IrockTransport` target.

- [ ] **Step 5: Commit M13 docs**

```bash
git add docs/superpowers/specs/2026-05-11-irock-m13-transport-adapter-foundation-design.md docs/superpowers/plans/2026-05-11-irock-m13-transport-adapter-foundation.md
git commit -m "docs: add M13 transport adapter foundation plan"
```

---

## Self-Review

Spec coverage:

- Expanded request and connection models: Task 1.
- Error taxonomy, unsupported adapter, Noop compatibility alias: Task 2.
- Adapter registry, fallback, duplicate last-wins behavior: Task 3.
- Dependency guard and full verification: Task 4.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: all tasks use `TransportRequest`, `TransportConnection`, `EstablishedTransportConnection`, `TransportError`, `TransportAdapter`, `UnsupportedTransportAdapter`, `NoopTransportAdapter`, and `TransportAdapterRegistry` consistently.
