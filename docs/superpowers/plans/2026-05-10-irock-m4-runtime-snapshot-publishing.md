# irock M4 Runtime Snapshot Publishing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AppFeature runtime snapshot publishing so selected app state can be frozen into `RuntimeSnapshot` and saved through `RuntimeSnapshotStore`.

**Architecture:** M4 adds a focused `RuntimeSnapshotPublisher` in `IrockAppFeature` and wires `AppViewModel` to it. The publisher owns app-level publish semantics while `IrockStorage` remains responsible only for persistence; no Xcode, App Group, VPN, or NetworkExtension code is introduced.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, SwiftUI ObservableObject, `IrockCore`, `IrockStorage`.

---

## File Structure

M4 creates and modifies these files:

```text
packages/IrockAppFeature/Sources/IrockAppFeature/RuntimeSnapshotPublisher.swift
packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/RuntimeSnapshotPublisherTests.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
README.md
CLAUDE.md
docs/superpowers/plans/2026-05-10-irock-m4-runtime-snapshot-publishing.md
```

Responsibilities:

- `RuntimeSnapshotPublisher.swift`: builds and saves `RuntimeSnapshot` through a store, returning publish results.
- `AppViewModels.swift`: exposes route/debug state mutation and publish action for future connect flow.
- `RuntimeSnapshotPublisherTests.swift`: tests publisher success and failure behavior.
- `AppViewModelsTests.swift`: tests ViewModel publishing integration and user logs.
- `README.md` and `CLAUDE.md`: update project status to include M4.

---

### Task 1: Add RuntimeSnapshotPublisher

**Files:**
- Create: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/RuntimeSnapshotPublisherTests.swift`
- Create: `packages/IrockAppFeature/Sources/IrockAppFeature/RuntimeSnapshotPublisher.swift`

- [ ] **Step 1: Write failing publisher tests**

Create `packages/IrockAppFeature/Tests/IrockAppFeatureTests/RuntimeSnapshotPublisherTests.swift`:

```swift
import XCTest
import IrockCore
import IrockStorage
@testable import IrockAppFeature

final class RuntimeSnapshotPublisherTests: XCTestCase {
    func testPublisherSavesSnapshotAndReturnsPublishedID() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)
        let node = makeNode(id: "node-1", name: "Demo")

        let result = publisher.publish(selectedNode: node, routeMode: .globalProxy, logLevel: .user)

        guard case let .published(snapshotID) = result else {
            return XCTFail("Expected published result")
        }
        XCTAssertTrue(snapshotID.rawValue.hasPrefix("snapshot-"))
        XCTAssertEqual(try store.load()?.selectedNode, node)
    }

    func testPublisherReturnsMissingSelectedNodeWithoutSaving() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)

        let result = publisher.publish(selectedNode: nil, routeMode: .ruleBased, logLevel: .user)

        XCTAssertEqual(result, .missingSelectedNode)
        XCTAssertNil(try store.load())
    }

    func testPublisherWritesRouteModeAndLogLevelIntoSnapshot() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)

        _ = publisher.publish(selectedNode: makeNode(id: "node-1", name: "Demo"), routeMode: .direct, logLevel: .debug)

        let snapshot = try XCTUnwrap(store.load())
        XCTAssertEqual(snapshot.routeMode, .direct)
        XCTAssertEqual(snapshot.logLevel, .debug)
    }

    func testPublisherReturnsStorageFailedWhenStoreThrows() {
        let publisher = RuntimeSnapshotPublisher(store: FailingRuntimeSnapshotStore())

        let result = publisher.publish(selectedNode: makeNode(id: "node-1", name: "Demo"), routeMode: .ruleBased, logLevel: .user)

        guard case let .storageFailed(message) = result else {
            return XCTFail("Expected storageFailed result")
        }
        XCTAssertTrue(message.contains("write failed"))
    }

    private func makeNode(id: String, name: String) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: id),
            name: name,
            protocolType: .trojan,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: id),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
    }
}

private struct FailingRuntimeSnapshotStore: RuntimeSnapshotStore {
    func save(_ snapshot: RuntimeSnapshot) throws {
        throw FailingStoreError.writeFailed
    }

    func load() throws -> RuntimeSnapshot? {
        nil
    }
}

private enum FailingStoreError: Error, CustomStringConvertible {
    case writeFailed

    var description: String {
        "write failed"
    }
}
```

- [ ] **Step 2: Run publisher tests to verify failure**

Run:

```bash
swift test --filter RuntimeSnapshotPublisherTests
```

Expected: FAIL with compiler errors like `cannot find 'RuntimeSnapshotPublisher' in scope`.

- [ ] **Step 3: Implement publisher**

Create `packages/IrockAppFeature/Sources/IrockAppFeature/RuntimeSnapshotPublisher.swift`:

```swift
import Foundation
import IrockCore
import IrockStorage

public enum RuntimeSnapshotPublishResult: Equatable, Sendable {
    case published(SnapshotID)
    case missingSelectedNode
    case storageFailed(String)
}

public struct RuntimeSnapshotPublisher: @unchecked Sendable {
    private let store: RuntimeSnapshotStore

    public init(store: RuntimeSnapshotStore) {
        self.store = store
    }

    public func publish(selectedNode: ProxyNode?, routeMode: RouteMode, logLevel: IrockLogLevel) -> RuntimeSnapshotPublishResult {
        guard let selectedNode else {
            return .missingSelectedNode
        }

        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-\(UUID().uuidString)"),
            selectedNode: selectedNode,
            routeMode: routeMode,
            logLevel: logLevel
        )

        do {
            try store.save(snapshot)
            return .published(snapshot.id)
        } catch {
            return .storageFailed(String(describing: error))
        }
    }
}
```

- [ ] **Step 4: Run publisher tests**

Run:

```bash
swift test --filter RuntimeSnapshotPublisherTests
```

Expected: PASS with all `RuntimeSnapshotPublisherTests` passing.

- [ ] **Step 5: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

- [ ] **Step 6: Commit publisher**

Run:

```bash
git add packages/IrockAppFeature/Sources/IrockAppFeature/RuntimeSnapshotPublisher.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/RuntimeSnapshotPublisherTests.swift
git commit -m "$(cat <<'EOF'
feat: add runtime snapshot publisher

Create the app feature boundary that converts selected node state into a persisted RuntimeSnapshot without depending on platform App Group or VPN APIs.

Constraint: Keep publishing SwiftPM-testable through RuntimeSnapshotStore injection
Confidence: high
Scope-risk: narrow
EOF
)"
```

---

### Task 2: Wire AppViewModel to snapshot publishing

**Files:**
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`

- [ ] **Step 1: Replace AppViewModel tests with publishing coverage**

Replace `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift` with:

```swift
import XCTest
import IrockCore
import IrockStorage
@testable import IrockAppFeature

final class AppViewModelsTests: XCTestCase {
    @MainActor
    func testAppViewModelSelectsNode() {
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node])

        model.selectNode(id: NodeID(rawValue: "node-1"))

        XCTAssertEqual(model.nodeListState.selectedNodeID?.rawValue, "node-1")
        XCTAssertEqual(model.overviewState.selectedNode?.name, "Demo")
    }

    @MainActor
    func testAppViewModelAppendsBoundedLogs() {
        let model = AppViewModel(nodes: [], logLimit: 2)

        model.appendLog("first")
        model.appendLog("second")
        model.appendLog("third")

        XCTAssertEqual(model.overviewState.recentLogMessages, ["second", "third"])
    }

    @MainActor
    func testAppViewModelUpdatesRouteModeBeforePublishing() throws {
        let node = makeNode(id: "node-1", name: "Demo")
        let store = InMemoryRuntimeSnapshotStore()
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)

        model.selectNode(id: node.id)
        model.setRouteMode(.direct)
        let result = model.publishRuntimeSnapshot()

        guard case .published = result else {
            return XCTFail("Expected published result")
        }
        XCTAssertEqual(model.overviewState.routeMode, .direct)
        XCTAssertEqual(try store.load()?.routeMode, .direct)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("运行配置已发布"))
    }

    @MainActor
    func testAppViewModelPublishesDebugSnapshotWhenDebugLoggingEnabled() throws {
        let node = makeNode(id: "node-1", name: "Demo")
        let store = InMemoryRuntimeSnapshotStore()
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)

        model.selectNode(id: node.id)
        model.setDebugLoggingEnabled(true)
        _ = model.publishRuntimeSnapshot()

        XCTAssertTrue(model.settingsState.debugLoggingEnabled)
        XCTAssertEqual(try store.load()?.logLevel, .debug)
    }

    @MainActor
    func testAppViewModelLogsMissingNodeWhenPublishingWithoutSelection() {
        let model = AppViewModel(nodes: [])

        let result = model.publishRuntimeSnapshot()

        XCTAssertEqual(result, .missingSelectedNode)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("请选择节点后再启动"))
    }

    private func makeNode(id: String, name: String) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: id),
            name: name,
            protocolType: .trojan,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: id),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
    }
}
```

- [ ] **Step 2: Run AppViewModel tests to verify failure**

Run:

```bash
swift test --filter AppViewModelsTests
```

Expected: FAIL with missing initializer/method errors for `runtimeSnapshotStore`, `setRouteMode`, `setDebugLoggingEnabled`, and `publishRuntimeSnapshot`.

- [ ] **Step 3: Implement AppViewModel publishing integration**

Replace `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift` with:

```swift
import Foundation
import IrockCore
import IrockStorage

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var overviewState: OverviewState
    @Published public private(set) var nodeListState: NodeListState
    @Published public private(set) var settingsState: SettingsState

    private let logLimit: Int
    private let runtimeSnapshotPublisher: RuntimeSnapshotPublisher

    public init(nodes: [ProxyNode], logLimit: Int = 5, runtimeSnapshotStore: RuntimeSnapshotStore = InMemoryRuntimeSnapshotStore()) {
        self.logLimit = max(0, logLimit)
        self.runtimeSnapshotPublisher = RuntimeSnapshotPublisher(store: runtimeSnapshotStore)
        self.nodeListState = NodeListState(nodes: nodes, selectedNodeID: nil)
        self.overviewState = OverviewState(connectionStatus: .disconnected, selectedNode: nil, routeMode: .ruleBased, recentLogMessages: [])
        self.settingsState = SettingsState(vpnPermissionStatus: "未配置", appGroupStatus: "未验证", debugLoggingEnabled: false)
    }

    public func selectNode(id: NodeID) {
        let selected = nodeListState.nodes.first { $0.id == id }
        nodeListState = NodeListState(nodes: nodeListState.nodes, selectedNodeID: selected?.id)
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: selected, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
    }

    public func setRouteMode(_ routeMode: RouteMode) {
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: overviewState.selectedNode, routeMode: routeMode, recentLogMessages: overviewState.recentLogMessages)
    }

    public func setDebugLoggingEnabled(_ enabled: Bool) {
        settingsState = SettingsState(vpnPermissionStatus: settingsState.vpnPermissionStatus, appGroupStatus: settingsState.appGroupStatus, debugLoggingEnabled: enabled)
    }

    @discardableResult
    public func publishRuntimeSnapshot() -> RuntimeSnapshotPublishResult {
        let logLevel: IrockLogLevel = settingsState.debugLoggingEnabled ? .debug : .user
        let result = runtimeSnapshotPublisher.publish(selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, logLevel: logLevel)

        switch result {
        case .published:
            appendLog("运行配置已发布")
        case .missingSelectedNode:
            appendLog("请选择节点后再启动")
        case .storageFailed:
            appendLog("运行配置发布失败")
        }

        return result
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

- [ ] **Step 4: Run AppViewModel tests**

Run:

```bash
swift test --filter AppViewModelsTests
```

Expected: PASS with all `AppViewModelsTests` passing.

- [ ] **Step 5: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

- [ ] **Step 6: Commit ViewModel integration**

Run:

```bash
git add packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
git commit -m "$(cat <<'EOF'
feat: publish runtime snapshots from app view model

Wire AppViewModel to RuntimeSnapshotPublisher so future connect flows can persist selected node, route mode, and log level before starting tunnel work.

Constraint: Do not start VPN or access platform App Group APIs in M4
Confidence: high
Scope-risk: narrow
EOF
)"
```

---

### Task 3: Refresh project guidance for M4

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Add: `docs/superpowers/plans/2026-05-10-irock-m4-runtime-snapshot-publishing.md`

- [ ] **Step 1: Update README current phase**

Replace the current phase paragraph and bullets in `README.md` with:

```markdown
## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, M2 TUN data path core, M3 runtime snapshot persistence foundation, and M4 runtime snapshot publishing foundation:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing/storage behavior, file-backed snapshot persistence, app feature state, runtime snapshot publishing, packet parsing, flow tracking, and tunnel runtime processing
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
```

- [ ] **Step 3: Update CLAUDE.md project status**

Replace the project status paragraph in `CLAUDE.md` with:

```markdown
## Project status

irock has a SwiftPM package graph, M1 app feature configuration scaffolding, M2 tunnel core, M3 runtime snapshot persistence foundation, and M4 runtime snapshot publishing foundation in the working tree. The committed product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Implementation plans live under `docs/superpowers/plans/`, including M0 engineering foundation, M1 UI configuration, M2 TUN data path, M3 runtime snapshot persistence, and M4 runtime snapshot publishing.

There is not yet an Xcode workspace, app target, or Packet Tunnel target in the working tree. Do not assume `xcodebuild` or app schemes exist until Xcode targets are created.
```

- [ ] **Step 4: Update CLAUDE.md AppFeature boundary**

Replace the `IrockAppFeature` bullet in `CLAUDE.md` with:

```markdown
- `IrockAppFeature`: reusable app-facing configuration, validation, runtime snapshot publishing, and snapshot coordination logic for future thin platform app shells.
```

- [ ] **Step 5: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

- [ ] **Step 6: Commit M4 guidance**

Run:

```bash
git add README.md CLAUDE.md docs/superpowers/plans/2026-05-10-irock-m4-runtime-snapshot-publishing.md
git commit -m "$(cat <<'EOF'
docs: refresh project guidance for M4

Document runtime snapshot publishing as the app-side bridge from editable configuration state to tunnel runtime snapshots.

Constraint: Keep Xcode and Network Extension target setup deferred
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
- `IrockAppFeature` contains `RuntimeSnapshotPublisher`.
- `AppViewModel` can set route mode, set debug logging, and publish a runtime snapshot.
- `RuntimeSnapshotPublisherTests` and `AppViewModelsTests` cover M4 success and failure behavior.
- README and CLAUDE.md mention M4 runtime snapshot publishing.
