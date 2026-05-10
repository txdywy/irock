# irock M15 Shadowsocks Adapter Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Shadowsocks-specific proxy adapter skeleton that validates Alpha node configuration and delegates transport opening through the M14 transport-backed path.

**Architecture:** M15 stays inside `IrockProtocols` and its tests. It introduces `ShadowsocksProxyAdapter`, which owns Shadowsocks-specific structural validation, rejects unsupported protocol/transport combinations before opening transport, and composes `TransportBackedProxyAdapter` for successful TCP transport opening.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, existing `IrockCore`, `IrockTransport`, and `IrockProtocols` contracts.

---

## File Structure

M15 modifies these files:

```text
packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift
packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
```

Responsibilities:

- `IrockProtocols.swift`: exports `ShadowsocksProxyAdapter`.
- `IrockProtocolsTests.swift`: verifies Shadowsocks adapter validation, delegation, and error behavior.

No `Package.swift` dependency changes are expected.

---

### Task 1: Add Shadowsocks adapter happy path

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Add failing happy-path tests**

Add these tests inside `IrockProtocolsTests` before `private func makeNode(...)`:

```swift
    func testShadowsocksProxyAdapterReportsSupportedProtocol() {
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: []))

        XCTAssertEqual(adapter.supportedProtocol, .shadowsocks)
    }

    func testShadowsocksProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "shadowsocks")
    }
```

- [ ] **Step 2: Run happy-path test to verify failure**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testShadowsocksProxyAdapterOpensTCPTransportAndReturnsProxyConnection'
```

Expected: FAIL with missing `ShadowsocksProxyAdapter`.

- [ ] **Step 3: Implement minimal Shadowsocks adapter**

Append this to `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift` after `TransportBackedProxyAdapter`:

```swift
public struct ShadowsocksProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .shadowsocks
    private let transportBackedAdapter: TransportBackedProxyAdapter

    public init(transportRegistry: TransportAdapterRegistry) {
        self.transportBackedAdapter = TransportBackedProxyAdapter(protocolType: .shadowsocks, transportRegistry: transportRegistry)
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        return try await transportBackedAdapter.connect(request: request)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .shadowsocks else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
    }
}
```

- [ ] **Step 4: Run happy-path tests**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testShadowsocksProxyAdapter'
```

Expected: PASS for the two Shadowsocks happy-path tests.

- [ ] **Step 5: Commit happy path**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "feat: add shadowsocks proxy adapter skeleton"
```

---

### Task 2: Add Shadowsocks structural validation

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Add failing validation tests**

Add these tests inside `IrockProtocolsTests` before `private func makeNode(...)`:

```swift
    func testShadowsocksProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsEmptyServerHostBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, serverHost: "   "), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("missing shadowsocks server host"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsInvalidServerPortBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, serverPort: 0), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("invalid shadowsocks server port"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsEmptyCredentialAccountBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, credentialAccount: "   "), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("missing shadowsocks credential account"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsNonTCPTransportBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .grpc)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .grpc), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
```

Update `makeNode` helper signature to:

```swift
    private func makeNode(
        protocolType: ProxyProtocolType,
        transport: TransportType,
        tls: TLSOptions = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
        serverHost: String = "example.com",
        serverPort: Int = 443,
        credentialAccount: String = "node-1"
    ) -> ProxyNode {
```

Inside the helper:

- Change `serverHost: "example.com"` to `serverHost: serverHost`.
- Change `serverPort: 443` to `serverPort: serverPort`.
- Change `CredentialReference(... account: "node-1")` to `CredentialReference(... account: credentialAccount)`.

- [ ] **Step 2: Run validation tests to verify failure**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testShadowsocksProxyAdapterRejectsEmptyServerHostBeforeTransportOpen'
```

Expected: FAIL because validation does not yet check host/port/credential/transport.

- [ ] **Step 3: Implement validation**

Replace `ShadowsocksProxyAdapter.validate(_:)` with:

```swift
    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .shadowsocks else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing shadowsocks server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks server port")
        }
        guard !node.credentialReference.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing shadowsocks credential account")
        }
        guard node.transport == .tcp else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
    }
```

- [ ] **Step 4: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS.

- [ ] **Step 5: Commit validation**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "feat: validate shadowsocks adapter configuration"
```

---

### Task 3: Verify delegated transport errors

**Files:**
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Add delegated transport failure test**

Add this test inside `IrockProtocolsTests` before `private func makeNode(...)`:

```swift
    func testShadowsocksProxyAdapterPropagatesMappedTransportFailure() async {
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [FailingTransportAdapter(transport: .tcp, error: .tcpConnectFailed("password refused"))])
        )
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected mapped transport failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tcpConnectFailed("transport tcp connect failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
```

- [ ] **Step 2: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS because M14 already maps transport failures.

- [ ] **Step 3: Commit delegated error coverage**

```bash
git add packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "test: cover shadowsocks transport failure mapping"
```

---

### Task 4: Final verification

**Files:**
- Verify only; no source edits expected unless verification exposes a bug.

- [ ] **Step 1: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS.

- [ ] **Step 2: Run full SwiftPM suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 3: Verify no forbidden protocol imports**

Run:

```bash
grep -R "import IrockTunnelCore\|import IrockStorage\|import IrockAppFeature" -n packages/IrockProtocols Package.swift || true
```

Expected: no forbidden imports from `packages/IrockProtocols` source or test files.

- [ ] **Step 4: Commit M15 docs**

```bash
git add docs/superpowers/specs/2026-05-11-irock-m15-shadowsocks-adapter-foundation-design.md docs/superpowers/plans/2026-05-11-irock-m15-shadowsocks-adapter-foundation.md
git commit -m "docs: add M15 shadowsocks adapter foundation plan"
```

---

## Self-Review

Spec coverage:

- Shadowsocks adapter identity and happy path: Task 1.
- Structural validation and deterministic failures: Task 2.
- Delegated transport failure mapping: Task 3.
- Full verification and dependency guard: Task 4.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: all tasks use existing M11/M13/M14 types consistently: `ShadowsocksProxyAdapter`, `ProxyRequest`, `ProxyProtocolError`, `TransportAdapterRegistry`, and `TransportError`.
