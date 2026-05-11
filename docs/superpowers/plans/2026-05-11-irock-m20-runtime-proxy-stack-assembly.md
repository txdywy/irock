# irock M20 Runtime Proxy Stack Assembly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic runtime proxy stack assembly boundary that wires Shadowsocks protocol adapters to TCP/TLS transport selection for tunnel runtime use.

**Architecture:** M20 adds a small `RuntimeProxyStack` factory in `IrockTunnelCore` and a `TunnelRuntimeConfiguration` convenience extension. `IrockTunnelCore` receives a direct `IrockTransport` dependency because the assembly layer names transport adapter protocols and `TCPTLSTransportAdapter`; protocol and transport behavior remains implemented in their existing packages.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest async tests, `IrockTunnelCore`, `IrockProtocols`, `IrockTransport`, existing deterministic test doubles.

---

## File Structure

M20 modifies these files:

```text
Package.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift
```

Responsibilities:

- `Package.swift`: adds direct `IrockTransport` dependencies to `IrockTunnelCore` and `IrockTunnelCoreTests` so they can import transport assembly types explicitly.
- `RuntimeProxyStack.swift`: contains the assembly factory and `TunnelRuntimeConfiguration` convenience helpers.
- `RuntimeProxyStackTests.swift`: proves the assembled stack routes TLS-enabled Shadowsocks traffic to the TLS child, TLS-disabled traffic to the plain child, and can be injected into `PacketTunnelRuntime`.

---

### Task 1: Add runtime proxy stack factory

**Files:**
- Modify: `Package.swift`
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`

- [ ] **Step 1: Add failing stack routing tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift` with:

```swift
import XCTest
import IrockCore
import IrockProtocols
import IrockRouting
import IrockStorage
import IrockTransport
@testable import IrockTunnelCore

final class RuntimeProxyStackTests: XCTestCase {
    func testShadowsocksTCPStackRoutesEnabledTLSToTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tlsChild)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let outbound = ProxyOutbound(node: makeNode(tls: tls), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection?.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.host, "example.com")
        XCTAssertEqual(tlsChild.requests.first?.port, 443)
        XCTAssertEqual(tlsChild.requests.first?.transport, .tcp)
        XCTAssertEqual(tlsChild.requests.first?.tls, tls)
        XCTAssertEqual(tlsChild.requests.first?.metadata["packetID"], "tcp-1")
        XCTAssertEqual(tlsChild.requests.first?.metadata["transportProtocol"], "tcp")
        XCTAssertEqual(tlsChild.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(tlsChild.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
    }

    func testShadowsocksTCPStackRoutesDisabledTLSToPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let registry = RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tlsChild)
        let outbound = ProxyOutbound(node: makeNode(tls: .disabled), registry: registry)
        let result = proxyResult(packetID: "tcp-1")

        let connection = try await outbound.connect(result: result)

        XCTAssertEqual(connection?.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection?.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(plain.requests.first?.host, "example.com")
        XCTAssertEqual(plain.requests.first?.port, 443)
        XCTAssertEqual(plain.requests.first?.transport, .tcp)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["packetID"], "tcp-1")
        XCTAssertEqual(plain.requests.first?.metadata["transportProtocol"], "tcp")
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(plain.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
        XCTAssertEqual(tlsChild.requests, [])
    }
}

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

private func proxyResult(packetID: String) -> PacketProcessingResult {
    var processor = PacketProcessor(configuration: TunnelRuntimeConfiguration(snapshot: snapshot(tls: .disabled), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32))
    let packet = Packet.ipv4TCP(id: packetID, source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
    return processor.process(packet)
}

private func snapshot(tls: TLSOptions) -> RuntimeSnapshot {
    RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: makeNode(tls: tls), routeMode: .globalProxy, logLevel: .user)
}

private func makeNode(tls: TLSOptions) -> ProxyNode {
    ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .shadowsocks, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: tls, udpPolicy: .disabled)
}
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter 'RuntimeProxyStackTests/testShadowsocksTCPStackRoutes'
```

Expected: FAIL to compile with errors like `cannot find 'RuntimeProxyStack' in scope` and/or `no such module 'IrockTransport'` from `IrockTunnelCoreTests`.

- [ ] **Step 3: Add Package.swift dependencies**

Change the `IrockTunnelCore` target dependencies from:

```swift
            dependencies: ["IrockCore", "IrockRouting", "IrockStorage", "IrockProtocols"],
```

to:

```swift
            dependencies: ["IrockCore", "IrockRouting", "IrockStorage", "IrockProtocols", "IrockTransport"],
```

Change the `IrockTunnelCoreTests` dependencies from:

```swift
            dependencies: ["IrockTunnelCore", "IrockStorage", "IrockProtocols"],
```

to:

```swift
            dependencies: ["IrockTunnelCore", "IrockStorage", "IrockProtocols", "IrockTransport"],
```

- [ ] **Step 4: Implement minimal RuntimeProxyStack**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift`:

```swift
import IrockProtocols
import IrockTransport

public struct RuntimeProxyStack: Sendable {
    public static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter>(plain: Plain, tls: TLS) -> ProxyAdapterRegistry {
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tls)
        let transportRegistry = TransportAdapterRegistry(adapters: [selector])
        let shadowsocks = ShadowsocksProxyAdapter(transportRegistry: transportRegistry)
        return ProxyAdapterRegistry(adapters: [shadowsocks])
    }
}
```

- [ ] **Step 5: Run stack routing tests**

Run:

```bash
swift test --filter 'RuntimeProxyStackTests/testShadowsocksTCPStackRoutes'
```

Expected: PASS.

- [ ] **Step 6: Commit stack factory**

```bash
git add Package.swift packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift
git commit -m "feat: assemble shadowsocks tcp proxy stack"
```

---

### Task 2: Add TunnelRuntimeConfiguration assembly helpers

**Files:**
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift`
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`

- [ ] **Step 1: Add failing runtime configuration test**

Append this test inside `RuntimeProxyStackTests` before its closing brace:

```swift
    func testShadowsocksTCPConfigurationWiresStackIntoPacketTunnelRuntime() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let reader = InMemoryPacketReader(packets: [Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)])
        let writer = InMemoryPacketWriter()
        let configuration = TunnelRuntimeConfiguration.shadowsocksTCP(
            snapshot: snapshot(tls: .disabled),
            routingEngine: RoutingEngine(rules: [.final(.proxy)]),
            plain: plain,
            tls: tlsChild,
            batchLimit: 16,
            flowLimit: 32
        )
        let runtime = PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration)

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.dropCount, 0)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(tlsChild.requests, [])
        XCTAssertEqual(writer.writtenResults.count, 1)
    }
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
swift test --filter RuntimeProxyStackTests/testShadowsocksTCPConfigurationWiresStackIntoPacketTunnelRuntime
```

Expected: FAIL to compile with `type 'TunnelRuntimeConfiguration' has no member 'shadowsocksTCP'`.

- [ ] **Step 3: Implement configuration helpers**

Append this extension to `RuntimeProxyStack.swift`:

```swift
import IrockCore
import IrockRouting

public extension TunnelRuntimeConfiguration {
    static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tls),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try TunnelRuntimeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tls),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
}
```

If Swift requires imports at file top, keep all imports at the top in this order:

```swift
import IrockCore
import IrockProtocols
import IrockRouting
import IrockTransport
```

- [ ] **Step 4: Run runtime configuration test**

Run:

```bash
swift test --filter RuntimeProxyStackTests/testShadowsocksTCPConfigurationWiresStackIntoPacketTunnelRuntime
```

Expected: PASS.

- [ ] **Step 5: Run all M20 stack tests**

Run:

```bash
swift test --filter RuntimeProxyStackTests
```

Expected: PASS.

- [ ] **Step 6: Commit configuration helpers**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift
git commit -m "feat: add shadowsocks tcp runtime configuration helper"
```

---

### Task 3: Cover assembled stack failure mapping and final verification

**Files:**
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`

- [ ] **Step 1: Add failing TLS child failure test**

Append this test inside `RuntimeProxyStackTests` before its closing brace:

```swift
    func testShadowsocksTCPConfigurationPublishesFailureWhenTLSChildFails() async throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = FailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("secret tls refused"))
        let reader = InMemoryPacketReader(packets: [Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)])
        let writer = InMemoryPacketWriter()
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let configuration = TunnelRuntimeConfiguration.shadowsocksTCP(
            snapshot: snapshot(tls: tls),
            routingEngine: RoutingEngine(rules: [.final(.proxy)]),
            plain: plain,
            tls: tlsChild,
            batchLimit: 16,
            flowLimit: 32
        )
        let runtime = PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected mapped TLS failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tlsHandshakeFailed("transport tls handshake failed"))
            XCTAssertEqual(plain.requests, [])
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Proxy adapter failed: TLS handshake failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Proxy adapter failed: TLS handshake failed"])
            XCTAssertEqual(writer.writtenResults, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
```

Also append this helper after `RecordingTransportAdapter`:

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

- [ ] **Step 2: Run failure test**

Run:

```bash
swift test --filter RuntimeProxyStackTests/testShadowsocksTCPConfigurationPublishesFailureWhenTLSChildFails
```

Expected: PASS, because the production stack already maps transport errors through `TransportBackedProxyAdapter`.

- [ ] **Step 3: Run targeted package tests**

Run:

```bash
swift test --filter IrockTunnelCoreTests
swift test --filter IrockProtocolsTests
swift test --filter IrockTransportTests
```

Expected: PASS.

- [ ] **Step 4: Run full SwiftPM suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 5: Verify no forbidden imports**

Run:

```bash
grep -R "import Network\|import Security" -n packages/IrockTunnelCore packages/IrockProtocols packages/IrockTransport Package.swift || true
```

Expected: no output.

- [ ] **Step 6: Commit failure coverage**

```bash
git add packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift
git commit -m "test: cover runtime proxy stack failure reporting"
```

---

### Task 4: Commit M20 implementation plan

**Files:**
- Modify: `docs/superpowers/plans/2026-05-11-irock-m20-runtime-proxy-stack-assembly.md`

- [ ] **Step 1: Run plan self-review scan**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
path = Path('docs/superpowers/plans/2026-05-11-irock-m20-runtime-proxy-stack-assembly.md')
patterns = ['T' + 'BD', 'TO' + 'DO', 'implement ' + 'later', 'fill in ' + 'details', 'Similar ' + 'to']
for line_number, line in enumerate(path.read_text().splitlines(), start=1):
    if any(pattern in line for pattern in patterns):
        print(f'{line_number}:{line}')
PY
```

Expected: no output.

- [ ] **Step 2: Commit plan**

```bash
git add docs/superpowers/plans/2026-05-11-irock-m20-runtime-proxy-stack-assembly.md
git commit -m "docs: add M20 runtime proxy stack assembly plan"
```

---

## Self-Review

Spec coverage:

- Runtime proxy stack factory: Task 1.
- Direct `IrockTransport` dependency for explicit assembly imports: Task 1.
- Shadowsocks adapter registration: Task 1.
- TCP/TLS selector registration: Task 1.
- Tunnel runtime configuration helper: Task 2.
- TLS-enabled and TLS-disabled routing through assembled stack: Task 1.
- Runtime injection and `proxyConnectCount`: Task 2.
- Failure propagation to status/log: Task 3.
- No real networking and forbidden import guard: Task 3.

Placeholder scan: no placeholder implementation steps remain.

Type consistency: plan uses current `TunnelRuntimeConfiguration` initializers, current `PacketTunnelRuntime` reporter placement, existing `ProxyOutbound`, `RuntimeSnapshot`, `RoutingEngine`, `TransportAdapter`, `TCPTLSTransportAdapter`, and `ShadowsocksProxyAdapter` APIs.
