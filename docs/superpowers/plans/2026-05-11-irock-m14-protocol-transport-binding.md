# irock M14 Protocol Transport Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a protocol-layer adapter skeleton that opens a node transport through `TransportAdapterRegistry` before returning a proxy connection.

**Architecture:** M14 stays inside `IrockProtocols` and its tests. It adds `TransportBackedProxyAdapter`, which validates protocol type, builds a `TransportRequest` from `ProxyRequest.node`, opens the selected transport adapter, maps transport errors into `ProxyProtocolError`, and returns `EstablishedProxyConnection` without exposing streams or doing real protocol handshakes.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, existing `IrockCore`, `IrockTransport`, and `IrockProtocols` contracts.

---

## File Structure

M14 modifies these files:

```text
packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift
packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
```

Responsibilities:

- `IrockProtocols.swift`: exports `TransportBackedProxyAdapter` and transport-to-protocol error mapping.
- `IrockProtocolsTests.swift`: verifies transport request construction, invocation, protocol mismatch, unsupported transport fallback, and error mapping.

No `Package.swift` dependency changes are expected because `IrockProtocols` already depends on `IrockTransport`.

---

### Task 1: Add transport-backed adapter happy path

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Add failing happy-path test**

Add this test inside `IrockProtocolsTests` before `private func makeNode(...)`:

```swift
    func testTransportBackedProxyAdapterOpensNodeTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .grpc)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .trojan, transport: .grpc)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .grpc)
        XCTAssertEqual(transport.requests.first?.tls?.enabled, true)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "trojan")
        XCTAssertEqual(transport.requests.first?.metadata["destination"], "host:apple.com:443")
    }
```

Add this helper after the test class closing brace:

```swift
private final class RecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    private let lock = NSLock()
    private var storedRequests: [TransportRequest] = []

    var requests: [TransportRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    init(transport: TransportType) {
        self.supportedTransport = transport
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        record(request)
        return EstablishedTransportConnection(host: request.host, port: request.port, transport: request.transport)
    }

    private func record(_ request: TransportRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(request)
    }
}
```

- [ ] **Step 2: Run happy-path test to verify failure**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testTransportBackedProxyAdapterOpensNodeTransportAndReturnsProxyConnection'
```

Expected: FAIL with missing `TransportBackedProxyAdapter`.

- [ ] **Step 3: Implement happy-path adapter**

Append this to `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift` after `ProxyAdapterRegistry`:

```swift
public struct TransportBackedProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType
    private let transportRegistry: TransportAdapterRegistry

    public init(protocolType: ProxyProtocolType, transportRegistry: TransportAdapterRegistry) {
        self.supportedProtocol = protocolType
        self.transportRegistry = transportRegistry
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        guard request.node.protocolType == supportedProtocol else {
            throw ProxyProtocolError.unsupportedProtocol(request.node.protocolType)
        }

        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request)
        )
        _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func transportMetadata(for request: ProxyRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        metadata["destination"] = destinationDescription(request.destination)
        return metadata
    }

    private func destinationDescription(_ destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port):
            return "host:\(host):\(port)"
        case let .ipv4(address, port):
            return "ipv4:\(address):\(port)"
        case let .ipv6(address, port):
            return "ipv6:\(address):\(port)"
        }
    }
}
```

- [ ] **Step 4: Run happy-path test**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testTransportBackedProxyAdapterOpensNodeTransportAndReturnsProxyConnection'
```

Expected: PASS.

- [ ] **Step 5: Commit happy-path adapter**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "feat: open transports from protocol adapters"
```

---

### Task 2: Add protocol mismatch and TLS disabled behavior

**Files:**
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Add protocol mismatch test**

Add this test inside `IrockProtocolsTests` before `private func makeNode(...)`:

```swift
    func testTransportBackedProxyAdapterRejectsProtocolMismatchBeforeOpeningTransport() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vmess))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
```

- [ ] **Step 2: Add TLS disabled test**

Add this test inside `IrockProtocolsTests` before `private func makeNode(...)`:

```swift
    func testTransportBackedProxyAdapterOmitsDisabledTLS() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp, tls: .disabled), destination: .ipv4("93.184.216.34", port: 443))

        _ = try await adapter.connect(request: request)

        XCTAssertNil(transport.requests.first?.tls)
        XCTAssertEqual(transport.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
    }
```

Update the existing `makeNode` helper signature to:

```swift
    private func makeNode(protocolType: ProxyProtocolType, transport: TransportType, tls: TLSOptions = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)) -> ProxyNode {
```

Inside the helper, replace the hard-coded `tls:` argument with `tls: tls`.

- [ ] **Step 3: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS.

- [ ] **Step 4: Commit mismatch/TLS behavior**

```bash
git add packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "test: cover protocol transport binding edges"
```

---

### Task 3: Map transport errors into protocol errors

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Add failing error mapping tests**

Add this test inside `IrockProtocolsTests` before `private func makeNode(...)`:

```swift
    func testTransportBackedProxyAdapterMapsTransportErrorsToProtocolErrors() async {
        let cases: [(TransportError, ProxyProtocolError)] = [
            (.invalidConfiguration("secret invalid"), .invalidConfiguration("transport invalid")),
            (.dnsFailed("secret host"), .dnsFailed("transport dns failed")),
            (.tcpConnectFailed("password refused"), .tcpConnectFailed("transport tcp connect failed")),
            (.tlsHandshakeFailed("token rejected"), .tlsHandshakeFailed("transport tls handshake failed")),
            (.unsupportedTransport(.quic), .unsupportedTransport(.quic)),
            (.quicHandshakeFailed("secret timeout"), .quicHandshakeFailed("transport quic handshake failed")),
            (.remoteClosed, .remoteClosed),
            (.timeout, .timeout)
        ]

        for (transportError, expectedProtocolError) in cases {
            let adapter = TransportBackedProxyAdapter(
                protocolType: .trojan,
                transportRegistry: TransportAdapterRegistry(adapters: [FailingTransportAdapter(transport: .tcp, error: transportError)])
            )
            let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

            do {
                _ = try await adapter.connect(request: request)
                XCTFail("Expected protocol error")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedProtocolError)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
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

- [ ] **Step 2: Run error mapping test to verify failure**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testTransportBackedProxyAdapterMapsTransportErrorsToProtocolErrors'
```

Expected: FAIL because raw `TransportError` is thrown instead of mapped `ProxyProtocolError`.

- [ ] **Step 3: Implement transport error mapping**

In `TransportBackedProxyAdapter.connect(request:)`, replace:

```swift
        _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
```

with:

```swift
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
```

Add this helper inside `TransportBackedProxyAdapter`:

```swift
    private func proxyProtocolError(for error: TransportError) -> ProxyProtocolError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration("transport invalid")
        case .dnsFailed:
            return .dnsFailed("transport dns failed")
        case .tcpConnectFailed:
            return .tcpConnectFailed("transport tcp connect failed")
        case .tlsHandshakeFailed:
            return .tlsHandshakeFailed("transport tls handshake failed")
        case let .unsupportedTransport(transport):
            return .unsupportedTransport(transport)
        case .quicHandshakeFailed:
            return .quicHandshakeFailed("transport quic handshake failed")
        case .remoteClosed:
            return .remoteClosed
        case .timeout:
            return .timeout
        }
    }
```

- [ ] **Step 4: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS.

- [ ] **Step 5: Commit error mapping**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "feat: map transport failures to protocol errors"
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

- [ ] **Step 2: Run transport tests**

Run:

```bash
swift test --filter IrockTransportTests
```

Expected: PASS.

- [ ] **Step 3: Run full SwiftPM suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Verify no forbidden protocol imports**

Run:

```bash
grep -R "import IrockTunnelCore\|import IrockStorage\|import IrockAppFeature" -n packages/IrockProtocols Package.swift || true
```

Expected: no forbidden imports from `packages/IrockProtocols` source or test files.

- [ ] **Step 5: Commit M14 docs**

```bash
git add docs/superpowers/specs/2026-05-11-irock-m14-protocol-transport-binding-design.md docs/superpowers/plans/2026-05-11-irock-m14-protocol-transport-binding.md
git commit -m "docs: add M14 protocol transport binding plan"
```

---

## Self-Review

Spec coverage:

- Transport-backed proxy adapter happy path: Task 1.
- Protocol mismatch and disabled TLS behavior: Task 2.
- Transport-to-protocol error mapping: Task 3.
- Full verification and dependency guard: Task 4.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: all tasks use existing M11/M13 types consistently: `ProxyRequest`, `ProxyConnection`, `EstablishedProxyConnection`, `ProxyProtocolError`, `TransportRequest`, `TransportConnection`, `TransportAdapterRegistry`, and `TransportError`.
