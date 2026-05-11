# M38 Trojan TCP/TLS Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add the first Trojan protocol adapter foundation so Trojan nodes validate configuration and open TCP or TCP/TLS transport through existing proxy/transport seams.

**Architecture:** Implement Trojan as a dedicated `ProxyAdapter` in `IrockProtocols`, following the credential-safe M36/M37 foundation pattern while keeping M38 scoped to validation, synthetic opener metadata, and TCP/TLS transport selection. Add `RuntimeProxyStack.trojanTCP` and `TunnelRuntimeConfiguration.trojanTCP` helpers so `IrockTunnelCore` can register Trojan without changing packet processing.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockProtocols, IrockTransport, IrockTunnelCore.

---

## Files

- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Add `TrojanOpenRequest` and `TrojanProxyAdapter`.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Add Trojan opener, validation, TCP, TLS, and credential-safety tests.
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift`
  - Add Trojan TCP/TLS registry and configuration helpers.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`
  - Add Trojan stack tests.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m38-trojan-tcp-tls-foundation-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m38-trojan-tcp-tls-foundation.md`

## Task 1: Trojan opener descriptor

- [ ] **Step 1: Write failing opener tests**

Add tests to `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` after the VLESS opener tests:

```swift
func testTrojanOpenRequestBuildsCredentialSafeMetadataAndPayload() throws {
    let request = try TrojanOpenRequest(
        password: "secret-password",
        destination: .host("apple.com", port: 443),
        serverName: "trojan.example.com"
    )

    XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
    XCTAssertEqual(request.serverName, "trojan.example.com")
    XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "trojan-foundation:host:apple.com:443:trojan.example.com")
    XCTAssertEqual(request.metadata["trojanPasswordPresent"], "true")
    XCTAssertNil(request.metadata["trojanPassword"])
    XCTAssertEqual(request.metadata["trojanDestination"], "host:apple.com:443")
    XCTAssertEqual(request.metadata["trojanServerName"], "trojan.example.com")
    XCTAssertFalse(request.openBytes.contains(Data("secret-password".utf8)))
}

func testTrojanOpenRequestRejectsEmptyPassword() {
    XCTAssertThrowsError(try TrojanOpenRequest(password: "   ", destination: .host("apple.com", port: 443))) { error in
        XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("missing trojan password"))
    }
}
```

- [ ] **Step 2: Run opener tests to verify RED**

Run: `swift test --filter IrockProtocolsTests/testTrojanOpenRequest`

Expected: FAIL because `TrojanOpenRequest` does not exist.

- [ ] **Step 3: Implement `TrojanOpenRequest`**

Add `TrojanOpenRequest` after `VLESSOpenRequest` in `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`. It should validate non-empty password, normalize optional server name by trimming whitespace, expose only `trojanPasswordPresent`, and build `openBytes` as `trojan-foundation:<destination>:<serverName>`.

- [ ] **Step 4: Run opener tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testTrojanOpenRequest`

Expected: PASS.

## Task 2: Trojan proxy adapter

- [ ] **Step 1: Write failing adapter tests**

Add tests after the VLESS adapter tests in `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`:

```swift
func testTrojanProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
    let transport = RecordingTransportAdapter(transport: .tcp)
    let adapter = TrojanProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
    let tls = TLSOptions(enabled: true, serverName: "trojan.example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
    let node = makeNode(protocolType: .trojan, transport: .tcp, tls: tls, credentialAccount: "secret-password")
    let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

    let connection = try await adapter.connect(request: request)

    XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
    XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests.first?.host, "example.com")
    XCTAssertEqual(transport.requests.first?.port, 443)
    XCTAssertEqual(transport.requests.first?.transport, .tcp)
    XCTAssertEqual(transport.requests.first?.tls, tls)
    XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
    XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "trojan")
    XCTAssertEqual(transport.requests.first?.metadata["trojanPasswordPresent"], "true")
    XCTAssertNil(transport.requests.first?.metadata["trojanPassword"])
    XCTAssertEqual(transport.requests.first?.metadata["trojanDestination"], "host:apple.com:443")
    XCTAssertEqual(transport.requests.first?.metadata["trojanServerName"], "trojan.example.com")
    XCTAssertEqual(String(data: transport.requests.first?.initialPayload ?? Data(), encoding: .utf8), "trojan-foundation:host:apple.com:443:trojan.example.com")
    XCTAssertFalse((transport.requests.first?.initialPayload ?? Data()).contains(Data("secret-password".utf8)))
}

func testTrojanProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
    let transport = RecordingTransportAdapter(transport: .tcp)
    let adapter = TrojanProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
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

func testTrojanProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
    let cases: [(ProxyNode, ProxyProtocolError)] = [
        (makeNode(protocolType: .trojan, transport: .tcp, serverHost: "   ", credentialAccount: "secret-password"), .invalidConfiguration("missing trojan server host")),
        (makeNode(protocolType: .trojan, transport: .tcp, serverPort: 0, credentialAccount: "secret-password"), .invalidConfiguration("invalid trojan server port")),
        (makeNode(protocolType: .trojan, transport: .tcp, credentialAccount: "   "), .invalidConfiguration("missing trojan password")),
        (makeNode(protocolType: .trojan, transport: .grpc, credentialAccount: "secret-password"), .unsupportedTransport(.grpc))
    ]

    for (node, expectedError) in cases {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TrojanProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        do {
            _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
            XCTFail("Expected Trojan validation failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, expectedError)
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run adapter tests to verify RED**

Run: `swift test --filter IrockProtocolsTests/testTrojanProxyAdapter`

Expected: FAIL because `TrojanProxyAdapter` does not exist.

- [ ] **Step 3: Implement `TrojanProxyAdapter`**

Add `TrojanProxyAdapter` after `VLESSProxyAdapter` in `IrockProtocols.swift`. Mirror VLESS validation and transport error mapping, replacing protocol-specific strings and using `TrojanOpenRequest`.

- [ ] **Step 4: Run adapter tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testTrojanProxyAdapter`

Expected: PASS.

## Task 3: Trojan runtime stack integration

- [ ] **Step 1: Write failing runtime stack tests**

Add Trojan stack tests to `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift` after the VLESS stack tests. They should mirror VLESS disabled/enabled TLS tests, use `RuntimeProxyStack.trojanTCP`, `makeTrojanNode`, assert `proxyProtocol == "trojan"`, `trojanPasswordPresent == "true"`, and `trojanPassword == nil`.

- [ ] **Step 2: Run runtime stack tests to verify RED**

Run: `swift test --filter RuntimeProxyStackTests/testTrojanTCPStack`

Expected: FAIL because `RuntimeProxyStack.trojanTCP` does not exist.

- [ ] **Step 3: Implement Trojan stack helpers**

Update `RuntimeProxyStack.swift` with `RuntimeProxyStack.trojanTCP(plain:tls:)` and `TunnelRuntimeConfiguration.trojanTCP(...)` overloads mirroring VLESS.

- [ ] **Step 4: Run runtime stack tests to verify GREEN**

Run: `swift test --filter RuntimeProxyStackTests/testTrojanTCPStack`

Expected: PASS.

## Task 4: Full verification

- [ ] **Step 1: Run protocol tests**

Run: `swift test --filter IrockProtocolsTests`

Expected: PASS.

- [ ] **Step 2: Run tunnel core tests**

Run: `swift test --filter IrockTunnelCoreTests`

Expected: PASS.

- [ ] **Step 3: Run full SwiftPM tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 4: Run credential exposure and platform scans**

Run credential grep and platform import scan; expected no Trojan password exposure in source metadata/payload examples and `Platform imports remain out of shared packages`.

- [ ] **Step 5: Review, deslop, and commit**

Request independent review against M38 acceptance criteria. If approved, run bounded deslop on changed M38 files, rerun verification, update Ralph state, commit, and push.

## Self-review

- Spec coverage: Tasks cover Trojan validation, credential-safe opener descriptor, TCP/TLS transport integration, runtime stack registration, and verification.
- Placeholder scan: No TBD/TODO/fill-in placeholders remain; out-of-scope items are explicitly deferred.
- Type consistency: Planned symbols are `TrojanOpenRequest`, `TrojanProxyAdapter`, `RuntimeProxyStack.trojanTCP`, and `TunnelRuntimeConfiguration.trojanTCP`.
