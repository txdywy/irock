# irock M3 Runtime Snapshot Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a SwiftPM-testable file-backed `RuntimeSnapshotStore` so future app and Packet Tunnel shells can share a frozen runtime snapshot through a directory URL.

**Architecture:** M3 extends `IrockStorage` with `FileRuntimeSnapshotStore`, preserving the existing `RuntimeSnapshotStore` protocol and `InMemoryRuntimeSnapshotStore`. The store writes a single JSON file named `runtime-snapshot.json` inside a caller-provided directory; platform code will later pass an App Group container URL, but this plan does not add platform target or entitlement code.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, Foundation `FileManager`, `JSONEncoder`, `JSONDecoder`, existing `IrockCore.RuntimeSnapshot`.

---

## File Structure

M3 creates and modifies these files:

```text
packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift
packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift
README.md
CLAUDE.md
docs/superpowers/plans/2026-05-10-irock-m3-runtime-snapshot-persistence.md
```

Responsibilities:

- `IrockStorage.swift`: owns the `RuntimeSnapshotStore` protocol, in-memory store, and new file-backed store.
- `IrockStorageTests.swift`: locks file-backed store behavior with temporary-directory tests.
- `README.md`: updates public project status and plan list to include M3.
- `CLAUDE.md`: updates agent guidance so future sessions know M3 exists.

---

### Task 1: Add file-backed runtime snapshot store

**Files:**
- Modify: `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift`
- Modify: `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift`

- [ ] **Step 1: Replace storage tests with failing file store coverage**

Replace `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift` with:

```swift
import XCTest
import IrockCore
@testable import IrockStorage

final class IrockStorageTests: XCTestCase {
    func testSnapshotStoreRoundTripsRuntimeSnapshotInMemory() throws {
        let snapshot = makeSnapshot(id: "snapshot-1", nodeID: "node-1", nodeName: "Demo SS", routeMode: .globalProxy)
        let store = InMemoryRuntimeSnapshotStore()

        XCTAssertNil(try store.load())

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
    }

    func testFileSnapshotStoreRoundTripsRuntimeSnapshot() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        let snapshot = makeSnapshot(id: "snapshot-1", nodeID: "node-1", nodeName: "Demo SS", routeMode: .globalProxy)
        let store = FileRuntimeSnapshotStore(directoryURL: directoryURL)

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
    }

    func testFileSnapshotStoreReturnsNilWhenSnapshotFileIsMissing() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        let store = FileRuntimeSnapshotStore(directoryURL: directoryURL)

        XCTAssertNil(try store.load())
    }

    func testFileSnapshotStoreOverwritesExistingSnapshot() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        let firstSnapshot = makeSnapshot(id: "snapshot-1", nodeID: "node-1", nodeName: "First Node", routeMode: .globalProxy)
        let secondSnapshot = makeSnapshot(id: "snapshot-2", nodeID: "node-2", nodeName: "Second Node", routeMode: .direct)
        let store = FileRuntimeSnapshotStore(directoryURL: directoryURL)

        try store.save(firstSnapshot)
        try store.save(secondSnapshot)

        XCTAssertEqual(try store.load(), secondSnapshot)
    }

    func testFileSnapshotStoreThrowsForCorruptJSON() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("runtime-snapshot.json", isDirectory: false)
        try Data("not-json".utf8).write(to: fileURL)
        let store = FileRuntimeSnapshotStore(directoryURL: directoryURL)

        XCTAssertThrowsError(try store.load())
    }

    func testFileSnapshotStoreCreatesDirectoryWhenSaving() throws {
        let parentURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(parentURL) }
        let directoryURL = parentURL.appendingPathComponent("Snapshots", isDirectory: true)
        let snapshot = makeSnapshot(id: "snapshot-1", nodeID: "node-1", nodeName: "Demo SS", routeMode: .ruleBased)
        let store = FileRuntimeSnapshotStore(directoryURL: directoryURL)

        try store.save(snapshot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.path))
        XCTAssertEqual(try store.load(), snapshot)
    }

    private func makeSnapshot(id: String, nodeID: String, nodeName: String, routeMode: RouteMode) -> RuntimeSnapshot {
        let node = ProxyNode(
            id: NodeID(rawValue: nodeID),
            name: nodeName,
            protocolType: .shadowsocks,
            serverHost: "127.0.0.1",
            serverPort: 8388,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: nodeID),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
        return RuntimeSnapshot(id: SnapshotID(rawValue: id), selectedNode: node, routeMode: routeMode, logLevel: .user)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IrockStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 2: Run storage tests to verify failure**

Run:

```bash
swift test --filter IrockStorageTests
```

Expected: FAIL with compiler errors similar to `cannot find 'FileRuntimeSnapshotStore' in scope`.

- [ ] **Step 3: Implement `FileRuntimeSnapshotStore`**

Replace `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift` with:

```swift
import Foundation
import IrockCore

public protocol RuntimeSnapshotStore {
    func save(_ snapshot: RuntimeSnapshot) throws
    func load() throws -> RuntimeSnapshot?
}

public final class InMemoryRuntimeSnapshotStore: RuntimeSnapshotStore {
    private let lock = NSLock()
    private var snapshot: RuntimeSnapshot?

    public init() {}

    public func save(_ snapshot: RuntimeSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        self.snapshot = snapshot
    }

    public func load() throws -> RuntimeSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

public final class FileRuntimeSnapshotStore: RuntimeSnapshotStore {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var snapshotURL: URL {
        directoryURL.appendingPathComponent("runtime-snapshot.json", isDirectory: false)
    }

    public init(directoryURL: URL, fileManager: FileManager = .default, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    public func save(_ snapshot: RuntimeSnapshot) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
    }

    public func load() throws -> RuntimeSnapshot? {
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: snapshotURL)
        return try decoder.decode(RuntimeSnapshot.self, from: data)
    }
}
```

- [ ] **Step 4: Run storage tests to verify pass**

Run:

```bash
swift test --filter IrockStorageTests
```

Expected: PASS with all `IrockStorageTests` passing.

- [ ] **Step 5: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

- [ ] **Step 6: Commit file-backed store**

Run:

```bash
git add packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift
git commit -m "$(cat <<'EOF'
feat: add file runtime snapshot store

Persist RuntimeSnapshot as JSON in a caller-provided directory so future app and tunnel shells can share frozen runtime configuration without platform dependencies.

Constraint: Keep App Group URL lookup outside IrockStorage
Confidence: high
Scope-risk: narrow
EOF
)"
```

---

### Task 2: Refresh project guidance for M3

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README project status**

Replace lines 4-10 of `README.md` with:

```markdown
## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, M2 TUN data path core, and M3 runtime snapshot persistence foundation:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing/storage behavior, file-backed snapshot persistence, app feature state, packet parsing, flow tracking, and tunnel runtime processing
- Xcode target creation instructions; Xcode workspace, app targets, and Packet Tunnel targets are not yet committed
```

- [ ] **Step 2: Update README plan list**

Replace lines 16-20 of `README.md` with:

```markdown
## Implementation plans

- M0: `docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md`
- M1: `docs/superpowers/plans/2026-05-10-irock-m1-ui-configuration.md`
- M2: `docs/superpowers/plans/2026-05-10-irock-m2-tun-data-path.md`
- M3: `docs/superpowers/plans/2026-05-10-irock-m3-runtime-snapshot-persistence.md`
```

- [ ] **Step 3: Update CLAUDE.md project status**

Replace lines 4-8 of `CLAUDE.md` with:

```markdown
## Project status

irock has a SwiftPM package graph, M1 app feature configuration scaffolding, M2 tunnel core, and M3 runtime snapshot persistence foundation in the working tree. The committed product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Implementation plans live under `docs/superpowers/plans/`, including M0 engineering foundation, M1 UI configuration, M2 TUN data path, and M3 runtime snapshot persistence.

There is not yet an Xcode workspace, app target, or Packet Tunnel target in the working tree. Do not assume `xcodebuild` or app schemes exist until Xcode targets are created.
```

- [ ] **Step 4: Update CLAUDE.md package boundary description**

Replace the `IrockStorage` bullet in `CLAUDE.md` with:

```markdown
- `IrockStorage`: local configuration, file-backed App Group-ready runtime snapshots, credentials, and basic logs.
```

- [ ] **Step 5: Update CLAUDE.md current repository structure description**

Replace line 36 of `CLAUDE.md` with:

```markdown
The working tree currently contains the SwiftPM package graph, including `IrockAppFeature`, `IrockTunnelCore`, and file-backed runtime snapshot persistence in `IrockStorage`, plus fixture and tooling directories:
```

- [ ] **Step 6: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

- [ ] **Step 7: Commit documentation refresh**

Run:

```bash
git add README.md CLAUDE.md docs/superpowers/plans/2026-05-10-irock-m3-runtime-snapshot-persistence.md
git commit -m "$(cat <<'EOF'
docs: refresh project guidance for M3

Document runtime snapshot persistence as the next completed foundation layer so future sessions route work from the current project state.

Constraint: Do not introduce Xcode or App Group setup instructions before targets exist
Confidence: high
Scope-risk: narrow
EOF
)"
```

---

## Verification Checklist

After completing both tasks, run:

```bash
git status --short
swift test
```

Expected final state:

- `git status --short` shows no uncommitted tracked changes.
- `swift test` passes with all SwiftPM tests.
- `IrockStorageTests` includes file-backed coverage for round-trip, missing file, overwrite, corrupt JSON, and directory creation.
- `README.md` and `CLAUDE.md` mention M3 runtime snapshot persistence.
