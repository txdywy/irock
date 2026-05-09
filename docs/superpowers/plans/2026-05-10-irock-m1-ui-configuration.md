# irock M1 UI Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the testable M1 foundation for irock's basic UI and configuration flows: overview state, node list, manual node editing, URI import entry point, basic logs, and settings model.

**Architecture:** M1 adds a SwiftPM package named `IrockAppFeature` instead of creating Xcode app targets immediately. The package contains SwiftUI views and view models that can compile and run tests without signing, App Groups, or Network Extension entitlements. Later Xcode app shells will import this package and mount the views.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, SwiftUI, IrockCore, IrockDiagnostics, IrockRouting, IrockStorage.

---

## Scope

M1 implements the UI/configuration foundation promised by the design spec's M1 milestone:

- Overview/home state model with connection status, selected node, route mode, and recent logs.
- Node list model.
- Manual node form draft model.
- URI import parser entry point that classifies supported URI schemes but does not implement full protocol parsing yet.
- Basic connection log view model.
- Settings model for VPN permission/App Group/debug toggles.
- SwiftUI page skeletons for overview, nodes, logs, and settings.

M1 does **not** create actual `.xcodeproj`, `.xcworkspace`, Packet Tunnel targets, VPN permission flows, App Group persistence, Keychain storage, real URI protocol parsing, or visual polish beyond compile-safe SwiftUI skeletons.

## File Structure

Create and modify these files:

```text
Package.swift
README.md
packages/IrockAppFeature/Sources/IrockAppFeature/AppFeatureModels.swift
packages/IrockAppFeature/Sources/IrockAppFeature/NodeDraft.swift
packages/IrockAppFeature/Sources/IrockAppFeature/URIImport.swift
packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift
packages/IrockAppFeature/Sources/IrockAppFeature/AppViews.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppFeatureModelsTests.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/NodeDraftTests.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
```

`IrockAppFeature` depends on `IrockCore`, `IrockRouting`, `IrockStorage`, and `IrockDiagnostics`.

---

### Task 1: Add IrockAppFeature package target

**Files:**
- Modify: `Package.swift`
- Test: `swift test`

- [ ] **Step 1: Add failing package reference test by creating a minimal test file**

Create `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppFeatureModelsTests.swift`:

```swift
import XCTest
@testable import IrockAppFeature

final class AppFeatureModelsTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(IrockAppFeatureModule.name, "IrockAppFeature")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter IrockAppFeatureTests
```

Expected: FAIL because `IrockAppFeature` target does not exist.

- [ ] **Step 3: Add package product and target**

Modify `Package.swift`:

1. Add product after `IrockPerformanceKit`:

```swift
.library(name: "IrockAppFeature", targets: ["IrockAppFeature"])
```

2. Add target after `IrockPerformanceKitTests`:

```swift
.target(
    name: "IrockAppFeature",
    dependencies: ["IrockCore", "IrockRouting", "IrockStorage", "IrockDiagnostics"],
    path: "packages/IrockAppFeature/Sources/IrockAppFeature"
),
.testTarget(
    name: "IrockAppFeatureTests",
    dependencies: ["IrockAppFeature"],
    path: "packages/IrockAppFeature/Tests/IrockAppFeatureTests"
)
```

Keep the manifest valid Swift with commas between target entries.

- [ ] **Step 4: Add minimal source**

Create `packages/IrockAppFeature/Sources/IrockAppFeature/AppFeatureModels.swift`:

```swift
public enum IrockAppFeatureModule {
    public static let name = "IrockAppFeature"
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter IrockAppFeatureTests
swift test
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift packages/IrockAppFeature
git commit -m "chore: add app feature package"
```

---

### Task 2: Add app feature state models

**Files:**
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppFeatureModels.swift`
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppFeatureModelsTests.swift`

- [ ] **Step 1: Replace model tests**

Replace `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppFeatureModelsTests.swift` with:

```swift
import XCTest
import IrockCore
@testable import IrockAppFeature

final class AppFeatureModelsTests: XCTestCase {
    func testOverviewStateStoresConnectionStatusAndRouteMode() {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo Node",
            protocolType: .trojan,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: .disabled
        )

        let state = OverviewState(connectionStatus: .connected, selectedNode: node, routeMode: .ruleBased, recentLogMessages: ["Connected"])

        XCTAssertEqual(state.connectionStatus, .connected)
        XCTAssertEqual(state.selectedNode?.name, "Demo Node")
        XCTAssertEqual(state.routeMode, .ruleBased)
        XCTAssertEqual(state.recentLogMessages, ["Connected"])
    }

    func testConnectionStatusDisplayText() {
        XCTAssertEqual(ConnectionStatus.disconnected.displayText, "未连接")
        XCTAssertEqual(ConnectionStatus.connecting.displayText, "连接中")
        XCTAssertEqual(ConnectionStatus.connected.displayText, "已连接")
        XCTAssertEqual(ConnectionStatus.failed.displayText, "连接失败")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AppFeatureModelsTests
```

Expected: FAIL because `OverviewState` and `ConnectionStatus` are missing.

- [ ] **Step 3: Implement models**

Replace `packages/IrockAppFeature/Sources/IrockAppFeature/AppFeatureModels.swift` with:

```swift
import IrockCore

public enum IrockAppFeatureModule {
    public static let name = "IrockAppFeature"
}

public enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case preparing
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case failed

    public var displayText: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .preparing, .connecting, .reconnecting:
            return "连接中"
        case .connected:
            return "已连接"
        case .disconnecting:
            return "断开中"
        case .failed:
            return "连接失败"
        }
    }
}

public struct OverviewState: Equatable, Sendable {
    public let connectionStatus: ConnectionStatus
    public let selectedNode: ProxyNode?
    public let routeMode: RouteMode
    public let recentLogMessages: [String]

    public init(connectionStatus: ConnectionStatus, selectedNode: ProxyNode?, routeMode: RouteMode, recentLogMessages: [String]) {
        self.connectionStatus = connectionStatus
        self.selectedNode = selectedNode
        self.routeMode = routeMode
        self.recentLogMessages = recentLogMessages
    }
}

public struct NodeListState: Equatable, Sendable {
    public let nodes: [ProxyNode]
    public let selectedNodeID: NodeID?

    public init(nodes: [ProxyNode], selectedNodeID: NodeID?) {
        self.nodes = nodes
        self.selectedNodeID = selectedNodeID
    }
}

public struct SettingsState: Equatable, Sendable {
    public let vpnPermissionStatus: String
    public let appGroupStatus: String
    public let debugLoggingEnabled: Bool

    public init(vpnPermissionStatus: String, appGroupStatus: String, debugLoggingEnabled: Bool) {
        self.vpnPermissionStatus = vpnPermissionStatus
        self.appGroupStatus = appGroupStatus
        self.debugLoggingEnabled = debugLoggingEnabled
    }
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter AppFeatureModelsTests
swift test
git add packages/IrockAppFeature/Sources/IrockAppFeature/AppFeatureModels.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppFeatureModelsTests.swift
git commit -m "feat: add app feature state models"
```

Expected: tests pass and commit succeeds.

---

### Task 3: Add manual node draft model

**Files:**
- Create: `packages/IrockAppFeature/Sources/IrockAppFeature/NodeDraft.swift`
- Create: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/NodeDraftTests.swift`

- [ ] **Step 1: Write failing tests**

Create `packages/IrockAppFeature/Tests/IrockAppFeatureTests/NodeDraftTests.swift`:

```swift
import XCTest
import IrockCore
@testable import IrockAppFeature

final class NodeDraftTests: XCTestCase {
    func testDraftBuildsProxyNodeWhenRequiredFieldsExist() throws {
        let draft = NodeDraft(
            name: "Demo Trojan",
            protocolType: .trojan,
            serverHost: "example.com",
            serverPortText: "443",
            credentialAccount: "node-1",
            transport: .tcp,
            tlsEnabled: true,
            tlsServerName: "example.com",
            udpEnabled: false
        )

        let node = try draft.buildNode(id: NodeID(rawValue: "node-1"), keychainService: "com.irock.nodes")

        XCTAssertEqual(node.name, "Demo Trojan")
        XCTAssertEqual(node.serverPort, 443)
        XCTAssertEqual(node.credentialReference.account, "node-1")
        XCTAssertTrue(node.tls.enabled)
        XCTAssertEqual(node.udpPolicy, .disabled)
    }

    func testDraftRejectsInvalidPort() {
        let draft = NodeDraft(name: "Bad", protocolType: .trojan, serverHost: "example.com", serverPortText: "99999", credentialAccount: "node-1", transport: .tcp, tlsEnabled: false, tlsServerName: "", udpEnabled: false)

        XCTAssertThrowsError(try draft.buildNode(id: NodeID(rawValue: "node-1"), keychainService: "com.irock.nodes")) { error in
            XCTAssertEqual(error as? NodeDraftError, .invalidPort)
        }
    }
}
```

- [ ] **Step 2: Run test to verify failure**

```bash
swift test --filter NodeDraftTests
```

Expected: FAIL because `NodeDraft` is missing.

- [ ] **Step 3: Implement node draft**

Create `packages/IrockAppFeature/Sources/IrockAppFeature/NodeDraft.swift`:

```swift
import IrockCore

public enum NodeDraftError: Error, Equatable, Sendable {
    case missingName
    case missingHost
    case missingCredentialAccount
    case invalidPort
}

public struct NodeDraft: Equatable, Sendable {
    public var name: String
    public var protocolType: ProxyProtocolType
    public var serverHost: String
    public var serverPortText: String
    public var credentialAccount: String
    public var transport: TransportType
    public var tlsEnabled: Bool
    public var tlsServerName: String
    public var udpEnabled: Bool

    public init(name: String, protocolType: ProxyProtocolType, serverHost: String, serverPortText: String, credentialAccount: String, transport: TransportType, tlsEnabled: Bool, tlsServerName: String, udpEnabled: Bool) {
        self.name = name
        self.protocolType = protocolType
        self.serverHost = serverHost
        self.serverPortText = serverPortText
        self.credentialAccount = credentialAccount
        self.transport = transport
        self.tlsEnabled = tlsEnabled
        self.tlsServerName = tlsServerName
        self.udpEnabled = udpEnabled
    }

    public func buildNode(id: NodeID, keychainService: String) throws -> ProxyNode {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = credentialAccount.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { throw NodeDraftError.missingName }
        guard !trimmedHost.isEmpty else { throw NodeDraftError.missingHost }
        guard !trimmedAccount.isEmpty else { throw NodeDraftError.missingCredentialAccount }
        guard let port = Int(serverPortText), (1...65535).contains(port) else { throw NodeDraftError.invalidPort }

        return ProxyNode(
            id: id,
            name: trimmedName,
            protocolType: protocolType,
            serverHost: trimmedHost,
            serverPort: port,
            credentialReference: CredentialReference(keychainService: keychainService, account: trimmedAccount),
            transport: transport,
            tls: TLSOptions(enabled: tlsEnabled, serverName: tlsServerName.isEmpty ? nil : tlsServerName, allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: udpEnabled ? .enabled : .disabled
        )
    }
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter NodeDraftTests
swift test
git add packages/IrockAppFeature/Sources/IrockAppFeature/NodeDraft.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/NodeDraftTests.swift
git commit -m "feat: add manual node draft model"
```

---

### Task 4: Add URI import classifier

**Files:**
- Create: `packages/IrockAppFeature/Sources/IrockAppFeature/URIImport.swift`
- Create: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift`

- [ ] **Step 1: Write failing tests**

Create `packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift`:

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
}
```

- [ ] **Step 2: Run test to verify failure**

```bash
swift test --filter URIImportTests
```

Expected: FAIL because `URIImport` is missing.

- [ ] **Step 3: Implement classifier**

Create `packages/IrockAppFeature/Sources/IrockAppFeature/URIImport.swift`:

```swift
import Foundation
import IrockCore

public enum URIImportError: Error, Equatable, Sendable {
    case missingScheme
    case unsupportedScheme(String)
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
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter URIImportTests
swift test
git add packages/IrockAppFeature/Sources/IrockAppFeature/URIImport.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift
git commit -m "feat: add URI import classifier"
```

---

### Task 5: Add view models

**Files:**
- Create: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`
- Create: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`

- [ ] **Step 1: Write failing tests**

Create `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`:

```swift
import XCTest
import IrockCore
@testable import IrockAppFeature

final class AppViewModelsTests: XCTestCase {
    func testAppViewModelSelectsNode() {
        let node = ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled)
        let model = AppViewModel(nodes: [node])

        model.selectNode(id: NodeID(rawValue: "node-1"))

        XCTAssertEqual(model.nodeListState.selectedNodeID?.rawValue, "node-1")
        XCTAssertEqual(model.overviewState.selectedNode?.name, "Demo")
    }

    func testAppViewModelAppendsBoundedLogs() {
        let model = AppViewModel(nodes: [], logLimit: 2)

        model.appendLog("first")
        model.appendLog("second")
        model.appendLog("third")

        XCTAssertEqual(model.overviewState.recentLogMessages, ["second", "third"])
    }
}
```

- [ ] **Step 2: Run test to verify failure**

```bash
swift test --filter AppViewModelsTests
```

Expected: FAIL because `AppViewModel` is missing.

- [ ] **Step 3: Implement view model**

Create `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`:

```swift
import Foundation
import IrockCore

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var overviewState: OverviewState
    @Published public private(set) var nodeListState: NodeListState
    @Published public private(set) var settingsState: SettingsState

    private let logLimit: Int

    public init(nodes: [ProxyNode], logLimit: Int = 5) {
        self.logLimit = max(0, logLimit)
        self.nodeListState = NodeListState(nodes: nodes, selectedNodeID: nil)
        self.overviewState = OverviewState(connectionStatus: .disconnected, selectedNode: nil, routeMode: .ruleBased, recentLogMessages: [])
        self.settingsState = SettingsState(vpnPermissionStatus: "未配置", appGroupStatus: "未验证", debugLoggingEnabled: false)
    }

    public func selectNode(id: NodeID) {
        let selected = nodeListState.nodes.first { $0.id == id }
        nodeListState = NodeListState(nodes: nodeListState.nodes, selectedNodeID: selected?.id)
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: selected, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
    }

    public func appendLog(_ message: String) {
        var messages = overviewState.recentLogMessages
        messages.append(message)
        if messages.count > logLimit {
            messages.removeFirst(messages.count - logLimit)
        }
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: messages)
    }
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter AppViewModelsTests
swift test
git add packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
git commit -m "feat: add app feature view model"
```

---

### Task 6: Add SwiftUI page skeletons

**Files:**
- Create: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViews.swift`
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppFeatureModelsTests.swift`

- [ ] **Step 1: Add compile smoke test for views**

Append this test to `AppFeatureModelsTests`:

```swift
    func testRootViewCanBeConstructed() {
        let viewModel = AppViewModel(nodes: [])
        _ = IrockRootView(viewModel: viewModel)
    }
```

- [ ] **Step 2: Run test to verify failure**

```bash
swift test --filter AppFeatureModelsTests/testRootViewCanBeConstructed
```

Expected: FAIL because `IrockRootView` is missing.

- [ ] **Step 3: Implement SwiftUI skeletons**

Create `packages/IrockAppFeature/Sources/IrockAppFeature/AppViews.swift`:

```swift
import SwiftUI

public struct IrockRootView: View {
    @ObservedObject private var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            OverviewView(state: viewModel.overviewState)
                .tabItem { Text("概览") }
            NodeListView(state: viewModel.nodeListState)
                .tabItem { Text("节点") }
            LogListView(messages: viewModel.overviewState.recentLogMessages)
                .tabItem { Text("日志") }
            SettingsView(state: viewModel.settingsState)
                .tabItem { Text("设置") }
        }
    }
}

public struct OverviewView: View {
    public let state: OverviewState

    public init(state: OverviewState) {
        self.state = state
    }

    public var body: some View {
        List {
            Text(state.connectionStatus.displayText)
            Text(state.selectedNode?.name ?? "未选择节点")
            Text(state.routeMode.rawValue)
        }
    }
}

public struct NodeListView: View {
    public let state: NodeListState

    public init(state: NodeListState) {
        self.state = state
    }

    public var body: some View {
        List(state.nodes, id: \.id) { node in
            Text(node.name)
        }
    }
}

public struct LogListView: View {
    public let messages: [String]

    public init(messages: [String]) {
        self.messages = messages
    }

    public var body: some View {
        List(messages, id: \.self) { message in
            Text(message)
        }
    }
}

public struct SettingsView: View {
    public let state: SettingsState

    public init(state: SettingsState) {
        self.state = state
    }

    public var body: some View {
        List {
            Text("VPN 权限：\(state.vpnPermissionStatus)")
            Text("App Group：\(state.appGroupStatus)")
            Text("Debug 日志：\(state.debugLoggingEnabled ? "开启" : "关闭")")
        }
    }
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter AppFeatureModelsTests/testRootViewCanBeConstructed
swift test
git add packages/IrockAppFeature/Sources/IrockAppFeature/AppViews.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppFeatureModelsTests.swift
git commit -m "feat: add SwiftUI app feature skeletons"
```

---

### Task 7: Update docs and final verification

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README implementation plans**

Replace the `## Implementation plans` section in `README.md` with:

```markdown
## Implementation plans

- M0: `docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md`
- M1: `docs/superpowers/plans/2026-05-10-irock-m1-ui-configuration.md`
```

- [ ] **Step 2: Update CLAUDE commands**

In `CLAUDE.md`, ensure commands include:

```markdown
- Run all SwiftPM tests: `swift test`
- Run a single test target: `swift test --filter IrockCoreTests`
- Run app feature tests: `swift test --filter IrockAppFeatureTests`
```

Keep existing guidance about no Xcode targets unless they actually exist.

- [ ] **Step 3: Run final verification**

```bash
swift test
git status --short --ignored
git log --oneline --max-count=12
```

Expected:

- `swift test` passes.
- Only ignored scratch/build directories appear under ignored output.
- Recent commits include all M1 task commits.

- [ ] **Step 4: Commit docs**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document M1 app feature plan"
```

---

## Self-Review

Spec coverage:

- Home/overview: Task 2 and Task 6.
- Node list: Task 2, Task 5, Task 6.
- Manual add node: Task 3.
- URI import entry: Task 4.
- Basic logs: Task 2, Task 5, Task 6.
- Settings page model: Task 2 and Task 6.
- Xcode app targets: intentionally deferred because M0 documented they require signing/team choices.

Placeholder scan: no placeholder markers or unspecified implementation steps are required for M1 execution.

Type consistency:

- `ProxyNode` uses `CredentialReference`, matching M0's secure runtime snapshot model.
- `RouteMode`, `NodeID`, `ProxyProtocolType`, `TransportType`, and `TLSOptions` match M0 type names.
- `AppViewModel`, `OverviewState`, `NodeListState`, and `SettingsState` are defined before SwiftUI views use them.
