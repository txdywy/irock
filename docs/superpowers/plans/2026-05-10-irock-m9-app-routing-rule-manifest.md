# irock M9 App Routing Rule Manifest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert local routing rule text in AppFeature into `RuntimeRoutingRuleManifest` and publish it with runtime snapshots.

**Architecture:** M9 adds `RoutingRuleManifestBuilder` in `IrockAppFeature`, using `IrockRouting.RoutingRuleParser` as the source of truth for rule syntax. `AppViewModel` stores editable rule text and passes the built manifest to `RuntimeSnapshotPublisher`; Tunnel remains manifest-only.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, existing `IrockCore`, `IrockRouting`, and `IrockAppFeature` types.

---

## File Structure

M9 creates and modifies these files:

```text
packages/IrockAppFeature/Sources/IrockAppFeature/RoutingRuleManifestBuilder.swift
packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/RoutingRuleManifestBuilderTests.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
README.md
CLAUDE.md
docs/superpowers/specs/2026-05-10-irock-m9-app-routing-rule-manifest-design.md
docs/superpowers/plans/2026-05-10-irock-m9-app-routing-rule-manifest.md
```

Responsibilities:

- `RoutingRuleManifestBuilder.swift`: parse local rule text and convert routing rules to runtime manifest rules.
- `AppViewModels.swift`: store local routing rule text and publish manifests with snapshots.
- Tests: builder conversion, parser error propagation, view-model publish behavior.

---

### Task 1: Add RoutingRuleManifestBuilder tests

**Files:**
- Create: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/RoutingRuleManifestBuilderTests.swift`

- [ ] **Step 1: Create failing builder tests**

Create `packages/IrockAppFeature/Tests/IrockAppFeatureTests/RoutingRuleManifestBuilderTests.swift`:

```swift
import XCTest
import IrockCore
import IrockRouting
@testable import IrockAppFeature

final class RoutingRuleManifestBuilderTests: XCTestCase {
    func testBuilderConvertsLocalRuleTextToRuntimeManifest() throws {
        let manifest = try RoutingRuleManifestBuilder.buildManifest(from: """
        DOMAIN,example.com,DIRECT
        DOMAIN-SUFFIX,apple.com,PROXY
        DOMAIN-KEYWORD,google,REJECT
        IP-CIDR,10.0.0.0/8,DIRECT
        FINAL,PROXY
        """)

        XCTAssertEqual(manifest, RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domain, value: "example.com", action: .direct),
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .proxy),
                RuntimeRoutingRule(kind: .domainKeyword, value: "google", action: .reject),
                RuntimeRoutingRule(kind: .ipCIDR, value: "10.0.0.0/8", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        ))
    }

    func testBuilderReturnsEmptyManifestForEmptyOrCommentOnlyText() throws {
        let manifest = try RoutingRuleManifestBuilder.buildManifest(from: "\n# no local rules\n")

        XCTAssertEqual(manifest, .empty)
    }

    func testBuilderPropagatesParserErrors() {
        XCTAssertThrowsError(try RoutingRuleManifestBuilder.buildManifest(from: "DOMAIN,example.com,DROP")) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .unsupportedAction(line: 1, action: "DROP"))
        }
    }
}
```

- [ ] **Step 2: Run builder tests to verify failure**

Run:

```bash
swift test --filter RoutingRuleManifestBuilderTests
```

Expected: FAIL with compiler error for missing `RoutingRuleManifestBuilder`.

---

### Task 2: Implement RoutingRuleManifestBuilder

**Files:**
- Create: `packages/IrockAppFeature/Sources/IrockAppFeature/RoutingRuleManifestBuilder.swift`

- [ ] **Step 1: Create builder implementation**

Create `packages/IrockAppFeature/Sources/IrockAppFeature/RoutingRuleManifestBuilder.swift`:

```swift
import IrockCore
import IrockRouting

public enum RoutingRuleManifestBuilder {
    public static func buildManifest(from text: String) throws -> RuntimeRoutingRuleManifest {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        do {
            let rules = try RoutingRuleParser.parseLines(lines)
            return RuntimeRoutingRuleManifest(version: 1, rules: rules.map(runtimeRule(from:)))
        } catch RoutingRuleParseError.emptyInput {
            return .empty
        }
    }

    private static func runtimeRule(from rule: RoutingRule) -> RuntimeRoutingRule {
        switch rule {
        case let .domain(value, action):
            return RuntimeRoutingRule(kind: .domain, value: value, action: runtimeAction(from: action))
        case let .domainSuffix(value, action):
            return RuntimeRoutingRule(kind: .domainSuffix, value: value, action: runtimeAction(from: action))
        case let .domainKeyword(value, action):
            return RuntimeRoutingRule(kind: .domainKeyword, value: value, action: runtimeAction(from: action))
        case let .ipCIDR(value, action):
            return RuntimeRoutingRule(kind: .ipCIDR, value: value, action: runtimeAction(from: action))
        case let .final(action):
            return RuntimeRoutingRule(kind: .finalRule, value: nil, action: runtimeAction(from: action))
        }
    }

    private static func runtimeAction(from action: RoutingAction) -> RuntimeRoutingAction {
        switch action {
        case .direct:
            return .direct
        case .proxy:
            return .proxy
        case .reject:
            return .reject
        }
    }
}
```

- [ ] **Step 2: Run builder tests**

Run:

```bash
swift test --filter RoutingRuleManifestBuilderTests
```

Expected: PASS with all builder tests passing.

---

### Task 3: Publish rule text from AppViewModel

**Files:**
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`

- [ ] **Step 1: Add failing AppViewModel tests**

Append these tests inside `AppViewModelsTests`:

```swift
    @MainActor
    func testAppViewModelPublishesRoutingRuleManifestFromLocalText() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)
        model.selectNode(id: node.id)
        model.setRoutingRuleText("DOMAIN-SUFFIX,apple.com,DIRECT\nFINAL,PROXY")

        _ = model.publishRuntimeSnapshot()

        XCTAssertEqual(try store.load()?.routingRuleManifest, RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        ))
    }

    @MainActor
    func testAppViewModelPublishesEmptyManifestForCommentOnlyRules() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)
        model.selectNode(id: node.id)
        model.setRoutingRuleText("# no local rules")

        _ = model.publishRuntimeSnapshot()

        XCTAssertEqual(try store.load()?.routingRuleManifest, .empty)
    }

    @MainActor
    func testAppViewModelDoesNotPublishWhenRoutingRulesAreInvalid() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)
        model.selectNode(id: node.id)
        model.setRoutingRuleText("DOMAIN,example.com,DROP")

        let result = model.publishRuntimeSnapshot()

        guard case .storageFailed = result else {
            return XCTFail("Expected storageFailed result")
        }
        XCTAssertNil(try store.load())
        XCTAssertTrue(model.overviewState.recentLogMessages.contains { $0.contains("Routing rules invalid") })
    }
```

- [ ] **Step 2: Run AppViewModel tests to verify failure**

Run:

```bash
swift test --filter AppViewModelsTests
```

Expected: FAIL with compiler error for missing `setRoutingRuleText`.

- [ ] **Step 3: Update AppViewModel**

In `AppViewModel`, add a stored property:

```swift
    private var routingRuleText: String
```

Initialize it in `init`:

```swift
        self.routingRuleText = ""
```

Add setter after `setRouteMode`:

```swift
    public func setRoutingRuleText(_ text: String) {
        routingRuleText = text
    }
```

Replace `publishRuntimeSnapshot()` with:

```swift
    @discardableResult
    public func publishRuntimeSnapshot() -> RuntimeSnapshotPublishResult {
        let logLevel: IrockLogLevel = settingsState.debugLoggingEnabled ? .debug : .user
        let manifest: RuntimeRoutingRuleManifest
        do {
            manifest = try RoutingRuleManifestBuilder.buildManifest(from: routingRuleText)
        } catch {
            appendLog("Routing rules invalid: \(error)")
            return .storageFailed(String(describing: error))
        }

        let result = runtimeSnapshotPublisher.publish(
            selectedNode: overviewState.selectedNode,
            routeMode: overviewState.routeMode,
            logLevel: logLevel,
            routingRuleManifest: manifest
        )

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
```

- [ ] **Step 4: Run AppViewModel tests**

Run:

```bash
swift test --filter AppViewModelsTests
```

Expected: PASS with all AppViewModel tests passing.

---

### Task 4: Refresh project guidance for M9

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README current phase**

Replace the current phase paragraph and bullets in `README.md` with:

```markdown
## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, M2 TUN data path core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, M6 local routing rule parsing foundation, M7 runtime rule manifest foundation, M8 runtime rule adapter foundation, and M9 app routing rule manifest foundation:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing rule manifests, runtime rule adapters, app routing rule manifest publishing, routing/storage behavior, file-backed snapshot persistence, app feature state, runtime snapshot publishing, Shadowsocks URI import, local routing rule parsing, packet parsing, flow tracking, and tunnel runtime processing
- Xcode target creation instructions; Xcode workspace, app targets, and Packet Tunnel targets are not yet committed
```

- [ ] **Step 2: Update README plan list**

Add this line after M8 in the implementation plan list:

```markdown
- M9: `docs/superpowers/plans/2026-05-10-irock-m9-app-routing-rule-manifest.md`
```

- [ ] **Step 3: Update CLAUDE.md project status**

Replace the project status paragraph in `CLAUDE.md` with:

```markdown
## Project status

irock has a SwiftPM package graph, M1 app feature configuration scaffolding, M2 tunnel core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, M6 local routing rule parsing foundation, M7 runtime rule manifest foundation, M8 runtime rule adapter foundation, and M9 app routing rule manifest foundation in the working tree. The committed product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Implementation plans live under `docs/superpowers/plans/`, including M0 engineering foundation, M1 UI configuration, M2 TUN data path, M3 runtime snapshot persistence, M4 runtime snapshot publishing, M5 Shadowsocks URI import, M6 local routing rules, M7 runtime rule manifest, M8 runtime rule adapter, and M9 app routing rule manifest.

There is not yet an Xcode workspace, app target, or Packet Tunnel target in the working tree. Do not assume `xcodebuild` or app schemes exist until Xcode targets are created.
```

- [ ] **Step 4: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

---

## Verification Checklist

After completing all tasks, run:

```bash
git status --short
swift test --filter RoutingRuleManifestBuilderTests
swift test --filter AppViewModelsTests
swift test
```

Expected final state:

- `RoutingRuleManifestBuilder` converts local routing rule text to runtime manifest.
- `AppViewModel` publishes routing rule manifests from local rule text.
- Invalid routing rule text does not overwrite snapshot storage.
- README and CLAUDE.md mention M9 app routing rule manifest.
- All SwiftPM tests pass.
