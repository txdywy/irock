# irock M7 Runtime Rule Manifest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carry a codable runtime routing rule manifest in `RuntimeSnapshot` so app and tunnel layers share the same immutable rule boundary.

**Architecture:** M7 adds core-local runtime routing manifest types to `IrockCore` without depending on `IrockRouting`. `RuntimeSnapshotPublisher` accepts an optional manifest and writes it into snapshots. `TunnelRuntimeConfiguration` exposes the manifest from its snapshot without building a routing engine from it yet.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, Codable runtime models.

---

## File Structure

M7 creates and modifies these files:

```text
packages/IrockCore/Sources/IrockCore/IrockCore.swift
packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift
packages/IrockAppFeature/Sources/IrockAppFeature/RuntimeSnapshotPublisher.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/RuntimeSnapshotPublisherTests.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeConfigurationTests.swift
README.md
CLAUDE.md
docs/superpowers/specs/2026-05-10-irock-m7-runtime-rule-manifest-design.md
docs/superpowers/plans/2026-05-10-irock-m7-runtime-rule-manifest.md
```

Responsibilities:

- `IrockCore.swift`: runtime routing manifest types and `RuntimeSnapshot.routingRuleManifest`.
- `RuntimeSnapshotPublisher.swift`: optional manifest publishing.
- `TunnelRuntimeConfiguration.swift`: read-only manifest access for tunnel runtime setup.
- Tests: lock encoding, publisher propagation, and tunnel configuration access.

---

### Task 1: Add RuntimeSnapshot manifest tests

**Files:**
- Modify: `packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift`

- [ ] **Step 1: Add failing core tests**

Append these tests inside `final class IrockCoreTests`:

```swift
    func testRuntimeSnapshotDefaultsToEmptyRoutingRuleManifest() {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user
        )

        XCTAssertEqual(snapshot.routingRuleManifest, .empty)
    }

    func testRuntimeSnapshotEncodesRoutingRuleManifest() throws {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct),
                RuntimeRoutingRule(kind: .final, value: nil, action: .proxy)
            ]
        )
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )

        let json = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("routingRuleManifest"))
        XCTAssertTrue(json.contains("domainSuffix"))
        XCTAssertTrue(json.contains("apple.com"))
        XCTAssertTrue(json.contains("proxy"))
        XCTAssertFalse(json.contains("password"))
    }
```

If the test file does not already have `makeNode()`, add this helper inside the test class:

```swift
    private func makeNode() -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo",
            protocolType: .shadowsocks,
            serverHost: "example.com",
            serverPort: 8388,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
    }
```

- [ ] **Step 2: Run core tests to verify failure**

Run:

```bash
swift test --filter IrockCoreTests
```

Expected: FAIL with compiler errors for missing `RuntimeRoutingRuleManifest`, `RuntimeRoutingRule`, and `routingRuleManifest`.

---

### Task 2: Implement core runtime routing manifest

**Files:**
- Modify: `packages/IrockCore/Sources/IrockCore/IrockCore.swift`

- [ ] **Step 1: Add manifest types before RuntimeSnapshot**

Insert before `public struct RuntimeSnapshot`:

```swift
public enum RuntimeRoutingAction: String, Codable, Sendable {
    case direct
    case proxy
    case reject
}

public enum RuntimeRoutingRuleKind: String, Codable, Sendable {
    case domain
    case domainSuffix
    case domainKeyword
    case ipCIDR
    case finalRule = "final"
}

public struct RuntimeRoutingRule: Equatable, Codable, Sendable {
    public let kind: RuntimeRoutingRuleKind
    public let value: String?
    public let action: RuntimeRoutingAction

    public init(kind: RuntimeRoutingRuleKind, value: String?, action: RuntimeRoutingAction) {
        self.kind = kind
        self.value = value
        self.action = action
    }
}

public struct RuntimeRoutingRuleManifest: Equatable, Codable, Sendable {
    public static let empty = RuntimeRoutingRuleManifest(version: 1, rules: [])

    public let version: Int
    public let rules: [RuntimeRoutingRule]

    public init(version: Int, rules: [RuntimeRoutingRule]) {
        self.version = version
        self.rules = rules
    }
}
```

- [ ] **Step 2: Update RuntimeSnapshot**

Replace `RuntimeSnapshot` with:

```swift
public struct RuntimeSnapshot: Equatable, Codable, Sendable {
    public let id: SnapshotID
    public let selectedNode: ProxyNode
    public let routeMode: RouteMode
    public let logLevel: IrockLogLevel
    public let routingRuleManifest: RuntimeRoutingRuleManifest

    public init(
        id: SnapshotID,
        selectedNode: ProxyNode,
        routeMode: RouteMode,
        logLevel: IrockLogLevel,
        routingRuleManifest: RuntimeRoutingRuleManifest = .empty
    ) {
        self.id = id
        self.selectedNode = selectedNode
        self.routeMode = routeMode
        self.logLevel = logLevel
        self.routingRuleManifest = routingRuleManifest
    }
}
```

- [ ] **Step 3: Run core tests**

Run:

```bash
swift test --filter IrockCoreTests
```

Expected: PASS with all `IrockCoreTests` passing.

---

### Task 3: Publish manifest from AppFeature

**Files:**
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/RuntimeSnapshotPublisherTests.swift`
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/RuntimeSnapshotPublisher.swift`

- [ ] **Step 1: Add failing publisher tests**

Append these tests inside `RuntimeSnapshotPublisherTests`:

```swift
    func testPublisherSavesRoutingRuleManifest() {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct)]
        )

        _ = publisher.publish(
            selectedNode: makeNode(id: "node-1", name: "Demo"),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )

        XCTAssertEqual(try store.load()?.routingRuleManifest, manifest)
    }

    func testPublisherDefaultsToEmptyRoutingRuleManifest() {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)

        _ = publisher.publish(selectedNode: makeNode(id: "node-1", name: "Demo"), routeMode: .ruleBased, logLevel: .user)

        XCTAssertEqual(try store.load()?.routingRuleManifest, .empty)
    }
```

- [ ] **Step 2: Run publisher tests to verify failure**

Run:

```bash
swift test --filter RuntimeSnapshotPublisherTests
```

Expected: FAIL with compiler error for missing `routingRuleManifest` publish parameter.

- [ ] **Step 3: Update RuntimeSnapshotPublisher**

Replace the `publish` signature and snapshot construction with:

```swift
    public func publish(
        selectedNode: ProxyNode?,
        routeMode: RouteMode,
        logLevel: IrockLogLevel,
        routingRuleManifest: RuntimeRoutingRuleManifest = .empty
    ) -> RuntimeSnapshotPublishResult {
        guard let selectedNode else {
            return .missingSelectedNode
        }

        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-\(UUID().uuidString)"),
            selectedNode: selectedNode,
            routeMode: routeMode,
            logLevel: logLevel,
            routingRuleManifest: routingRuleManifest
        )
```

Keep the existing save/do-catch behavior unchanged.

- [ ] **Step 4: Run publisher tests**

Run:

```bash
swift test --filter RuntimeSnapshotPublisherTests
```

Expected: PASS with all publisher tests passing.

---

### Task 4: Expose manifest in tunnel runtime configuration

**Files:**
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeConfigurationTests.swift`
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift`

- [ ] **Step 1: Add failing tunnel configuration test**

Append this test inside `TunnelRuntimeConfigurationTests`:

```swift
    func testConfigurationExposesRoutingRuleManifest() {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct)]
        )
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )
        let configuration = TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: RoutingEngine(rules: [.final(.reject)]),
            batchLimit: 32,
            flowLimit: 128
        )

        XCTAssertEqual(configuration.routingRuleManifest, manifest)
    }
```

If the test file does not already have `makeNode()`, add the same helper shape used by existing tests in that file.

- [ ] **Step 2: Run tunnel configuration tests to verify failure**

Run:

```bash
swift test --filter TunnelRuntimeConfigurationTests
```

Expected: FAIL with compiler error for missing `routingRuleManifest` property on `TunnelRuntimeConfiguration`.

- [ ] **Step 3: Add configuration property**

In `TunnelRuntimeConfiguration`, add:

```swift
    public var routingRuleManifest: RuntimeRoutingRuleManifest {
        snapshot.routingRuleManifest
    }
```

- [ ] **Step 4: Run tunnel configuration tests**

Run:

```bash
swift test --filter TunnelRuntimeConfigurationTests
```

Expected: PASS with all tunnel configuration tests passing.

---

### Task 5: Refresh project guidance for M7

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README current phase**

Replace the current phase paragraph and bullets in `README.md` with:

```markdown
## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, M2 TUN data path core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, M6 local routing rule parsing foundation, and M7 runtime rule manifest foundation:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing rule manifests, routing/storage behavior, file-backed snapshot persistence, app feature state, runtime snapshot publishing, Shadowsocks URI import, local routing rule parsing, packet parsing, flow tracking, and tunnel runtime processing
- Xcode target creation instructions; Xcode workspace, app targets, and Packet Tunnel targets are not yet committed
```

- [ ] **Step 2: Update README plan list**

Add this line after M6 in the implementation plan list:

```markdown
- M7: `docs/superpowers/plans/2026-05-10-irock-m7-runtime-rule-manifest.md`
```

- [ ] **Step 3: Update CLAUDE.md project status**

Replace the project status paragraph in `CLAUDE.md` with:

```markdown
## Project status

irock has a SwiftPM package graph, M1 app feature configuration scaffolding, M2 tunnel core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, M6 local routing rule parsing foundation, and M7 runtime rule manifest foundation in the working tree. The committed product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Implementation plans live under `docs/superpowers/plans/`, including M0 engineering foundation, M1 UI configuration, M2 TUN data path, M3 runtime snapshot persistence, M4 runtime snapshot publishing, M5 Shadowsocks URI import, M6 local routing rules, and M7 runtime rule manifest.

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
swift test --filter IrockCoreTests
swift test --filter RuntimeSnapshotPublisherTests
swift test --filter TunnelRuntimeConfigurationTests
swift test
```

Expected final state:

- `RuntimeSnapshot` carries a default-empty `routingRuleManifest`.
- Runtime snapshot JSON includes `routingRuleManifest` and still excludes raw credential material.
- `RuntimeSnapshotPublisher` persists supplied manifests and defaults to empty manifest.
- `TunnelRuntimeConfiguration` exposes `routingRuleManifest`.
- `IrockCore` does not import or depend on `IrockRouting`.
- README and CLAUDE.md mention M7 runtime rule manifest.
- All SwiftPM tests pass.
