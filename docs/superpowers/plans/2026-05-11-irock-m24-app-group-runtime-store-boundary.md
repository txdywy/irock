# M24 App Group Runtime Store Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a platform-neutral runtime store bundle and App Group directory convention so future app and tunnel targets can share runtime snapshot, status, and logs through one container directory.

**Architecture:** Add two focused types to `IrockStorage`: `RuntimeStoreBundle` groups existing store protocols, while `AppGroupRuntimeStoreDirectory` derives a deterministic `Runtime` subdirectory from a caller-provided container URL. The implementation composes existing file-backed stores and preserves all existing file formats and error behavior.

**Tech Stack:** SwiftPM, XCTest, Foundation `URL`/`FileManager`, existing `IrockCore` runtime models, existing `IrockStorage` store protocols and file store implementations.

---

## File Structure

- Modify: `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift`
  - Add `RuntimeStoreBundle` after the store protocols.
  - Add `AppGroupRuntimeStoreDirectory` near the file-backed runtime store helpers.
  - Reuse existing `FileRuntimeSnapshotStore`, `FileRuntimeStatusStore`, and `FileRuntimeLogStore`.
- Modify: `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift`
  - Add focused XCTest coverage for deterministic directory derivation, shared file-backed bundles, missing values, log limits, and direct bundle initialization.

---

### Task 1: Runtime Store Bundle Composition

**Files:**
- Modify: `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift`
- Modify: `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift`

- [ ] **Step 1: Write failing tests for direct bundle initialization and file-backed round trip**

Add these tests after `testFileSnapshotStoreCreatesDirectoryWhenSaving()`:

```swift
    func testRuntimeStoreBundlePreservesInjectedStores() throws {
        let snapshotStore = InMemoryRuntimeSnapshotStore()
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore(limit: 2)
        let bundle = RuntimeStoreBundle(snapshotStore: snapshotStore, statusStore: statusStore, logStore: logStore)
        let snapshot = makeSnapshot(id: "snapshot-1", nodeID: "node-1", nodeName: "Demo SS", routeMode: .globalProxy)
        let status = makeStatus(phase: .connected, message: "Connected")
        let log = makeLog(id: "1", message: "connected")

        try bundle.snapshotStore.save(snapshot)
        try bundle.statusStore.save(status)
        try bundle.logStore.append(log)

        XCTAssertEqual(try snapshotStore.load(), snapshot)
        XCTAssertEqual(try statusStore.load(), status)
        XCTAssertEqual(try logStore.loadRecent(), [log])
    }

    func testFileBackedRuntimeStoreBundleRoundTripsRuntimeState() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        let bundle = RuntimeStoreBundle.fileBacked(directoryURL: directoryURL, logLimit: 3)
        let snapshot = makeSnapshot(id: "snapshot-1", nodeID: "node-1", nodeName: "Demo SS", routeMode: .ruleBased)
        let status = makeStatus(phase: .preparing, message: "Preparing")
        let firstLog = makeLog(id: "1", message: "first")
        let secondLog = makeLog(id: "2", message: "second")

        try bundle.snapshotStore.save(snapshot)
        try bundle.statusStore.save(status)
        try bundle.logStore.append(firstLog)
        try bundle.logStore.append(secondLog)

        XCTAssertEqual(try bundle.snapshotStore.load(), snapshot)
        XCTAssertEqual(try bundle.statusStore.load(), status)
        XCTAssertEqual(try bundle.logStore.loadRecent(), [firstLog, secondLog])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter IrockStorageTests/testRuntimeStoreBundlePreservesInjectedStores
swift test --filter IrockStorageTests/testFileBackedRuntimeStoreBundleRoundTripsRuntimeState
```

Expected: both commands fail to compile with `cannot find 'RuntimeStoreBundle' in scope`.

- [ ] **Step 3: Implement `RuntimeStoreBundle`**

Add this code after the `RuntimeLogStore` protocol in `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift`:

```swift
public struct RuntimeStoreBundle: Sendable {
    public let snapshotStore: any RuntimeSnapshotStore
    public let statusStore: any RuntimeStatusStore
    public let logStore: any RuntimeLogStore

    public init(
        snapshotStore: any RuntimeSnapshotStore,
        statusStore: any RuntimeStatusStore,
        logStore: any RuntimeLogStore
    ) {
        self.snapshotStore = snapshotStore
        self.statusStore = statusStore
        self.logStore = logStore
    }

    public static func fileBacked(
        directoryURL: URL,
        logLimit: Int = 200,
        fileManager: FileManager = .default
    ) -> RuntimeStoreBundle {
        RuntimeStoreBundle(
            snapshotStore: FileRuntimeSnapshotStore(directoryURL: directoryURL, fileManager: fileManager),
            statusStore: FileRuntimeStatusStore(directoryURL: directoryURL, fileManager: fileManager),
            logStore: FileRuntimeLogStore(directoryURL: directoryURL, limit: logLimit, fileManager: fileManager)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter IrockStorageTests/testRuntimeStoreBundlePreservesInjectedStores
swift test --filter IrockStorageTests/testFileBackedRuntimeStoreBundleRoundTripsRuntimeState
```

Expected: both commands pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift
git commit -m "feat: add runtime store bundle"
```

---

### Task 2: App Group Runtime Directory Convention

**Files:**
- Modify: `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift`
- Modify: `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift`

- [ ] **Step 1: Write failing tests for directory derivation and shared state**

Add these tests after the Task 1 bundle tests:

```swift
    func testAppGroupRuntimeStoreDirectoryDerivesRuntimeDirectory() throws {
        let containerURL = URL(fileURLWithPath: "/tmp/irock-app-group", isDirectory: true)
        let directory = AppGroupRuntimeStoreDirectory(containerURL: containerURL)

        XCTAssertEqual(directory.runtimeDirectoryURL, containerURL.appendingPathComponent("Runtime", isDirectory: true))
    }

    func testAppGroupRuntimeStoreBundlesShareStateThroughContainerDirectory() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(containerURL) }
        let appDirectory = AppGroupRuntimeStoreDirectory(containerURL: containerURL)
        let tunnelDirectory = AppGroupRuntimeStoreDirectory(containerURL: containerURL)
        let appBundle = appDirectory.makeRuntimeStoreBundle(logLimit: 5)
        let tunnelBundle = tunnelDirectory.makeRuntimeStoreBundle(logLimit: 5)
        let snapshot = makeSnapshot(id: "snapshot-1", nodeID: "node-1", nodeName: "Demo SS", routeMode: .globalProxy)
        let status = makeStatus(phase: .connected, message: "Connected")
        let log = makeLog(id: "1", message: "connected")

        try appBundle.snapshotStore.save(snapshot)
        try tunnelBundle.statusStore.save(status)
        try tunnelBundle.logStore.append(log)

        XCTAssertEqual(try tunnelBundle.snapshotStore.load(), snapshot)
        XCTAssertEqual(try appBundle.statusStore.load(), status)
        XCTAssertEqual(try appBundle.logStore.loadRecent(), [log])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter IrockStorageTests/testAppGroupRuntimeStoreDirectoryDerivesRuntimeDirectory
swift test --filter IrockStorageTests/testAppGroupRuntimeStoreBundlesShareStateThroughContainerDirectory
```

Expected: both commands fail to compile with `cannot find 'AppGroupRuntimeStoreDirectory' in scope`.

- [ ] **Step 3: Implement `AppGroupRuntimeStoreDirectory`**

Add this code after `RuntimeStoreBundle` in `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift`:

```swift
public struct AppGroupRuntimeStoreDirectory: Equatable, Sendable {
    public let containerURL: URL

    public var runtimeDirectoryURL: URL {
        containerURL.appendingPathComponent("Runtime", isDirectory: true)
    }

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    public func makeRuntimeStoreBundle(
        logLimit: Int = 200,
        fileManager: FileManager = .default
    ) -> RuntimeStoreBundle {
        RuntimeStoreBundle.fileBacked(directoryURL: runtimeDirectoryURL, logLimit: logLimit, fileManager: fileManager)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter IrockStorageTests/testAppGroupRuntimeStoreDirectoryDerivesRuntimeDirectory
swift test --filter IrockStorageTests/testAppGroupRuntimeStoreBundlesShareStateThroughContainerDirectory
```

Expected: both commands pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift
git commit -m "feat: add app group runtime store directory"
```

---

### Task 3: Missing Values and Log Limit Coverage

**Files:**
- Modify: `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift`

- [ ] **Step 1: Write tests for missing values and log limit through bundle APIs**

Add these tests after the Task 2 tests:

```swift
    func testAppGroupRuntimeStoreBundleReturnsEmptyStateWhenFilesAreMissing() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(containerURL) }
        let bundle = AppGroupRuntimeStoreDirectory(containerURL: containerURL).makeRuntimeStoreBundle()

        XCTAssertNil(try bundle.snapshotStore.load())
        XCTAssertNil(try bundle.statusStore.load())
        XCTAssertEqual(try bundle.logStore.loadRecent(), [])
    }

    func testAppGroupRuntimeStoreBundleRespectsLogLimit() throws {
        let containerURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(containerURL) }
        let bundle = AppGroupRuntimeStoreDirectory(containerURL: containerURL).makeRuntimeStoreBundle(logLimit: 2)

        try bundle.logStore.append(makeLog(id: "1", message: "first"))
        try bundle.logStore.append(makeLog(id: "2", message: "second"))
        try bundle.logStore.append(makeLog(id: "3", message: "third"))

        XCTAssertEqual(try bundle.logStore.loadRecent().map(\.message), ["second", "third"])
    }
```

- [ ] **Step 2: Run tests to verify they pass with existing implementation**

Run:

```bash
swift test --filter IrockStorageTests/testAppGroupRuntimeStoreBundleReturnsEmptyStateWhenFilesAreMissing
swift test --filter IrockStorageTests/testAppGroupRuntimeStoreBundleRespectsLogLimit
```

Expected: both commands pass. These tests cover behavior provided by the new composition plus existing file stores.

- [ ] **Step 3: Commit Task 3**

```bash
git add packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift
git commit -m "test: cover app group runtime store bundle behavior"
```

---

### Task 4: Full Verification and Shipping Prep

**Files:**
- No source changes expected unless verification reveals issues.

- [ ] **Step 1: Run focused storage tests**

Run:

```bash
swift test --filter IrockStorageTests
```

Expected: all `IrockStorageTests` pass.

- [ ] **Step 2: Run full test suite**

Run:

```bash
swift test
```

Expected: all SwiftPM tests pass.

- [ ] **Step 3: Run forbidden import scan**

Run:

```bash
grep -R "import Network\|import Security\|import NetworkExtension\|import UIKit\|import AppKit" -n packages/IrockStorage packages/IrockTunnelCore packages/IrockProtocols packages/IrockTransport Package.swift || true
```

Expected: no output.

- [ ] **Step 4: Scan plan for placeholders and command typos**

Run:

```bash
grep -nE '[T]BD|[T]ODO|[i]mplement later|[f]ill in|n[g]rep' docs/superpowers/plans/2026-05-11-irock-m24-app-group-runtime-store-boundary.md || true
```

Expected: no output.

- [ ] **Step 5: Commit plan if not already committed**

```bash
git add docs/superpowers/plans/2026-05-11-irock-m24-app-group-runtime-store-boundary.md
git commit -m "docs: add M24 app group runtime store boundary plan"
```

- [ ] **Step 6: Prepare branch for review/PR**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean working tree and commits for M24 design, plan, implementation, and tests.
