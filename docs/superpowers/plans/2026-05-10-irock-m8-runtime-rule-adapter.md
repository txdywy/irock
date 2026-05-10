# irock M8 Runtime Rule Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `RuntimeRoutingRuleManifest` into `IrockRouting.RoutingRule` values and let tunnel configuration build a routing engine from snapshot rules.

**Architecture:** M8 adds the adapter in `IrockTunnelCore`, the package that already depends on both `IrockCore` and `IrockRouting`. `IrockCore` remains dependency-free, `IrockRouting` remains runtime-model agnostic, and `TunnelRuntimeConfiguration` gains a convenience initializer that builds `RoutingEngine` from the snapshot manifest.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest.

---

## File Structure

M8 creates and modifies these files:

```text
packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeRoutingRuleAdapter.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeRoutingRuleAdapterTests.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeConfigurationTests.swift
README.md
CLAUDE.md
docs/superpowers/specs/2026-05-10-irock-m8-runtime-rule-adapter-design.md
docs/superpowers/plans/2026-05-10-irock-m8-runtime-rule-adapter.md
```

Responsibilities:

- `RuntimeRoutingRuleAdapter.swift`: convert core runtime manifest rules into `IrockRouting.RoutingRule` values.
- `TunnelRuntimeConfiguration.swift`: add convenience initializer from snapshot manifest.
- Tests: adapter conversion, missing values, and tunnel configuration integration.

---

### Task 1: Add adapter tests

**Files:**
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeRoutingRuleAdapterTests.swift`

- [ ] **Step 1: Create failing adapter tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/RuntimeRoutingRuleAdapterTests.swift`:

```swift
import XCTest
import IrockCore
import IrockRouting
@testable import IrockTunnelCore

final class RuntimeRoutingRuleAdapterTests: XCTestCase {
    func testAdapterConvertsSupportedRuleKinds() throws {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domain, value: "example.com", action: .direct),
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .proxy),
                RuntimeRoutingRule(kind: .domainKeyword, value: "google", action: .reject),
                RuntimeRoutingRule(kind: .ipCIDR, value: "10.0.0.0/8", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        )

        let rules = try RuntimeRoutingRuleAdapter.routingRules(from: manifest)

        XCTAssertEqual(rules, [
            .domain("example.com", .direct),
            .domainSuffix("apple.com", .proxy),
            .domainKeyword("google", .reject),
            .ipCIDR("10.0.0.0/8", .direct),
            .final(.proxy)
        ])
    }

    func testAdapterRejectsMissingValueForNonFinalRule() {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: nil, action: .direct)]
        )

        XCTAssertThrowsError(try RuntimeRoutingRuleAdapter.routingRules(from: manifest)) { error in
            XCTAssertEqual(error as? RuntimeRoutingRuleAdapterError, .missingValue(kind: .domainSuffix))
        }
    }

    func testAdapterRejectsEmptyValueForNonFinalRule() {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domain, value: "", action: .direct)]
        )

        XCTAssertThrowsError(try RuntimeRoutingRuleAdapter.routingRules(from: manifest)) { error in
            XCTAssertEqual(error as? RuntimeRoutingRuleAdapterError, .missingValue(kind: .domain))
        }
    }
}
```

- [ ] **Step 2: Run adapter tests to verify failure**

Run:

```bash
swift test --filter RuntimeRoutingRuleAdapterTests
```

Expected: FAIL with compiler errors for missing `RuntimeRoutingRuleAdapter` and `RuntimeRoutingRuleAdapterError`.

---

### Task 2: Implement RuntimeRoutingRuleAdapter

**Files:**
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeRoutingRuleAdapter.swift`

- [ ] **Step 1: Create adapter implementation**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/RuntimeRoutingRuleAdapter.swift`:

```swift
import IrockCore
import IrockRouting

public enum RuntimeRoutingRuleAdapterError: Error, Equatable, Sendable {
    case missingValue(kind: RuntimeRoutingRuleKind)
}

public enum RuntimeRoutingRuleAdapter {
    public static func routingRules(from manifest: RuntimeRoutingRuleManifest) throws -> [RoutingRule] {
        try manifest.rules.map(routingRule(from:))
    }

    private static func routingRule(from rule: RuntimeRoutingRule) throws -> RoutingRule {
        let action = routingAction(from: rule.action)

        switch rule.kind {
        case .domain:
            return .domain(try requiredValue(from: rule), action)
        case .domainSuffix:
            return .domainSuffix(try requiredValue(from: rule), action)
        case .domainKeyword:
            return .domainKeyword(try requiredValue(from: rule), action)
        case .ipCIDR:
            return .ipCIDR(try requiredValue(from: rule), action)
        case .finalRule:
            return .final(action)
        }
    }

    private static func routingAction(from action: RuntimeRoutingAction) -> RoutingAction {
        switch action {
        case .direct:
            return .direct
        case .proxy:
            return .proxy
        case .reject:
            return .reject
        }
    }

    private static func requiredValue(from rule: RuntimeRoutingRule) throws -> String {
        guard let value = rule.value, !value.isEmpty else {
            throw RuntimeRoutingRuleAdapterError.missingValue(kind: rule.kind)
        }
        return value
    }
}
```

- [ ] **Step 2: Run adapter tests**

Run:

```bash
swift test --filter RuntimeRoutingRuleAdapterTests
```

Expected: PASS with all adapter tests passing.

---

### Task 3: Build routing engine from snapshot manifest

**Files:**
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeConfigurationTests.swift`
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeConfiguration.swift`

- [ ] **Step 1: Add failing configuration tests**

Append these tests inside `TunnelRuntimeConfigurationTests`:

```swift
    func testConfigurationBuildsRoutingEngineFromSnapshotManifest() {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        )
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )
        let configuration = try TunnelRuntimeConfiguration(snapshot: snapshot, batchLimit: 32, flowLimit: 128)

        let decision = configuration.routingEngine.resolve(RoutingContext(host: "developer.apple.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }

    func testConfigurationBuiltFromEmptyManifestUsesRejectDefault() throws {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user
        )
        let configuration = try TunnelRuntimeConfiguration(snapshot: snapshot, batchLimit: 32, flowLimit: 128)

        let decision = configuration.routingEngine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .reject)
        XCTAssertNil(decision.matchedRule)
    }
```

- [ ] **Step 2: Run configuration tests to verify failure**

Run:

```bash
swift test --filter TunnelRuntimeConfigurationTests
```

Expected: FAIL with compiler errors for missing throwing convenience initializer.

- [ ] **Step 3: Add convenience initializer**

In `TunnelRuntimeConfiguration`, add below the existing initializer:

```swift
    public init(snapshot: RuntimeSnapshot, batchLimit: Int, flowLimit: Int) throws {
        let rules = try RuntimeRoutingRuleAdapter.routingRules(from: snapshot.routingRuleManifest)
        self.init(
            snapshot: snapshot,
            routingEngine: RoutingEngine(rules: rules),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
```

- [ ] **Step 4: Run configuration tests**

Run:

```bash
swift test --filter TunnelRuntimeConfigurationTests
```

Expected: PASS with all configuration tests passing.

---

### Task 4: Refresh project guidance for M8

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README current phase**

Replace the current phase paragraph and bullets in `README.md` with:

```markdown
## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, M2 TUN data path core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, M6 local routing rule parsing foundation, M7 runtime rule manifest foundation, and M8 runtime rule adapter foundation:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing rule manifests, runtime rule adapters, routing/storage behavior, file-backed snapshot persistence, app feature state, runtime snapshot publishing, Shadowsocks URI import, local routing rule parsing, packet parsing, flow tracking, and tunnel runtime processing
- Xcode target creation instructions; Xcode workspace, app targets, and Packet Tunnel targets are not yet committed
```

- [ ] **Step 2: Update README plan list**

Add this line after M7 in the implementation plan list:

```markdown
- M8: `docs/superpowers/plans/2026-05-10-irock-m8-runtime-rule-adapter.md`
```

- [ ] **Step 3: Update CLAUDE.md project status**

Replace the project status paragraph in `CLAUDE.md` with:

```markdown
## Project status

irock has a SwiftPM package graph, M1 app feature configuration scaffolding, M2 tunnel core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, M6 local routing rule parsing foundation, M7 runtime rule manifest foundation, and M8 runtime rule adapter foundation in the working tree. The committed product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Implementation plans live under `docs/superpowers/plans/`, including M0 engineering foundation, M1 UI configuration, M2 TUN data path, M3 runtime snapshot persistence, M4 runtime snapshot publishing, M5 Shadowsocks URI import, M6 local routing rules, M7 runtime rule manifest, and M8 runtime rule adapter.

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
swift test --filter RuntimeRoutingRuleAdapterTests
swift test --filter TunnelRuntimeConfigurationTests
swift test
```

Expected final state:

- `RuntimeRoutingRuleAdapter.routingRules(from:)` converts runtime manifest rules to routing rules.
- Missing non-final values return `RuntimeRoutingRuleAdapterError.missingValue`.
- `TunnelRuntimeConfiguration(snapshot:batchLimit:flowLimit:)` builds routing engine from snapshot manifest.
- Empty manifest produces routing engine default reject behavior.
- Existing explicit routing engine initializer still works.
- README and CLAUDE.md mention M8 runtime rule adapter.
- All SwiftPM tests pass.
