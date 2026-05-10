# irock M5 Shadowsocks URI Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parse common `ss://` Shadowsocks URIs into `NodeDraft` values without adding protocol runtime, Keychain, network, or platform behavior.

**Architecture:** M5 extends the existing `URIImport` entry point with `parseShadowsocksDraft(_:)` while preserving `classify(_:)`. The parser produces editable `NodeDraft` values only; `NodeDraft.buildNode(...)` remains responsible for constructing `ProxyNode` with credential references.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, Foundation `URLComponents`, `Data(base64Encoded:)`, existing `IrockCore` and `IrockAppFeature` models.

---

## File Structure

M5 creates and modifies these files:

```text
packages/IrockAppFeature/Sources/IrockAppFeature/URIImport.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift
README.md
CLAUDE.md
docs/superpowers/plans/2026-05-10-irock-m5-shadowsocks-uri-import.md
```

Responsibilities:

- `URIImport.swift`: classify URI schemes and parse Shadowsocks URIs into `NodeDraft`.
- `URIImportTests.swift`: lock supported SS URI forms and import errors.
- `README.md` and `CLAUDE.md`: update project status to include M5.

---

### Task 1: Parse Shadowsocks URI into NodeDraft

**Files:**
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift`
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/URIImport.swift`

- [ ] **Step 1: Replace URI import tests with Shadowsocks parser coverage**

Replace `packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift` with:

```swift
import XCTest
import IrockCore
@testable import IrockAppFeature

final class URIImportTests: XCTestCase {
    func testClassifiesSupportedSchemes() throws {
        XCTAssertEqual(try URIImport.classify("ss://abc").protocolType, .shadowsocks)
        XCTAssertEqual(try URIImport.classify("vmess://abc").protocolType, .vmess)
        XCTAssertEqual(try URIImport.classify("vless://abc").protocolType, .vless)
        XCTAssertEqual(try URIImport.classify("trojan://abc").protocolType, .trojan)
        XCTAssertEqual(try URIImport.classify("hysteria2://abc").protocolType, .hysteria2)
        XCTAssertEqual(try URIImport.classify("tuic://abc").protocolType, .tuic)
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try URIImport.classify("https://example.com")) { error in
            XCTAssertEqual(error as? URIImportError, .unsupportedScheme("https"))
        }
    }

    func testParsesFullyBase64EncodedShadowsocksURI() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzc0BleGFtcGxlLmNvbTo4Mzg4#Demo%20SS")

        XCTAssertEqual(draft.name, "Demo SS")
        XCTAssertEqual(draft.protocolType, .shadowsocks)
        XCTAssertEqual(draft.serverHost, "example.com")
        XCTAssertEqual(draft.serverPortText, "8388")
        XCTAssertEqual(draft.credentialAccount, "aes-256-gcm:pass")
        XCTAssertEqual(draft.transport, .tcp)
        XCTAssertFalse(draft.tlsEnabled)
        XCTAssertEqual(draft.tlsServerName, "")
        XCTAssertFalse(draft.udpEnabled)
    }

    func testParsesUserInfoBase64ShadowsocksURI() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo%20SS")

        XCTAssertEqual(draft.name, "Demo SS")
        XCTAssertEqual(draft.serverHost, "example.com")
        XCTAssertEqual(draft.serverPortText, "8388")
        XCTAssertEqual(draft.credentialAccount, "aes-256-gcm:pass")
    }

    func testUsesHostPortAsNameWhenFragmentIsMissing() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388")

        XCTAssertEqual(draft.name, "example.com:8388")
    }

    func testParsesURLSafeBase64WithoutPadding() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwQHNz@example.com:443#URLSafe")

        XCTAssertEqual(draft.name, "URLSafe")
        XCTAssertEqual(draft.credentialAccount, "chacha20-ietf-poly1305:p@ss")
        XCTAssertEqual(draft.serverHost, "example.com")
        XCTAssertEqual(draft.serverPortText, "443")
    }

    func testParseShadowsocksRejectsNonSSScheme() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("trojan://example.com")) { error in
            XCTAssertEqual(error as? URIImportError, .unsupportedScheme("trojan"))
        }
    }

    func testParseShadowsocksRejectsInvalidBase64() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("ss://not base64@example.com:8388")) { error in
            XCTAssertEqual(error as? URIImportError, .invalidBase64)
        }
    }

    func testParseShadowsocksRejectsMissingUserInfo() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("ss://example.com:8388")) { error in
            XCTAssertEqual(error as? URIImportError, .missingUserInfo)
        }
    }

    func testParseShadowsocksRejectsMissingHost() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@:8388")) { error in
            XCTAssertEqual(error as? URIImportError, .missingHost)
        }
    }

    func testParseShadowsocksRejectsMissingPort() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@example.com")) { error in
            XCTAssertEqual(error as? URIImportError, .missingPort)
        }
    }

    func testImportedDraftBuildsShadowsocksNode() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-1"), keychainService: "com.irock.nodes")

        XCTAssertEqual(node.protocolType, .shadowsocks)
        XCTAssertEqual(node.name, "Demo")
        XCTAssertEqual(node.serverHost, "example.com")
        XCTAssertEqual(node.serverPort, 8388)
        XCTAssertEqual(node.credentialReference.account, "aes-256-gcm:pass")
    }
}
```

- [ ] **Step 2: Run URI import tests to verify failure**

Run:

```bash
swift test --filter URIImportTests
```

Expected: FAIL with compiler errors for missing `parseShadowsocksDraft` and missing `URIImportError` cases.

- [ ] **Step 3: Implement Shadowsocks parser**

Replace `packages/IrockAppFeature/Sources/IrockAppFeature/URIImport.swift` with:

```swift
import Foundation
import IrockCore

public enum URIImportError: Error, Equatable, Sendable {
    case missingScheme
    case unsupportedScheme(String)
    case malformedURI
    case invalidBase64
    case missingUserInfo
    case missingHost
    case missingPort
}

public struct URIImportResult: Equatable, Sendable {
    public let protocolType: ProxyProtocolType
    public let originalText: String

    public init(protocolType: ProxyProtocolType, originalText: String) {
        self.protocolType = protocolType
        self.originalText = originalText
    }
}

public enum URIImport {
    public static func classify(_ text: String) throws -> URIImportResult {
        guard let scheme = URLComponents(string: text)?.scheme?.lowercased() else {
            throw URIImportError.missingScheme
        }

        switch scheme {
        case "ss":
            return URIImportResult(protocolType: .shadowsocks, originalText: text)
        case "vmess":
            return URIImportResult(protocolType: .vmess, originalText: text)
        case "vless":
            return URIImportResult(protocolType: .vless, originalText: text)
        case "trojan":
            return URIImportResult(protocolType: .trojan, originalText: text)
        case "hysteria2":
            return URIImportResult(protocolType: .hysteria2, originalText: text)
        case "tuic":
            return URIImportResult(protocolType: .tuic, originalText: text)
        default:
            throw URIImportError.unsupportedScheme(scheme)
        }
    }

    public static func parseShadowsocksDraft(_ text: String) throws -> NodeDraft {
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased() else {
            throw URIImportError.missingScheme
        }
        guard scheme == "ss" else {
            throw URIImportError.unsupportedScheme(scheme)
        }

        let payload = String(text.dropFirst("ss://".count))
        guard !payload.isEmpty else {
            throw URIImportError.malformedURI
        }

        let withoutFragment = payload.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let fragmentName = components.percentEncodedFragment?.removingPercentEncoding
        let parsed = try parseShadowsocksPayload(String(withoutFragment))
        let name = fragmentName?.isEmpty == false ? fragmentName! : "\(parsed.host):\(parsed.port)"

        return NodeDraft(
            name: name,
            protocolType: .shadowsocks,
            serverHost: parsed.host,
            serverPortText: parsed.port,
            credentialAccount: parsed.userInfo,
            transport: .tcp,
            tlsEnabled: false,
            tlsServerName: "",
            udpEnabled: false
        )
    }

    private static func parseShadowsocksPayload(_ payload: String) throws -> (userInfo: String, host: String, port: String) {
        if let atIndex = payload.firstIndex(of: "@") {
            let encodedUserInfo = String(payload[..<atIndex])
            let endpoint = String(payload[payload.index(after: atIndex)...])
            let userInfo = try decodeBase64String(encodedUserInfo)
            let parsedEndpoint = try parseEndpoint(endpoint)
            return (userInfo, parsedEndpoint.host, parsedEndpoint.port)
        }

        let decoded = try decodeBase64String(payload)
        guard let atIndex = decoded.lastIndex(of: "@") else {
            throw URIImportError.missingUserInfo
        }
        let userInfo = String(decoded[..<atIndex])
        let endpoint = String(decoded[decoded.index(after: atIndex)...])
        let parsedEndpoint = try parseEndpoint(endpoint)
        return (userInfo, parsedEndpoint.host, parsedEndpoint.port)
    }

    private static func parseEndpoint(_ endpoint: String) throws -> (host: String, port: String) {
        guard let colonIndex = endpoint.lastIndex(of: ":") else {
            throw URIImportError.missingPort
        }
        let host = String(endpoint[..<colonIndex])
        let port = String(endpoint[endpoint.index(after: colonIndex)...])
        guard !host.isEmpty else {
            throw URIImportError.missingHost
        }
        guard !port.isEmpty else {
            throw URIImportError.missingPort
        }
        return (host, port)
    }

    private static func decodeBase64String(_ text: String) throws -> String {
        var normalized = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: normalized), let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty else {
            throw URIImportError.invalidBase64
        }
        return decoded
    }
}
```

- [ ] **Step 4: Run URI import tests**

Run:

```bash
swift test --filter URIImportTests
```

Expected: PASS with all `URIImportTests` passing.

- [ ] **Step 5: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

- [ ] **Step 6: Commit Shadowsocks parser**

Run:

```bash
git add packages/IrockAppFeature/Sources/IrockAppFeature/URIImport.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift
git commit -m "$(cat <<'EOF'
feat: parse Shadowsocks URI imports

Convert common ss:// URI forms into NodeDraft values so imported Shadowsocks nodes can flow through existing app configuration validation.

Constraint: Do not add protocol runtime, Keychain writes, or subscription import behavior
Confidence: high
Scope-risk: narrow
EOF
)"
```

---

### Task 2: Refresh project guidance for M5

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Add: `docs/superpowers/plans/2026-05-10-irock-m5-shadowsocks-uri-import.md`

- [ ] **Step 1: Update README current phase**

Replace the current phase paragraph and bullets in `README.md` with:

```markdown
## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, M2 TUN data path core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, and M5 Shadowsocks URI import foundation:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing/storage behavior, file-backed snapshot persistence, app feature state, runtime snapshot publishing, Shadowsocks URI import, packet parsing, flow tracking, and tunnel runtime processing
- Xcode target creation instructions; Xcode workspace, app targets, and Packet Tunnel targets are not yet committed
```

- [ ] **Step 2: Update README plan list**

Replace the implementation plan list in `README.md` with:

```markdown
## Implementation plans

- M0: `docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md`
- M1: `docs/superpowers/plans/2026-05-10-irock-m1-ui-configuration.md`
- M2: `docs/superpowers/plans/2026-05-10-irock-m2-tun-data-path.md`
- M3: `docs/superpowers/plans/2026-05-10-irock-m3-runtime-snapshot-persistence.md`
- M4: `docs/superpowers/plans/2026-05-10-irock-m4-runtime-snapshot-publishing.md`
- M5: `docs/superpowers/plans/2026-05-10-irock-m5-shadowsocks-uri-import.md`
```

- [ ] **Step 3: Update CLAUDE.md project status**

Replace the project status paragraph in `CLAUDE.md` with:

```markdown
## Project status

irock has a SwiftPM package graph, M1 app feature configuration scaffolding, M2 tunnel core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, and M5 Shadowsocks URI import foundation in the working tree. The committed product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Implementation plans live under `docs/superpowers/plans/`, including M0 engineering foundation, M1 UI configuration, M2 TUN data path, M3 runtime snapshot persistence, M4 runtime snapshot publishing, and M5 Shadowsocks URI import.

There is not yet an Xcode workspace, app target, or Packet Tunnel target in the working tree. Do not assume `xcodebuild` or app schemes exist until Xcode targets are created.
```

- [ ] **Step 4: Update CLAUDE.md AppFeature boundary**

Replace the `IrockAppFeature` bullet in `CLAUDE.md` with:

```markdown
- `IrockAppFeature`: reusable app-facing configuration, validation, URI import, runtime snapshot publishing, and snapshot coordination logic for future thin platform app shells.
```

- [ ] **Step 5: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

- [ ] **Step 6: Commit M5 guidance**

Run:

```bash
git add README.md CLAUDE.md docs/superpowers/plans/2026-05-10-irock-m5-shadowsocks-uri-import.md
git commit -m "$(cat <<'EOF'
docs: refresh project guidance for M5

Document Shadowsocks URI import as the first concrete URI-to-node-draft path in the app feature layer.

Constraint: Keep non-Shadowsocks URI parsing and subscription import out of M5
Confidence: high
Scope-risk: narrow
EOF
)"
```

---

## Verification Checklist

After completing all tasks, run:

```bash
git status --short
swift test
```

Expected final state:

- `git status --short` shows no uncommitted tracked changes.
- `swift test` passes with all SwiftPM tests.
- `URIImport.classify(_:)` existing scheme classification still works.
- `URIImport.parseShadowsocksDraft(_:)` parses supported `ss://` forms into `NodeDraft`.
- `URIImportTests` cover supported forms and stable error cases.
- README and CLAUDE.md mention M5 Shadowsocks URI import.
