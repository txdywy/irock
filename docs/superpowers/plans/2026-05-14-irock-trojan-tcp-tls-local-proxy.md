# Trojan TCP+TLS Local Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Trojan over TCP+TLS usable through the macOS local SOCKS/HTTP CONNECT proxy using native repository-owned protocol framing and transport code.

**Architecture:** Reuse the existing `TrojanOpenRequest` in `IrockProtocols` for the real Trojan request prefix, then add a small macOS TLS byte-stream wrapper around `Network.NWConnection`. `MacOSLocalProxyController` will route Trojan destinations to that stream, send the Trojan opener as the first TLS payload, and reuse the existing bidirectional relay shape already used by Hysteria2 streams.

**Tech Stack:** Swift 5.10, SwiftPM/XCTest for shared packages, macOS app target, Foundation, Darwin sockets, Network.framework, existing `IrockCore`, `IrockProtocols`, and `IrockAppFeature` packages. No full proxy cores and no third-party protocol libraries.

---

## File structure

- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`
  - Allow `.trojan` with `.tcp` to start local proxy instead of marking it unsupported.
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`
  - Add a regression proving Trojan TCP starts the local proxy controller.
- Create: `apps/irock-macOS/irockMacApp/MacOSTLSByteStream.swift`
  - Provide a small `TransportByteStream` implementation backed by `NWConnection` over TLS.
- Modify: `apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift`
  - Permit Trojan TCP in `start(node:credential:realmCredential:)`.
  - Route `.trojan` in `openOutboundAndRelay`.
  - Build and send `TrojanOpenRequest` as the initial TLS payload.
  - Relay local socket bytes to/from the TLS byte stream without Trojan-specific per-chunk framing.
- Modify: `apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj`
  - Add `MacOSTLSByteStream.swift` to the app target sources.
- Modify: `apps/irock-macOS/irockMacApp/IrockMacApp.swift`
  - Add an environment-gated packaged app self-test path for real Trojan nodes if the app already has a self-test dispatcher.
- Modify if present in the script: `apps/irock-macOS/build-unsigned-app.sh`
  - Include the new source file in any source-list or self-test checks.

---

### Task 1: Prove app feature allows Trojan TCP local proxy startup

**Files:**
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`

- [ ] **Step 1: Write the failing app feature test**

Add this test near the existing local proxy start tests in `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`:

```swift
func testAppViewModelStartsTrojanTCPLocalProxy() throws {
    let controller = RecordingLocalProxyController()
    let model = AppViewModel(localProxyController: controller)
    let node = try model.importURI("trojan://secret-password@trojan.example.com:443?sni=trojan.example.com&alpn=h2#Trojan")
    model.selectNode(id: node.id)

    let result = model.startLocalProxy()

    XCTAssertEqual(node.protocolType, .trojan)
    XCTAssertEqual(node.transport, .tcp)
    XCTAssertEqual(controller.startedNode, node)
    XCTAssertEqual(controller.startedCredential, "secret-password")
    XCTAssertEqual(model.localProxyState.phase, .running)
    guard case let .localProxyStarted(endpoint) = result else {
        return XCTFail("Expected Trojan local proxy startup, got \(result)")
    }
    XCTAssertEqual(endpoint.socksPort, 10808)
}
```

If `RecordingLocalProxyController` uses different property names, use the names already used by the HY2/Shadowsocks local proxy tests in the same file. Do not introduce a second mock controller.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter IrockAppFeatureTests/testAppViewModelStartsTrojanTCPLocalProxy
```

Expected: FAIL because `AppViewModel.startLocalProxy()` marks non-Shadowsocks/non-HY2 protocols unsupported.

- [ ] **Step 3: Allow Trojan TCP in `AppViewModel.startLocalProxy()`**

In `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`, update the protocol gate in `startLocalProxy()` to include Trojan TCP.

Replace the existing switch shape that has `.shadowsocks`, `.hysteria2`, and `default` with this logic:

```swift
switch node.protocolType {
case .shadowsocks:
    guard node.transport == .tcp else {
        localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "当前 Shadowsocks 节点需要 TCP 传输")
        return .localProxyFailed(localProxyState.message)
    }
    guard ShadowsocksStreamRequest.supportsCredential(credential) else {
        localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "当前 Shadowsocks 加密方法暂不支持本地代理")
        return .localProxyFailed(localProxyState.message)
    }
case .hysteria2:
    guard node.transport == .quic else {
        localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "当前 Hysteria2 节点需要 QUIC 传输")
        return .localProxyFailed(localProxyState.message)
    }
case .trojan:
    guard node.transport == .tcp else {
        localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "当前 Trojan 节点需要 TCP/TLS 传输")
        return .localProxyFailed(localProxyState.message)
    }
default:
    if localProxyState.phase != .running {
        localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "当前协议暂不支持本地代理")
    }
    return .localProxyFailed(localProxyState.message)
}
```

Keep the existing credential lookup, realm credential lookup, `localProxyController.start(...)`, and success state code unchanged.

- [ ] **Step 4: Verify the app feature test passes**

Run:

```bash
swift test --filter IrockAppFeatureTests/testAppViewModelStartsTrojanTCPLocalProxy
```

Expected: PASS.

- [ ] **Step 5: Run the app feature test target**

Run:

```bash
swift test --filter IrockAppFeatureTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 1**

```bash
git add packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
git commit -m "Allow Trojan TCP local proxy startup"
```

---

### Task 2: Add a native macOS TLS byte stream

**Files:**
- Create: `apps/irock-macOS/irockMacApp/MacOSTLSByteStream.swift`
- Modify: `apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the TLS byte stream file**

Create `apps/irock-macOS/irockMacApp/MacOSTLSByteStream.swift` with this content:

```swift
import Foundation
import IrockCore
import IrockTransport
import Network
import Security

final class MacOSTLSByteStream: TransportByteStream, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "dev.irock.macos-tls-byte-stream")

    init(host: String, port: Int, tls: TLSOptions, initialPayload: Data?) throws {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: try NWEndpoint.Port(validatingTCPPort: port))
        let options = NWProtocolTLS.Options()
        if let serverName = tls.serverName?.trimmingCharacters(in: .whitespacesAndNewlines), !serverName.isEmpty {
            serverName.withCString { sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, $0) }
        }
        for alpn in tls.alpn.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            alpn.withCString { sec_protocol_options_add_tls_application_protocol(options.securityProtocolOptions, $0) }
        }
        if tls.allowInsecure {
            sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, complete in
                complete(true)
            }, queue)
        }
        if tls.fingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            throw TransportError.invalidConfiguration("tls certificate pinning is unsupported in macOS local proxy")
        }
        if tls.reality != nil {
            throw TransportError.invalidConfiguration("reality tls is unsupported in Trojan local proxy")
        }
        let parameters = NWParameters(tls: options)
        self.connection = NWConnection(to: endpoint, using: parameters)
        self.initialPayload = initialPayload
    }

    private let initialPayload: Data?

    func start() async throws {
        final class ResumeGate: @unchecked Sendable {
            private let lock = NSLock()
            private var didResume = false

            func runOnce(_ body: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                body()
            }
        }

        let resumeGate = ResumeGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeGate.runOnce {
                        if let initialPayload, !initialPayload.isEmpty {
                            self.connection.send(content: initialPayload, completion: .contentProcessed { error in
                                if let error {
                                    continuation.resume(throwing: TransportError.tcpConnectFailed(error.localizedDescription))
                                } else {
                                    continuation.resume()
                                }
                            })
                        } else {
                            continuation.resume()
                        }
                    }
                case let .failed(error):
                    resumeGate.runOnce {
                        continuation.resume(throwing: TransportError.tlsHandshakeFailed(error.localizedDescription))
                    }
                case .cancelled:
                    resumeGate.runOnce {
                        continuation.resume(throwing: TransportError.remoteClosed)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func read(maxLength: Int) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: TransportError.tcpConnectFailed(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: TransportError.tcpConnectFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func closeWrite() async {
        connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in })
    }

    func close() async {
        connection.cancel()
    }
}

private extension NWEndpoint.Port {
    init(validatingTCPPort port: Int) throws {
        guard (1...65_535).contains(port), let value = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw TransportError.invalidConfiguration("invalid tcp port")
        }
        self = value
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

Modify `apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj` by following the existing `MacOSPlatformQUICStreamDialer.swift` entries:

1. Add a `PBXBuildFile` entry named `IROCKAPPTLSBUILD0001 /* MacOSTLSByteStream.swift in Sources */`.
2. Add a `PBXFileReference` entry named `IROCKAPPTLSFILEREF01 /* MacOSTLSByteStream.swift */`.
3. Add the file reference to the `irockMacApp` group next to `MacOSPlatformQUICStreamDialer.swift`.
4. Add the build file to the app target `Sources` build phase.

Use the same formatting style as neighboring entries; do not regenerate the project.

- [ ] **Step 3: Build the macOS app target**

Run:

```bash
./apps/irock-macOS/build-unsigned-app.sh
```

Expected: build succeeds, or the script reaches the same signing/self-test boundary it currently uses for unsigned builds. If the script has a dedicated no-run/build-only flag, use the flag documented in the script.

- [ ] **Step 4: Commit Task 2**

```bash
git add apps/irock-macOS/irockMacApp/MacOSTLSByteStream.swift apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj
git commit -m "Add macOS TLS byte stream"
```

---

### Task 3: Route Trojan through the macOS local proxy

**Files:**
- Modify: `apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift`

- [ ] **Step 1: Extend the local proxy protocol gate**

In `MacOSLocalProxyController.start(node:credential:realmCredential:)`, replace the guard with:

```swift
guard (node.protocolType == .shadowsocks && node.transport == .tcp)
    || (node.protocolType == .hysteria2 && node.transport == .quic)
    || (node.protocolType == .trojan && node.transport == .tcp) else {
    throw LocalProxyError.unavailable
}
```

- [ ] **Step 2: Route Trojan in `openOutboundAndRelay`**

In `openOutboundAndRelay(...)`, add a Trojan case between Shadowsocks and Hysteria2:

```swift
case .trojan:
    try openTrojanOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, sendSuccess: sendSuccess)
```

- [ ] **Step 3: Add the Trojan outbound method**

Add this method near `openShadowsocksOutboundAndRelay(...)`:

```swift
private func openTrojanOutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, sendSuccess: () throws -> Void) throws {
    let request = try TrojanOpenRequest(
        password: credential,
        destination: destination,
        serverName: node.tls.serverName ?? node.serverHost
    )
    let tls = TLSOptions(
        enabled: .enabled,
        serverName: node.tls.serverName ?? node.serverHost,
        alpn: node.tls.alpn,
        allowInsecure: node.tls.allowInsecure,
        fingerprint: node.tls.fingerprint,
        reality: node.tls.reality
    )
    let stream = try MacOSTLSByteStream(
        host: node.serverHost,
        port: node.serverPort,
        tls: tls,
        initialPayload: request.openBytes
    )
    try runAsync { try await stream.start() }
    try sendSuccess()
    relay(local: client, stream: stream)
}
```

Do not add per-chunk Trojan framing in the relay. Trojan sends only the initial request header and then forwards raw TCP bytes inside TLS.

- [ ] **Step 4: Generalize stream relay parameter type if needed**

If `relay(local:stream:)`, `relayLocalToStream`, or `relayStreamToLocal` currently accept only `NativeHysteria2ByteStream`, change their parameter type to `any TransportByteStream` and add `IrockTransport` import if it is not already available.

Use this final shape:

```swift
private func relay(local: Int32, stream: any TransportByteStream) {
    let group = DispatchGroup()
    group.enter()
    connectionQueue.async {
        self.relayLocalToStream(local: local, stream: stream)
        group.leave()
    }
    group.enter()
    connectionQueue.async {
        self.relayStreamToLocal(stream: stream, local: local)
        group.leave()
    }
    group.wait()
}

private func relayLocalToStream(local: Int32, stream: any TransportByteStream) {
    do {
        while let payload = try readAvailable(from: local, maxLength: 16_384) {
            try runAsync { try await stream.write(payload) }
        }
        try runAsync { try await stream.closeWrite() }
    } catch {}
}

private func relayStreamToLocal(stream: any TransportByteStream, local: Int32) {
    do {
        while let payload = try runAsync({ try await stream.read(maxLength: 16_384) }) {
            try writeAll(payload, to: local)
        }
    } catch {}
    shutdown(local, SHUT_WR)
}
```

- [ ] **Step 5: Update the HTTP unsupported response text**

Replace the hard-coded Shadowsocks-only text in `sendUnsupportedHTTPResponse` with:

```swift
let response = "HTTP/1.1 501 Not Implemented\r\nContent-Length: 75\r\nConnection: close\r\n\r\nHTTP proxy only supports CONNECT tunneling for supported local proxy protocols."
```

- [ ] **Step 6: Build the macOS app**

Run:

```bash
./apps/irock-macOS/build-unsigned-app.sh
```

Expected: build succeeds, or reaches the expected unsigned app self-test stage with no compile errors.

- [ ] **Step 7: Commit Task 3**

```bash
git add apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift
git commit -m "Route Trojan through macOS local proxy"
```

---

### Task 4: Add optional real Trojan local proxy validation

**Files:**
- Modify: `apps/irock-macOS/irockMacApp/IrockMacApp.swift`
- Modify: `apps/irock-macOS/build-unsigned-app.sh`

- [ ] **Step 1: Locate existing packaged self-test hooks**

Run:

```bash
grep -R "IROCK_.*TEST\|SELF_TEST\|self-test\|example.com\|curl" -n apps/irock-macOS
```

Expected: find the existing HY2/local proxy packaged validation path added in recent commits.

- [ ] **Step 2: Add Trojan environment variable names to the self-test path**

Use these variable names consistently:

```text
IROCK_TROJAN_TEST_HOST
IROCK_TROJAN_TEST_PORT
IROCK_TROJAN_TEST_PASSWORD
IROCK_TROJAN_TEST_SNI
IROCK_TROJAN_TEST_ALLOW_INSECURE
```

If the app has a self-test dispatcher in `IrockMacApp.swift`, add a Trojan branch that constructs a `ProxyNode` equivalent to this shape:

```swift
let node = ProxyNode(
    id: NodeID(rawValue: "trojan-self-test"),
    name: "Trojan Self Test",
    protocolType: .trojan,
    serverHost: host,
    serverPort: port,
    credentialReference: CredentialReference(keychainService: "self-test", account: "trojan-self-test"),
    transport: .tcp,
    transportOptions: TransportOptions(),
    tls: TLSOptions(
        enabled: .enabled,
        serverName: sni.isEmpty ? host : sni,
        alpn: [],
        allowInsecure: allowInsecure,
        fingerprint: nil,
        reality: nil
    ),
    udpPolicy: .disabled
)
```

Pass the password directly to `MacOSLocalProxyController.start(node:credential:realmCredential:)` inside the self-test only. Do not store it in fixtures, logs, or runtime snapshots.

- [ ] **Step 3: Make the script skip cleanly without credentials**

In `apps/irock-macOS/build-unsigned-app.sh`, add a check equivalent to:

```bash
if [[ -z "${IROCK_TROJAN_TEST_HOST:-}" || -z "${IROCK_TROJAN_TEST_PORT:-}" || -z "${IROCK_TROJAN_TEST_PASSWORD:-}" ]]; then
  echo "Skipping Trojan real-node self-test; set IROCK_TROJAN_TEST_HOST, IROCK_TROJAN_TEST_PORT, and IROCK_TROJAN_TEST_PASSWORD to enable it."
else
  echo "Running Trojan real-node self-test..."
  # Use the existing app self-test invocation style from the script.
fi
```

Do not invent a second app-launch mechanism if the script already has one.

- [ ] **Step 4: Run script without credentials**

Run:

```bash
./apps/irock-macOS/build-unsigned-app.sh
```

Expected: build succeeds and Trojan self-test is skipped with a clear message.

- [ ] **Step 5: Commit Task 4**

```bash
git add apps/irock-macOS/irockMacApp/IrockMacApp.swift apps/irock-macOS/build-unsigned-app.sh
git commit -m "Add Trojan local proxy self-test hook"
```

---

### Task 5: Full verification, performance sanity, and publication

**Files:**
- No source edits unless verification reveals a defect.

- [ ] **Step 1: Run targeted SwiftPM tests**

Run:

```bash
swift test --filter IrockAppFeatureTests
swift test --filter IrockProtocolsTests
```

Expected: both pass.

- [ ] **Step 2: Run full SwiftPM tests**

Run:

```bash
swift test
```

Expected: all tests pass. If default `.build` is locked by a stale process, diagnose the process first; use a separate `--scratch-path` only to unblock verification after confirming the lock source.

- [ ] **Step 3: Build packaged macOS app**

Run:

```bash
./apps/irock-macOS/build-unsigned-app.sh
```

Expected: unsigned app builds and existing self-tests pass or skip cleanly when credentials are absent.

- [ ] **Step 4: Optional real-node Trojan validation**

Only run when credentials are supplied by the operator in the shell environment:

```bash
IROCK_TROJAN_TEST_HOST="<host>" \
IROCK_TROJAN_TEST_PORT="443" \
IROCK_TROJAN_TEST_PASSWORD="<password>" \
IROCK_TROJAN_TEST_SNI="<sni>" \
./apps/irock-macOS/build-unsigned-app.sh
```

Expected: packaged app starts local proxy, an HTTP CONNECT or SOCKS request through Trojan reaches the validation destination, and the script prints a credential-safe success line.

- [ ] **Step 5: Check for secrets and plaintext protocol-library imports**

Run:

```bash
grep -R "sing-box\|xray\|clash\|IROCK_TROJAN_TEST_PASSWORD\|secret-password" -n . --exclude-dir=.git --exclude-dir=.build
```

Expected: no proxy core dependency references; `secret-password` may appear only in tests/docs as a dummy fixture, not in runtime logs or source defaults.

- [ ] **Step 6: Review git diff**

Run:

```bash
git status --short
git diff --stat
```

Expected: only intended files changed and all changes are committed before publishing.

- [ ] **Step 7: Push and merge after verification**

Use the normal autonomous project workflow after tests pass:

```bash
git push origin HEAD
```

If working on a feature branch, create/update a PR, merge to `main` after verification, push `main`, delete only the merged local feature branch, and preserve unrelated worktree-agent branches.
