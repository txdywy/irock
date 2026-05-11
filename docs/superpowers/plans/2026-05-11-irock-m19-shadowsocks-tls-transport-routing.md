# irock M19 Shadowsocks TLS Transport Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove Shadowsocks protocol adapters compose with the TCP/TLS transport selector for TLS-enabled and TLS-disabled nodes.

**Architecture:** M19 stays in `IrockProtocolsTests`; no production source changes are expected. Tests wire `ShadowsocksProxyAdapter` to a `TransportAdapterRegistry` containing `TCPTLSTransportAdapter`, then assert selector child routing and existing transport-to-protocol error mapping.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, existing `IrockCore`, `IrockTransport`, and `IrockProtocols` contracts.

---

## File Structure

M19 modifies this file:

```text
packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
```

Responsibilities:

- `IrockProtocolsTests.swift`: adds integration-style protocol tests using existing recording/failing transport adapters and M18 `TCPTLSTransportAdapter`.

No production source or `Package.swift` dependency changes are expected.

---

### Task 1: Cover Shadowsocks TLS selector routing

**Files:**
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Add TLS-enabled and TLS-disabled routing tests**

Add these tests inside `IrockProtocolsTests` before `makeNode(...)`:

```swift
    func testShadowsocksProxyAdapterRoutesEnabledTLSThroughSelectorTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [selector]))
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp, tls: tls)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.host, "example.com")
        XCTAssertEqual(tlsChild.requests.first?.port, 443)
        XCTAssertEqual(tlsChild.requests.first?.transport, .tcp)
        XCTAssertEqual(tlsChild.requests.first?.tls, tls)
        XCTAssertEqual(tlsChild.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(tlsChild.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(tlsChild.requests.first?.metadata["destination"], "host:apple.com:443")
    }

    func testShadowsocksProxyAdapterRoutesDisabledTLSThroughSelectorPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [selector]))
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp, tls: .disabled)
        let request = ProxyRequest(node: node, destination: .ipv4("93.184.216.34", port: 443))

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(plain.requests.first?.host, "example.com")
        XCTAssertEqual(plain.requests.first?.port, 443)
        XCTAssertEqual(plain.requests.first?.transport, .tcp)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(plain.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
        XCTAssertEqual(tlsChild.requests, [])
    }
```

- [ ] **Step 2: Run routing tests**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testShadowsocksProxyAdapterRoutes'
```

Expected: PASS. These tests should pass because M14/M15/M18 already provide the required behavior.

- [ ] **Step 3: Commit routing coverage**

```bash
git add packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "test: cover shadowsocks tls transport routing"
```

---

### Task 2: Cover Shadowsocks selector error mapping

**Files:**
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Add TLS and plain child failure mapping tests**

Add these tests inside `IrockProtocolsTests` before `makeNode(...)`:

```swift
    func testShadowsocksProxyAdapterMapsSelectorTLSChildFailure() async {
        let selector = TCPTLSTransportAdapter(
            plain: RecordingTransportAdapter(transport: .tcp),
            tls: FailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("tls refused"))
        )
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [selector]))
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, tls: tls), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected mapped TLS failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tlsHandshakeFailed("transport tls handshake failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterMapsSelectorPlainChildFailure() async {
        let selector = TCPTLSTransportAdapter(
            plain: FailingTransportAdapter(transport: .tcp, error: .tcpConnectFailed("plain refused")),
            tls: RecordingTransportAdapter(transport: .tcp)
        )
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [selector]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, tls: .disabled), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected mapped plain failure")
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

Expected: PASS.

- [ ] **Step 3: Commit error mapping coverage**

```bash
git add packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "test: cover shadowsocks selector failure mapping"
```

---

### Task 3: Final verification

**Files:**
- Verify only; no source edits expected unless verification exposes a bug.

- [ ] **Step 1: Run protocol tests**

Run:

```bash
swift test --filter IrockProtocolsTests
```

Expected: PASS.

- [ ] **Step 2: Run transport and tunnel tests**

Run:

```bash
swift test --filter IrockTransportTests
swift test --filter IrockTunnelCoreTests
```

Expected: PASS.

- [ ] **Step 3: Run full SwiftPM suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Verify no forbidden network/security imports**

Run:

```bash
grep -R "import Network\|import Security" -n packages/IrockProtocols packages/IrockTransport Package.swift || true
```

Expected: no forbidden imports from protocol or transport package source or test files.

- [ ] **Step 5: Commit M19 plan**

```bash
git add docs/superpowers/plans/2026-05-11-irock-m19-shadowsocks-tls-transport-routing.md
git commit -m "docs: add M19 shadowsocks tls routing plan"
```

---

## Self-Review

Spec coverage:

- TLS-enabled Shadowsocks selector routing: Task 1.
- TLS-disabled Shadowsocks selector routing: Task 1.
- TLS child failure mapping: Task 2.
- Plain child failure mapping: Task 2.
- Full verification and import guard: Task 3.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: all tasks use `ShadowsocksProxyAdapter`, `TCPTLSTransportAdapter`, `TransportAdapterRegistry`, `RecordingTransportAdapter`, `FailingTransportAdapter`, `ProxyRequest`, `ProxyProtocolError`, and `TLSOptions` consistently.
