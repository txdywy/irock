# M37 VLESS TCP/TLS Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first VLESS protocol adapter foundation so VLESS nodes validate configuration and open TCP or TCP/TLS transport through existing proxy/transport seams.

**Architecture:** Implement VLESS as a dedicated `ProxyAdapter` in `IrockProtocols`, following the credential-safe M36 VMess pattern while keeping M37 scoped to validation, synthetic opener metadata, and TCP/TLS transport selection. Add `RuntimeProxyStack.vlessTCP` and `TunnelRuntimeConfiguration.vlessTCP` helpers so `IrockTunnelCore` can register VLESS without changing packet processing.

**Tech Stack:** Swift 5.10, SwiftPM XCTest, IrockCore, IrockProtocols, IrockTransport, IrockTunnelCore.

---

## Files

- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Add `VLESSOpenRequest` and `VLESSProxyAdapter`.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Add VLESS opener, validation, TCP, TLS, and credential-safety tests.
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeProxyStack.swift`
  - Add VLESS TCP/TLS registry and configuration helpers.
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift`
  - Add VLESS stack tests.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m37-vless-tcp-tls-foundation-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m37-vless-tcp-tls-foundation.md`

## Task 1: VLESS opener descriptor

- [ ] **Step 1: Write failing opener tests**

Add tests to `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` after the VMess opener tests:

```swift
func testVLESSOpenRequestBuildsCredentialSafeMetadataAndPayload() throws {
    let request = try VLESSOpenRequest(
        userID: "00000000-0000-0000-0000-000000000002",
        destination: .host("apple.com", port: 443)
    )

    XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
    XCTAssertEqual(request.security, "none")
    XCTAssertEqual(request.flow, "")
    XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "vless-foundation:host:apple.com:443:none:")
    XCTAssertEqual(request.metadata["vlessUserIDPresent"], "true")
    XCTAssertNil(request.metadata["vlessUserID"])
    XCTAssertEqual(request.metadata["vlessDestination"], "host:apple.com:443")
    XCTAssertEqual(request.metadata["vlessSecurity"], "none")
    XCTAssertEqual(request.metadata["vlessFlow"], "")
    XCTAssertFalse(request.openBytes.contains(Data("00000000-0000-0000-0000-000000000002".utf8)))
}

func testVLESSOpenRequestRejectsInvalidUserID() {
    XCTAssertThrowsError(try VLESSOpenRequest(userID: "not-a-uuid", destination: .host("apple.com", port: 443))) { error in
        XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid vless user id"))
    }
}
```

- [ ] **Step 2: Run opener tests to verify RED**

Run: `swift test --filter IrockProtocolsTests/testVLESSOpenRequest`

Expected: FAIL because `VLESSOpenRequest` does not exist.

- [ ] **Step 3: Implement `VLESSOpenRequest`**

Add `VLESSOpenRequest` after `VMessOpenRequest` in `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`. It should validate UUID shape, normalize security to lowercase, use an empty default flow, expose only `vlessUserIDPresent`, and build `openBytes` as `vless-foundation:<destination>:<security>:<flow>`.

- [ ] **Step 4: Run opener tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testVLESSOpenRequest`

Expected: PASS.

## Task 2: VLESS proxy adapter

- [ ] **Step 1: Write failing adapter tests**

Add tests after the VMess adapter tests in `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`:

```swift
func testVLESSProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
    let transport = RecordingTransportAdapter(transport: .tcp)
    let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
    let node = makeNode(protocolType: .vless, transport: .tcp, credentialAccount: "00000000-0000-0000-0000-000000000002")
    let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

    let connection = try await adapter.connect(request: request)

    XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
    XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests.first?.host, "example.com")
    XCTAssertEqual(transport.requests.first?.port, 443)
    XCTAssertEqual(transport.requests.first?.transport, .tcp)
    XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
    XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "vless")
    XCTAssertEqual(transport.requests.first?.metadata["vlessUserIDPresent"], "true")
    XCTAssertNil(transport.requests.first?.metadata["vlessUserID"])
    XCTAssertEqual(transport.requests.first?.metadata["vlessDestination"], "host:apple.com:443")
    XCTAssertEqual(String(data: transport.requests.first?.initialPayload ?? Data(), encoding: .utf8), "vless-foundation:host:apple.com:443:none:")
    XCTAssertFalse((transport.requests.first?.initialPayload ?? Data()).contains(Data("00000000-0000-0000-0000-000000000002".utf8)))
}

func testVLESSProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
    let transport = RecordingTransportAdapter(transport: .tcp)
    let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
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

func testVLESSProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
    let cases: [(ProxyNode, ProxyProtocolError)] = [
        (makeNode(protocolType: .vless, transport: .tcp, serverHost: "   ", credentialAccount: "00000000-0000-0000-0000-000000000002"), .invalidConfiguration("missing vless server host")),
        (makeNode(protocolType: .vless, transport: .tcp, serverPort: 0, credentialAccount: "00000000-0000-0000-0000-000000000002"), .invalidConfiguration("invalid vless server port")),
        (makeNode(protocolType: .vless, transport: .tcp, credentialAccount: "not-a-uuid"), .invalidConfiguration("invalid vless user id")),
        (makeNode(protocolType: .vless, transport: .grpc, credentialAccount: "00000000-0000-0000-0000-000000000002"), .unsupportedTransport(.grpc))
    ]

    for (node, expectedError) in cases {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        do {
            _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
            XCTFail("Expected VLESS validation failure")
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

Run: `swift test --filter IrockProtocolsTests/testVLESSProxyAdapter`

Expected: FAIL because `VLESSProxyAdapter` does not exist.

- [ ] **Step 3: Implement `VLESSProxyAdapter`**

Add `VLESSProxyAdapter` after `VMessProxyAdapter` in `IrockProtocols.swift`. Mirror VMess validation and transport error mapping, replacing protocol-specific strings and using `VLESSOpenRequest`.

- [ ] **Step 4: Run adapter tests to verify GREEN**

Run: `swift test --filter IrockProtocolsTests/testVLESSProxyAdapter`

Expected: PASS.

## Task 3: VLESS runtime stack integration

- [ ] **Step 1: Write failing runtime stack tests**

Add VLESS stack tests to `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeProxyStackTests.swift` after the VMess stack tests. They should mirror VMess disabled/enabled TLS tests, use `RuntimeProxyStack.vlessTCP`, `makeVLESSNode`, assert `proxyProtocol == "vless"`, `vlessUserIDPresent == "true"`, and `vlessUserID == nil`.

- [ ] **Step 2: Run runtime stack tests to verify RED**

Run: `swift test --filter RuntimeProxyStackTests/testVLESSTCPStack`

Expected: FAIL because `RuntimeProxyStack.vlessTCP` does not exist.

- [ ] **Step 3: Implement VLESS stack helpers**

Update `RuntimeProxyStack.swift` with `RuntimeProxyStack.vlessTCP(plain:tls:)` and `TunnelRuntimeConfiguration.vlessTCP(...)` overloads mirroring VMess.

- [ ] **Step 4: Run runtime stack tests to verify GREEN**

Run: `swift test --filter RuntimeProxyStackTests/testVLESSTCPStack`

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

Run credential grep and platform import scan; expected no VLESS UUID exposure in metadata/payload examples and `Platform imports remain out of shared packages`.

- [ ] **Step 5: Review, deslop, and commit**

Request independent review against M37 acceptance criteria. If approved, run bounded deslop on changed M37 files, rerun verification, update Ralph state, commit, and push.

## Self-review

- Spec coverage: Tasks cover VLESS validation, credential-safe opener descriptor, TCP/TLS transport integration, runtime stack registration, and verification.
- Placeholder scan: No TBD/TODO/fill-in placeholders remain; out-of-scope items are explicitly deferred.
- Type consistency: Planned symbols are `VLESSOpenRequest`, `VLESSProxyAdapter`, `RuntimeProxyStack.vlessTCP`, and `TunnelRuntimeConfiguration.vlessTCP`.
