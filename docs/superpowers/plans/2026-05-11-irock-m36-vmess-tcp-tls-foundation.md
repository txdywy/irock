# M36 VMess TCP/TLS Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add the first VMess protocol adapter foundation so VMess nodes validate configuration and open TCP or TCP/TLS transport through existing proxy/transport seams.

**Architecture:** Implement VMess as a dedicated `ProxyAdapter` in `IrockProtocols`, mirroring the Shadowsocks adapter boundary while keeping M36 scoped to validation, deterministic opener metadata, and TCP/TLS transport selection. Add `RuntimeProxyStack.vmessTCP` and `TunnelRuntimeConfiguration.vmessTCP` helpers so `IrockTunnelCore` can register VMess without changing packet processing.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockProtocols, IrockTransport, IrockTunnelCore.

---

## Files

- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Add `VMessOpenRequest` and `VMessProxyAdapter`.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Add VMess opener, validation, TCP, TLS, and transport-failure tests.
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift`
  - Add VMess TCP/TLS registry and configuration helpers.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`
  - Add VMess stack tests.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m36-vmess-tcp-tls-foundation-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m36-vmess-tcp-tls-foundation.md`

## Task 1: VMess opener descriptor

- [x] **Step 1: Write failing opener tests**

Add these tests to `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` after the Shadowsocks stream request tests:

```swift
func testVMessOpenRequestBuildsStableMetadataAndPayload() throws {
    let request = try VMessOpenRequest(
        userID: "00000000-0000-0000-0000-000000000001",
        destination: .host("apple.com", port: 443)
    )

    XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
    XCTAssertEqual(request.security, "auto")
    XCTAssertEqual(request.alterID, 0)
    XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "vmess-foundation:host:apple.com:443:auto:0")
    XCTAssertEqual(request.metadata["vmessUserIDPresent"], "true")
    XCTAssertNil(request.metadata["vmessUserID"])
    XCTAssertEqual(request.metadata["vmessDestination"], "host:apple.com:443")
    XCTAssertEqual(request.metadata["vmessSecurity"], "auto")
    XCTAssertEqual(request.metadata["vmessAlterID"], "0")
}

func testVMessOpenRequestRejectsInvalidUserID() {
    XCTAssertThrowsError(try VMessOpenRequest(userID: "not-a-uuid", destination: .host("apple.com", port: 443))) { error in
        XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid vmess user id"))
    }
}
```

- [x] **Step 2: Run opener tests to verify RED**

Run: `swift test --filter IrockProtocolsTests/testVMessOpenRequest`

Expected: FAIL because `VMessOpenRequest` does not exist.

- [x] **Step 3: Implement `VMessOpenRequest`**

Add this type to `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift` after `ShadowsocksStreamRequest`:

```swift
public struct VMessOpenRequest: Equatable, Sendable {
    public let destinationDescription: String
    public let security: String
    public let alterID: Int
    public let openBytes: Data

    public var metadata: [String: String] {
        [
            "vmessUserIDPresent": "true",
            "vmessDestination": destinationDescription,
            "vmessSecurity": security,
            "vmessAlterID": String(alterID)
        ]
    }

    public init(userID: String, destination: ProxyDestination, security: String = "auto", alterID: Int = 0) throws {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard UUID(uuidString: normalizedUserID) != nil else {
            throw ProxyProtocolError.invalidConfiguration("invalid vmess user id")
        }
        guard alterID >= 0 else {
            throw ProxyProtocolError.invalidConfiguration("invalid vmess alter id")
        }
        let normalizedSecurity = security.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSecurity.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("invalid vmess security")
        }

        self.destinationDescription = Self.destinationDescription(destination)
        self.security = normalizedSecurity
        self.alterID = alterID
        self.openBytes = Data("vmess-foundation:\(Self.destinationDescription(destination)):\(normalizedSecurity):\(alterID)".utf8)
    }

    private static func destinationDescription(_ destination: ProxyDestination) -> String {
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

- [x] **Step 4: Run opener tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testVMessOpenRequest`

Expected: PASS.

## Task 2: VMess proxy adapter

- [x] **Step 1: Write failing adapter tests**

Add these tests to `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` after `testTransportBackedProxyAdapterRejectsProtocolMismatchBeforeOpeningTransport`:

```swift
func testVMessProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
    let transport = RecordingTransportAdapter(transport: .tcp)
    let adapter = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
    let node = makeNode(protocolType: .vmess, transport: .tcp, credentialAccount: "00000000-0000-0000-0000-000000000001")
    let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

    let connection = try await adapter.connect(request: request)

    XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
    XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests.first?.host, "example.com")
    XCTAssertEqual(transport.requests.first?.port, 443)
    XCTAssertEqual(transport.requests.first?.transport, .tcp)
    XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
    XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "vmess")
    XCTAssertEqual(transport.requests.first?.metadata["vmessUserIDPresent"], "true")
    XCTAssertNil(transport.requests.first?.metadata["vmessUserID"])
    XCTAssertEqual(transport.requests.first?.metadata["vmessDestination"], "host:apple.com:443")
    XCTAssertEqual(String(data: transport.requests.first?.initialPayload ?? Data(), encoding: .utf8), "vmess-foundation:host:apple.com:443:auto:0")
}

func testVMessProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
    let transport = RecordingTransportAdapter(transport: .tcp)
    let adapter = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
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

func testVMessProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
    let cases: [(ProxyNode, ProxyProtocolError)] = [
        (makeNode(protocolType: .vmess, transport: .tcp, serverHost: "   ", credentialAccount: "00000000-0000-0000-0000-000000000001"), .invalidConfiguration("missing vmess server host")),
        (makeNode(protocolType: .vmess, transport: .tcp, serverPort: 0, credentialAccount: "00000000-0000-0000-0000-000000000001"), .invalidConfiguration("invalid vmess server port")),
        (makeNode(protocolType: .vmess, transport: .tcp, credentialAccount: "not-a-uuid"), .invalidConfiguration("invalid vmess user id")),
        (makeNode(protocolType: .vmess, transport: .grpc, credentialAccount: "00000000-0000-0000-0000-000000000001"), .unsupportedTransport(.grpc))
    ]

    for (node, expectedError) in cases {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        do {
            _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
            XCTFail("Expected VMess validation failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, expectedError)
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

- [x] **Step 2: Run adapter tests to verify RED**

Run: `swift test --filter IrockProtocolsTests/testVMessProxyAdapter`

Expected: FAIL because `VMessProxyAdapter` does not exist.

- [x] **Step 3: Implement `VMessProxyAdapter`**

Add this type to `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift` after `TransportBackedProxyAdapter`:

```swift
public struct VMessProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .vmess
    private let transportRegistry: TransportAdapterRegistry

    public init(transportRegistry: TransportAdapterRegistry) {
        self.transportRegistry = transportRegistry
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let openRequest = try VMessOpenRequest(userID: request.node.credentialReference.account, destination: request.destination)
        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request, openRequest: openRequest),
            initialPayload: openRequest.openBytes
        )
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .vmess else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing vmess server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid vmess server port")
        }
        guard node.transport == .tcp else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
        _ = try VMessOpenRequest(userID: node.credentialReference.account, destination: .host("validation.local", port: 1))
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: VMessOpenRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }

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
}
```

- [x] **Step 4: Run adapter tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testVMessProxyAdapter`

Expected: PASS.

## Task 3: VMess runtime stack integration

- [x] **Step 1: Write failing runtime stack tests**

Add these tests to `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`:

```swift
func testVMessTCPStackRoutesDisabledTLSToPlainChild() async throws {
    let plain = StackRecordingTransportAdapter(transport: .tcp)
    let tlsChild = StackRecordingTransportAdapter(transport: .tcp)
    let registry = RuntimeProxyStack.vmessTCP(plain: plain, tls: tlsChild)
    let adapter = registry.adapter(for: .vmess)
    let node = stackNode(protocolType: .vmess, tls: .disabled, credentialAccount: "00000000-0000-0000-0000-000000000001")

    _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))

    XCTAssertEqual(plain.requests.count, 1)
    XCTAssertNil(plain.requests.first?.tls)
    XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "vmess")
    XCTAssertEqual(tlsChild.requests, [])
}

func testVMessTCPStackRoutesEnabledTLSToTLSChild() async throws {
    let plain = StackRecordingTransportAdapter(transport: .tcp)
    let tlsChild = StackRecordingTransportAdapter(transport: .tcp)
    let registry = RuntimeProxyStack.vmessTCP(plain: plain, tls: tlsChild)
    let adapter = registry.adapter(for: .vmess)
    let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
    let node = stackNode(protocolType: .vmess, tls: tls, credentialAccount: "00000000-0000-0000-0000-000000000001")

    _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))

    XCTAssertEqual(plain.requests, [])
    XCTAssertEqual(tlsChild.requests.count, 1)
    XCTAssertEqual(tlsChild.requests.first?.tls, tls)
    XCTAssertEqual(tlsChild.requests.first?.metadata["proxyProtocol"], "vmess")
}
```

If `RuntimeProxyStackTests.swift` does not already have `StackRecordingTransportAdapter` or `stackNode`, add test-local helpers matching the existing Shadowsocks stack helpers.

- [x] **Step 2: Run runtime stack tests to verify RED**

Run: `swift test --filter RuntimeProxyStackTests/testVMessTCPStack`

Expected: FAIL because `RuntimeProxyStack.vmessTCP` does not exist.

- [x] **Step 3: Implement VMess stack helpers**

Update `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift`:

```swift
public static func vmessTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
    plain: Plain,
    tls: TLS
) -> ProxyAdapterRegistry {
    let selector = TCPTLSTransportAdapter(plain: plain, tls: tls)
    let transportRegistry = TransportAdapterRegistry(adapters: [selector])
    let vmess = VMessProxyAdapter(transportRegistry: transportRegistry)
    return ProxyAdapterRegistry(adapters: [vmess])
}
```

Add matching `TunnelRuntimeConfiguration.vmessTCP` overloads mirroring `shadowsocksTCP` but without credential resolver.

- [x] **Step 4: Run runtime stack tests to verify GREEN**

Run: `swift test --filter RuntimeProxyStackTests/testVMessTCPStack`

Expected: PASS.

## Task 4: Full verification

- [x] **Step 1: Run protocol tests**

Run: `swift test --filter IrockProtocolsTests`

Expected: PASS.

- [x] **Step 2: Run tunnel core tests**

Run: `swift test --filter IrockTunnelCoreTests`

Expected: PASS.

- [x] **Step 3: Run full SwiftPM tests**

Run: `swift test`

Expected: PASS.

- [x] **Step 4: Run platform import boundary scan**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
package_forbidden = {'Network', 'NetworkExtension', 'UIKit', 'AppKit', 'Security'}
violations = []
for path in Path('packages').rglob('*.swift'):
    for line_no, line in enumerate(path.read_text().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith('import '):
            module = stripped.split()[1]
            if module in package_forbidden:
                violations.append(f'{path}:{line_no}: {stripped}')
if violations:
    print('\n'.join(violations))
    raise SystemExit(1)
print('Platform imports remain out of shared packages')
PY
```

Expected: `Platform imports remain out of shared packages`.

- [x] **Step 5: Review, deslop, and commit**

Request independent review against M36 acceptance criteria. If approved, run bounded deslop on changed M36 files, rerun verification, update Ralph state, commit, and push.

## Self-review

- Spec coverage: Tasks cover VMess validation, opener descriptor, TCP/TLS transport integration, runtime stack registration, and verification.
- Placeholder scan: No TBD/TODO/fill-in placeholders remain. The only future work is explicitly out of scope.
- Type consistency: Planned symbols are `VMessOpenRequest`, `VMessProxyAdapter`, `RuntimeProxyStack.vmessTCP`, and `TunnelRuntimeConfiguration.vmessTCP`.
