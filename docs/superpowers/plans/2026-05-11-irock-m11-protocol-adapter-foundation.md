# irock M11 Protocol Adapter Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder protocol package with stable proxy adapter foundation types, errors, unsupported behavior, and adapter lookup.

**Architecture:** M11 stays inside `IrockProtocols` and its tests. It migrates the existing placeholder `ProxyRequest`, `ProxyConnection`, `ProtocolAdapterError`, `ProxyAdapter`, and `NoopProxyAdapter` into a foundation layer with `ProxyDestination`, request metadata, a minimal connection protocol, typed protocol errors, `UnsupportedProxyAdapter`, and `ProxyAdapterRegistry`.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, existing `IrockCore` protocol/node/transport domain types, existing `IrockTransport` dependency.

---

## File Structure

M11 modifies these files:

```text
packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift
packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
```

Responsibilities:

- `IrockProtocols.swift`: exports the protocol adapter foundation API.
- `IrockProtocolsTests.swift`: verifies request/connection modeling, error descriptions, unsupported adapter behavior, and registry lookup.

No `Package.swift` dependency changes are expected because `IrockProtocols` already depends on `IrockCore` and `IrockTransport`.

---

### Task 1: Add destination, request, and connection models

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Replace request tests with failing foundation model tests**

Replace `testProxyRequestStoresNodeAndDestination()` in `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` with:

```swift
    func testProxyDestinationEquatableCases() {
        XCTAssertEqual(ProxyDestination.host("apple.com", port: 443), .host("apple.com", port: 443))
        XCTAssertEqual(ProxyDestination.ipv4("93.184.216.34", port: 443), .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(ProxyDestination.ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443), .ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443))
        XCTAssertNotEqual(ProxyDestination.host("apple.com", port: 443), .host("apple.com", port: 80))
    }

    func testProxyRequestStoresNodeDestinationAndMetadata() {
        let node = makeNode(protocolType: .trojan, transport: .tcp)
        let request = ProxyRequest(
            node: node,
            destination: .host("apple.com", port: 443),
            metadata: ["source": "unit-test"]
        )

        XCTAssertEqual(request.node.protocolType, .trojan)
        XCTAssertEqual(request.destination, .host("apple.com", port: 443))
        XCTAssertEqual(request.metadata, ["source": "unit-test"])
    }

    func testProxyRequestDefaultsMetadataToEmpty() {
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp), destination: .ipv4("1.1.1.1", port: 53))

        XCTAssertEqual(request.metadata, [:])
    }

    func testEstablishedProxyConnectionStoresNodeIDAndDestination() {
        let connection = EstablishedProxyConnection(
            nodeID: NodeID(rawValue: "node-1"),
            destination: .host("apple.com", port: 443)
        )

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
    }
```

Add this helper at the bottom of the test class before the closing brace:

```swift
    private func makeNode(protocolType: ProxyProtocolType, transport: TransportType) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo Node",
            protocolType: protocolType,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: transport,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: .disabled
        )
    }
```

- [ ] **Step 2: Run model tests to verify failure**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testProxyDestinationEquatableCases'
```

Expected: FAIL with compiler errors for missing `ProxyDestination` and `EstablishedProxyConnection`, and old `ProxyRequest` initializer mismatch.

- [ ] **Step 3: Implement destination, request, and connection models**

In `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`, replace the existing `ProxyRequest` and `ProxyConnection` definitions with:

```swift
public enum ProxyDestination: Equatable, Sendable {
    case host(String, port: Int)
    case ipv4(String, port: Int)
    case ipv6(String, port: Int)
}

public struct ProxyRequest: Equatable, Sendable {
    public let node: ProxyNode
    public let destination: ProxyDestination
    public let metadata: [String: String]

    public init(node: ProxyNode, destination: ProxyDestination, metadata: [String: String] = [:]) {
        self.node = node
        self.destination = destination
        self.metadata = metadata
    }
}

public protocol ProxyConnection: Sendable {
    var nodeID: NodeID { get }
    var destination: ProxyDestination { get }
}

public struct EstablishedProxyConnection: ProxyConnection, Equatable, Sendable {
    public let nodeID: NodeID
    public let destination: ProxyDestination

    public init(nodeID: NodeID, destination: ProxyDestination) {
        self.nodeID = nodeID
        self.destination = destination
    }
}
```

Do not keep the old `destinationHost` / `destinationPort` request shape.

- [ ] **Step 4: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: FAIL only where old `ProtocolAdapterError` / `NoopProxyAdapter` tests still use old request construction. These are addressed in Task 2.

- [ ] **Step 5: Commit model migration**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "feat: model proxy adapter requests"
```

---

### Task 2: Add protocol errors and unsupported adapter

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Replace Noop adapter test with failing unsupported/error tests**

Replace `testNoopProxyAdapterFailsWithUnsupportedProtocol()` with:

```swift
    func testUnsupportedProxyAdapterFailsWithRequestedProtocol() async {
        let node = makeNode(protocolType: .tuic, transport: .quic)
        let adapter = UnsupportedProxyAdapter(protocolType: .tuic)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.tuic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNoopProxyAdapterRemainsUnsupportedAlias() async {
        let node = makeNode(protocolType: .hysteria2, transport: .quic)
        let adapter = NoopProxyAdapter()
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.hysteria2))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProxyProtocolErrorDescriptionsAreStableAndCredentialSafe() {
        let errors: [(ProxyProtocolError, String)] = [
            (.invalidConfiguration("missing server host"), "Invalid configuration: missing server host"),
            (.dnsFailed("example.com"), "DNS failed: example.com"),
            (.tcpConnectFailed("connection refused"), "TCP connect failed: connection refused"),
            (.tlsHandshakeFailed("certificate rejected"), "TLS handshake failed: certificate rejected"),
            (.authenticationFailed("method rejected"), "Authentication failed: method rejected"),
            (.unsupportedTransport(.quic), "Unsupported transport: quic"),
            (.unsupportedProtocol(.tuic), "Unsupported protocol: tuic"),
            (.protocolHandshakeFailed("bad response"), "Protocol handshake failed: bad response"),
            (.quicHandshakeFailed("timeout"), "QUIC handshake failed: timeout"),
            (.udpUnsupported, "UDP unsupported"),
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
swift test --filter 'IrockProtocolsTests/testUnsupportedProxyAdapterFailsWithRequestedProtocol'
```

Expected: FAIL with missing `UnsupportedProxyAdapter` and `ProxyProtocolError`.

- [ ] **Step 3: Implement `ProxyProtocolError`, `ProxyAdapter`, `UnsupportedProxyAdapter`, and Noop alias**

In `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`, replace `ProtocolAdapterError`, `ProxyAdapter`, and `NoopProxyAdapter` with:

```swift
public enum ProxyProtocolError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case dnsFailed(String)
    case tcpConnectFailed(String)
    case tlsHandshakeFailed(String)
    case authenticationFailed(String)
    case unsupportedTransport(TransportType)
    case unsupportedProtocol(ProxyProtocolType)
    case protocolHandshakeFailed(String)
    case quicHandshakeFailed(String)
    case udpUnsupported
    case remoteClosed
    case timeout

    public var description: String {
        switch self {
        case let .invalidConfiguration(reason):
            return "Invalid configuration: \(reason)"
        case let .dnsFailed(reason):
            return "DNS failed: \(reason)"
        case let .tcpConnectFailed(reason):
            return "TCP connect failed: \(reason)"
        case let .tlsHandshakeFailed(reason):
            return "TLS handshake failed: \(reason)"
        case let .authenticationFailed(reason):
            return "Authentication failed: \(reason)"
        case let .unsupportedTransport(transport):
            return "Unsupported transport: \(transport.rawValue)"
        case let .unsupportedProtocol(protocolType):
            return "Unsupported protocol: \(protocolType.rawValue)"
        case let .protocolHandshakeFailed(reason):
            return "Protocol handshake failed: \(reason)"
        case let .quicHandshakeFailed(reason):
            return "QUIC handshake failed: \(reason)"
        case .udpUnsupported:
            return "UDP unsupported"
        case .remoteClosed:
            return "Remote closed"
        case .timeout:
            return "Timeout"
        }
    }
}

public protocol ProxyAdapter: Sendable {
    var supportedProtocol: ProxyProtocolType { get }
    func connect(request: ProxyRequest) async throws -> any ProxyConnection
}

public struct UnsupportedProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType

    public init(protocolType: ProxyProtocolType) {
        self.supportedProtocol = protocolType
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        throw ProxyProtocolError.unsupportedProtocol(request.node.protocolType)
    }
}

public struct NoopProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType

    public init(protocolType: ProxyProtocolType = .shadowsocks) {
        self.supportedProtocol = protocolType
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        throw ProxyProtocolError.unsupportedProtocol(request.node.protocolType)
    }
}
```

The `any ProxyConnection` existential is required because `ProxyConnection` is now a protocol.

- [ ] **Step 4: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS for model and unsupported/error tests.

- [ ] **Step 5: Commit unsupported adapter and error model**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "feat: add protocol adapter errors"
```

---

### Task 3: Add adapter registry

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Add failing registry tests**

Append these tests inside `IrockProtocolsTests` before `private func makeNode(...)`:

```swift
    func testProxyAdapterRegistryReturnsRegisteredAdapter() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let registry = ProxyAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .trojan)
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        let connection = try await selected.connect(request: request)

        XCTAssertEqual(selected.supportedProtocol, .trojan)
        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
    }

    func testProxyAdapterRegistryFallsBackToUnsupportedAdapter() async {
        let registry = ProxyAdapterRegistry(adapters: [])
        let selected = registry.adapter(for: .vless)
        let request = ProxyRequest(node: makeNode(protocolType: .vless, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await selected.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vless))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProxyAdapterRegistryUsesLastRegisteredAdapterForDuplicates() async throws {
        let first = RecordingProxyAdapter(protocolType: .vmess, connectionNodeID: NodeID(rawValue: "first"))
        let second = RecordingProxyAdapter(protocolType: .vmess, connectionNodeID: NodeID(rawValue: "second"))
        let registry = ProxyAdapterRegistry(adapters: [first, second])
        let selected = registry.adapter(for: .vmess)
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        let connection = try await selected.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "second"))
    }
```

Add this test helper before the test class closing brace:

```swift
private struct RecordingProxyAdapter: ProxyAdapter {
    let supportedProtocol: ProxyProtocolType
    let connectionNodeID: NodeID

    init(protocolType: ProxyProtocolType, connectionNodeID: NodeID = NodeID(rawValue: "node-1")) {
        self.supportedProtocol = protocolType
        self.connectionNodeID = connectionNodeID
    }

    func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        EstablishedProxyConnection(nodeID: connectionNodeID, destination: request.destination)
    }
}
```

- [ ] **Step 2: Run registry test to verify failure**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testProxyAdapterRegistryReturnsRegisteredAdapter'
```

Expected: FAIL with missing `ProxyAdapterRegistry`.

- [ ] **Step 3: Implement `ProxyAdapterRegistry`**

Append this to `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift` after `NoopProxyAdapter`:

```swift
public struct ProxyAdapterRegistry: Sendable {
    private let adapters: [ProxyProtocolType: any ProxyAdapter]

    public init(adapters: [any ProxyAdapter]) {
        var indexed: [ProxyProtocolType: any ProxyAdapter] = [:]
        for adapter in adapters {
            indexed[adapter.supportedProtocol] = adapter
        }
        self.adapters = indexed
    }

    public func adapter(for protocolType: ProxyProtocolType) -> any ProxyAdapter {
        adapters[protocolType] ?? UnsupportedProxyAdapter(protocolType: protocolType)
    }
}
```

- [ ] **Step 4: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS with all protocol tests passing.

- [ ] **Step 5: Commit adapter registry**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "feat: add proxy adapter registry"
```

---

### Task 4: Final verification and dependency guard

**Files:**
- Verify only; no source edits expected unless a verification failure exposes a real bug.

- [ ] **Step 1: Run protocol package tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS with all protocol tests passing.

- [ ] **Step 2: Run full SwiftPM suite**

Run:

```bash
swift test
```

Expected: PASS with all tests passing.

- [ ] **Step 3: Verify no forbidden package imports**

Run:

```bash
grep -R "import IrockTunnelCore\|import IrockStorage\|import IrockAppFeature" -n packages/IrockProtocols Package.swift || true
```

Expected: no output from `packages/IrockProtocols` source or test files. `Package.swift` may mention package targets elsewhere, but `IrockProtocols` target dependencies should remain only `IrockCore` and `IrockTransport`.

- [ ] **Step 4: Inspect git status**

Run:

```bash
git status --short
```

Expected: no uncommitted source changes.

- [ ] **Step 5: Create no empty commit**

If verification changes no files and `git status --short` is empty, create no commit. Report verification evidence.

---

## Self-Review

Spec coverage:

- Destination/request/connection models: Task 1.
- Adapter protocol, unsupported adapter, Noop compatibility alias, and protocol error taxonomy: Task 2.
- Adapter registry, fallback, and duplicate last-wins behavior: Task 3.
- Dependency guard and full verification: Task 4.

Scope check: This plan stays inside `IrockProtocols` source/tests and does not implement real protocol handshakes, encryption, TCP sockets, tunnel bridging, or credential lookup.

Type consistency: Later tasks use `ProxyDestination`, `ProxyRequest`, `ProxyConnection`, `EstablishedProxyConnection`, `ProxyProtocolError`, `ProxyAdapter`, `UnsupportedProxyAdapter`, `NoopProxyAdapter`, and `ProxyAdapterRegistry` exactly as defined in earlier tasks.

Placeholder scan: no unfinished marker phrases remain in this plan.
