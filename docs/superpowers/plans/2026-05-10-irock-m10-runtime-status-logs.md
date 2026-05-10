# irock M10 Runtime Status and Logs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the shared runtime feedback boundary so TunnelCore can publish connection status/logs and AppFeature can read them.

**Architecture:** M10 adds durable status/log models in `IrockCore`, store protocols plus in-memory/file-backed implementations in `IrockStorage`, a narrow `TunnelRuntimeReporter` in `IrockTunnelCore`, and an app-facing refresh path in `AppViewModel`. The data flow remains one-way across package boundaries: Core models are shared, Storage persists, TunnelCore writes runtime feedback, and AppFeature reads it.

**Tech Stack:** Swift 5.10+ package targets, Foundation `Date`/`JSONEncoder`/`JSONDecoder`, `NSLock`, XCTest async tests, existing `IrockCore`, `IrockStorage`, `IrockTunnelCore`, and `IrockAppFeature` packages.

---

## File Structure

M10 creates and modifies these files:

```text
packages/IrockCore/Sources/IrockCore/IrockCore.swift
packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift
packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift
packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeReporter.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeReporterTests.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift
packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
```

Responsibilities:

- `IrockCore.swift`: defines codable/sendable runtime status and log value types.
- `IrockStorage.swift`: defines status/log store protocols and in-memory/file-backed implementations.
- `TunnelRuntimeReporter.swift`: gives TunnelCore a narrow status/log publishing facade over storage protocols.
- `PacketTunnelRuntime.swift`: publishes lifecycle status/logs around batch processing.
- `AppViewModels.swift`: reads runtime feedback into app-facing state without knowing tunnel internals.

---

### Task 1: Add runtime feedback models in IrockCore

**Files:**
- Modify: `packages/IrockCore/Sources/IrockCore/IrockCore.swift`
- Modify: `packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift`

- [ ] **Step 1: Add failing model tests**

Append these tests inside `IrockCoreTests` before `private func makeNode()`:

```swift
    func testRuntimeConnectionStatusCodableRoundTrips() throws {
        let status = RuntimeConnectionStatus(
            phase: .connected,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo Node",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_000),
            message: "Connected"
        )

        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeConnectionStatus.self, from: data)

        XCTAssertEqual(decoded, status)
    }

    func testRuntimeConnectionStatusDisconnectedDefault() {
        let status = RuntimeConnectionStatus.disconnected(updatedAt: Date(timeIntervalSince1970: 1_715_000_001))

        XCTAssertEqual(status.phase, .disconnected)
        XCTAssertNil(status.selectedNodeID)
        XCTAssertNil(status.selectedNodeName)
        XCTAssertEqual(status.updatedAt, Date(timeIntervalSince1970: 1_715_000_001))
        XCTAssertNil(status.message)
    }

    func testRuntimeLogEntryCodableRoundTrips() throws {
        let entry = RuntimeLogEntry(
            id: "log-1",
            timestamp: Date(timeIntervalSince1970: 1_715_000_002),
            level: .user,
            message: "Tunnel connected",
            nodeID: NodeID(rawValue: "node-1"),
            phase: .connected
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(RuntimeLogEntry.self, from: data)

        XCTAssertEqual(decoded, entry)
    }
```

- [ ] **Step 2: Run model tests to verify failure**

Run:

```bash
swift test --filter 'IrockCoreTests/testRuntimeConnectionStatusCodableRoundTrips'
```

Expected: FAIL with compiler errors for missing `RuntimeConnectionStatus` and `RuntimeLogEntry`.

- [ ] **Step 3: Implement runtime feedback models**

Insert this code in `packages/IrockCore/Sources/IrockCore/IrockCore.swift` after `IrockLogLevel` and before `RuntimeRoutingAction`:

```swift
public enum RuntimeConnectionPhase: String, Codable, Sendable {
    case disconnected
    case preparing
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case failed
}

public struct RuntimeConnectionStatus: Equatable, Codable, Sendable {
    public let phase: RuntimeConnectionPhase
    public let selectedNodeID: NodeID?
    public let selectedNodeName: String?
    public let updatedAt: Date
    public let message: String?

    public static func disconnected(updatedAt: Date = Date()) -> RuntimeConnectionStatus {
        RuntimeConnectionStatus(
            phase: .disconnected,
            selectedNodeID: nil,
            selectedNodeName: nil,
            updatedAt: updatedAt,
            message: nil
        )
    }

    public init(phase: RuntimeConnectionPhase, selectedNodeID: NodeID?, selectedNodeName: String?, updatedAt: Date = Date(), message: String?) {
        self.phase = phase
        self.selectedNodeID = selectedNodeID
        self.selectedNodeName = selectedNodeName
        self.updatedAt = updatedAt
        self.message = message
    }
}

public enum RuntimeLogLevel: String, Codable, Sendable {
    case user
    case debug
}

public struct RuntimeLogEntry: Equatable, Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let level: RuntimeLogLevel
    public let message: String
    public let nodeID: NodeID?
    public let phase: RuntimeConnectionPhase?

    public init(id: String, timestamp: Date = Date(), level: RuntimeLogLevel, message: String, nodeID: NodeID?, phase: RuntimeConnectionPhase?) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.nodeID = nodeID
        self.phase = phase
    }
}
```

Because this file currently has no `Foundation` import, add this at the top:

```swift
import Foundation
```

- [ ] **Step 4: Run core tests**

Run:

```bash
swift test --filter IrockCoreTests
```

Expected: PASS with all core tests passing.

- [ ] **Step 5: Commit core models**

```bash
git add packages/IrockCore/Sources/IrockCore/IrockCore.swift packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift
git commit -m "feat: add runtime feedback models"
```

---

### Task 2: Add runtime status and log stores in IrockStorage

**Files:**
- Modify: `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift`
- Modify: `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift`

- [ ] **Step 1: Add failing storage tests**

Append these tests inside `IrockStorageTests` before `private func makeSnapshot(...)`:

```swift
    func testInMemoryRuntimeStatusStoreRoundTripsStatus() throws {
        let store = InMemoryRuntimeStatusStore()
        let status = makeStatus(phase: .connected, message: "Connected")

        XCTAssertNil(try store.load())

        try store.save(status)

        XCTAssertEqual(try store.load(), status)
    }

    func testFileRuntimeStatusStoreRoundTripsStatus() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        let store = FileRuntimeStatusStore(directoryURL: directoryURL)
        let status = makeStatus(phase: .preparing, message: "Preparing")

        try store.save(status)

        XCTAssertEqual(try store.load(), status)
    }

    func testFileRuntimeStatusStoreReturnsNilWhenMissing() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        let store = FileRuntimeStatusStore(directoryURL: directoryURL)

        XCTAssertNil(try store.load())
    }

    func testFileRuntimeStatusStoreThrowsForCorruptJSON() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directoryURL.appendingPathComponent("runtime-status.json", isDirectory: false))
        let store = FileRuntimeStatusStore(directoryURL: directoryURL)

        XCTAssertThrowsError(try store.load())
    }

    func testInMemoryRuntimeLogStoreKeepsNewestEntries() throws {
        let store = InMemoryRuntimeLogStore(limit: 2)
        try store.append(makeLog(id: "1", message: "first"))
        try store.append(makeLog(id: "2", message: "second"))
        try store.append(makeLog(id: "3", message: "third"))

        XCTAssertEqual(try store.loadRecent().map(\.message), ["second", "third"])
    }

    func testFileRuntimeLogStoreRoundTripsAndClearsLogs() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        let store = FileRuntimeLogStore(directoryURL: directoryURL, limit: 3)
        let first = makeLog(id: "1", message: "first")
        let second = makeLog(id: "2", message: "second")

        try store.append(first)
        try store.append(second)

        XCTAssertEqual(try store.loadRecent(), [first, second])

        try store.clear()

        XCTAssertEqual(try store.loadRecent(), [])
    }

    func testFileRuntimeLogStoreKeepsNewestEntries() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        let store = FileRuntimeLogStore(directoryURL: directoryURL, limit: 2)
        try store.append(makeLog(id: "1", message: "first"))
        try store.append(makeLog(id: "2", message: "second"))
        try store.append(makeLog(id: "3", message: "third"))

        XCTAssertEqual(try store.loadRecent().map(\.message), ["second", "third"])
    }

    func testFileRuntimeLogStoreThrowsForCorruptJSON() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directoryURL.appendingPathComponent("runtime-logs.json", isDirectory: false))
        let store = FileRuntimeLogStore(directoryURL: directoryURL)

        XCTAssertThrowsError(try store.loadRecent())
    }
```

Add these helpers before `makeTemporaryDirectory()`:

```swift
    private func makeStatus(phase: RuntimeConnectionPhase, message: String?) -> RuntimeConnectionStatus {
        RuntimeConnectionStatus(
            phase: phase,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo SS",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_010),
            message: message
        )
    }

    private func makeLog(id: String, message: String) -> RuntimeLogEntry {
        RuntimeLogEntry(
            id: id,
            timestamp: Date(timeIntervalSince1970: 1_715_000_011),
            level: .user,
            message: message,
            nodeID: NodeID(rawValue: "node-1"),
            phase: .connected
        )
    }
```

- [ ] **Step 2: Run storage tests to verify failure**

Run:

```bash
swift test --filter IrockStorageTests
```

Expected: FAIL with compiler errors for missing `RuntimeStatusStore`, `InMemoryRuntimeStatusStore`, `FileRuntimeStatusStore`, `RuntimeLogStore`, `InMemoryRuntimeLogStore`, and `FileRuntimeLogStore`.

- [ ] **Step 3: Implement status and log stores**

Append this code to `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift` after `FileRuntimeSnapshotStore`:

```swift
public protocol RuntimeStatusStore: Sendable {
    func save(_ status: RuntimeConnectionStatus) throws
    func load() throws -> RuntimeConnectionStatus?
}

public protocol RuntimeLogStore: Sendable {
    func append(_ entry: RuntimeLogEntry) throws
    func loadRecent() throws -> [RuntimeLogEntry]
    func clear() throws
}

public final class InMemoryRuntimeStatusStore: RuntimeStatusStore, @unchecked Sendable {
    private let lock = NSLock()
    private var status: RuntimeConnectionStatus?

    public init() {}

    public func save(_ status: RuntimeConnectionStatus) throws {
        lock.lock()
        defer { lock.unlock() }
        self.status = status
    }

    public func load() throws -> RuntimeConnectionStatus? {
        lock.lock()
        defer { lock.unlock() }
        return status
    }
}

public final class InMemoryRuntimeLogStore: RuntimeLogStore, @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var entries: [RuntimeLogEntry]

    public init(limit: Int = 200) {
        self.limit = max(0, limit)
        self.entries = []
    }

    public func append(_ entry: RuntimeLogEntry) throws {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    public func loadRecent() throws -> [RuntimeLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

public final class FileRuntimeStatusStore: RuntimeStatusStore, @unchecked Sendable {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var statusURL: URL {
        directoryURL.appendingPathComponent("runtime-status.json", isDirectory: false)
    }

    public init(directoryURL: URL, fileManager: FileManager = .default, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    public func save(_ status: RuntimeConnectionStatus) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(status)
        try data.write(to: statusURL, options: .atomic)
    }

    public func load() throws -> RuntimeConnectionStatus? {
        guard fileManager.fileExists(atPath: statusURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: statusURL)
        return try decoder.decode(RuntimeConnectionStatus.self, from: data)
    }
}

public final class FileRuntimeLogStore: RuntimeLogStore, @unchecked Sendable {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let limit: Int

    private var logsURL: URL {
        directoryURL.appendingPathComponent("runtime-logs.json", isDirectory: false)
    }

    public init(directoryURL: URL, limit: Int = 200, fileManager: FileManager = .default, encoder: JSONEncoder = JSONEncoder(), decoder: JSONDecoder = JSONDecoder()) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.limit = max(0, limit)
    }

    public func append(_ entry: RuntimeLogEntry) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var entries = try loadRecent()
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        let data = try encoder.encode(entries)
        try data.write(to: logsURL, options: .atomic)
    }

    public func loadRecent() throws -> [RuntimeLogEntry] {
        guard fileManager.fileExists(atPath: logsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: logsURL)
        return try decoder.decode([RuntimeLogEntry].self, from: data)
    }

    public func clear() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode([RuntimeLogEntry]())
        try data.write(to: logsURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run storage tests**

Run:

```bash
swift test --filter IrockStorageTests
```

Expected: PASS with all storage tests passing.

- [ ] **Step 5: Commit storage stores**

```bash
git add packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift
git commit -m "feat: store runtime status and logs"
```

---

### Task 3: Add TunnelRuntimeReporter

**Files:**
- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeReporter.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeReporterTests.swift`

- [ ] **Step 1: Add failing reporter tests**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeReporterTests.swift`:

```swift
import XCTest
import IrockCore
import IrockStorage
@testable import IrockTunnelCore

final class TunnelRuntimeReporterTests: XCTestCase {
    func testReporterPublishesStatus() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let status = RuntimeConnectionStatus(
            phase: .connected,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_020),
            message: "Connected"
        )

        try reporter.publishStatus(status)

        XCTAssertEqual(try statusStore.load(), status)
    }

    func testReporterAppendsLogEntry() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let entry = RuntimeLogEntry(
            id: "log-1",
            timestamp: Date(timeIntervalSince1970: 1_715_000_021),
            level: .user,
            message: "Connected",
            nodeID: NodeID(rawValue: "node-1"),
            phase: .connected
        )

        try reporter.appendLog(entry)

        XCTAssertEqual(try logStore.loadRecent(), [entry])
    }
}
```

- [ ] **Step 2: Run reporter tests to verify failure**

Run:

```bash
swift test --filter TunnelRuntimeReporterTests
```

Expected: FAIL with compiler error for missing `TunnelRuntimeReporter`.

- [ ] **Step 3: Implement TunnelRuntimeReporter**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeReporter.swift`:

```swift
import IrockCore
import IrockStorage

public struct TunnelRuntimeReporter: Sendable {
    private let statusStore: RuntimeStatusStore
    private let logStore: RuntimeLogStore

    public init(statusStore: RuntimeStatusStore, logStore: RuntimeLogStore) {
        self.statusStore = statusStore
        self.logStore = logStore
    }

    public func publishStatus(_ status: RuntimeConnectionStatus) throws {
        try statusStore.save(status)
    }

    public func appendLog(_ entry: RuntimeLogEntry) throws {
        try logStore.append(entry)
    }
}
```

- [ ] **Step 4: Run reporter tests**

Run:

```bash
swift test --filter TunnelRuntimeReporterTests
```

Expected: PASS with 2 tests passing.

- [ ] **Step 5: Commit reporter**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeReporter.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeReporterTests.swift
git commit -m "feat: add tunnel runtime reporter"
```

---

### Task 4: Publish status from PacketTunnelRuntime

**Files:**
- Modify: `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift`
- Modify: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift`

- [ ] **Step 1: Add failing runtime status test**

Add `import IrockStorage` to `PacketTunnelRuntimeTests.swift`.

Append this test inside `PacketTunnelRuntimeTests`:

```swift
    func testRuntimePublishesPreparingAndConnectedStatus() async throws {
        let validPacket = Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)
        let reader = InMemoryPacketReader(packets: [validPacket])
        let writer = InMemoryPacketWriter()
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let runtime = PacketTunnelRuntime(
            reader: reader,
            writer: writer,
            configuration: TunnelRuntimeConfiguration(snapshot: snapshot(routeMode: .globalProxy), routingEngine: RoutingEngine(rules: [.final(.proxy)]), batchLimit: 16, flowLimit: 32),
            reporter: reporter
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        let status = try XCTUnwrap(statusStore.load())
        XCTAssertEqual(status.phase, .connected)
        XCTAssertEqual(status.selectedNodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(status.selectedNodeName, "Demo")
        XCTAssertEqual(status.message, "Packet batch processed")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
    }
```

- [ ] **Step 2: Run runtime tests to verify failure**

Run:

```bash
swift test --filter 'PacketTunnelRuntimeTests/testRuntimePublishesPreparingAndConnectedStatus'
```

Expected: FAIL with compiler error because `PacketTunnelRuntime` does not accept `reporter:` yet.

- [ ] **Step 3: Implement reporter integration**

Replace `PacketTunnelRuntime` in `packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift` with:

```swift
import Foundation
import IrockCore

public protocol PacketReader: Sendable {
    func readBatch() async throws -> [Packet]
}

public protocol PacketWriter: Sendable {
    func write(_ results: [PacketProcessingResult]) async throws
}

public struct PacketTunnelRuntimeSummary: Equatable, Sendable {
    public let readCount: Int
    public let writtenCount: Int
    public let dropCount: Int

    public init(readCount: Int, writtenCount: Int, dropCount: Int) {
        self.readCount = readCount
        self.writtenCount = writtenCount
        self.dropCount = dropCount
    }
}

public struct PacketTunnelRuntime<Reader: PacketReader, Writer: PacketWriter>: Sendable {
    private let reader: Reader
    private let writer: Writer
    private let configuration: TunnelRuntimeConfiguration
    private let reporter: TunnelRuntimeReporter?

    public init(reader: Reader, writer: Writer, configuration: TunnelRuntimeConfiguration, reporter: TunnelRuntimeReporter? = nil) {
        self.reader = reader
        self.writer = writer
        self.configuration = configuration
        self.reporter = reporter
    }

    public func runOnce() async throws -> PacketTunnelRuntimeSummary {
        try publish(.preparing, message: "Preparing packet batch")
        try appendLog(message: "Tunnel runtime preparing", phase: .preparing)

        let packets = try await reader.readBatch()
        var processor = PacketProcessor(configuration: configuration)
        let results = processor.process(packets)

        try await writer.write(results)

        try publish(.connected, message: "Packet batch processed")
        try appendLog(message: "Tunnel runtime connected", phase: .connected)

        return PacketTunnelRuntimeSummary(
            readCount: packets.count,
            writtenCount: results.count,
            dropCount: results.filter { result in
                if case .drop = result.action {
                    return true
                }
                return false
            }.count
        )
    }

    private func publish(_ phase: RuntimeConnectionPhase, message: String) throws {
        try reporter?.publishStatus(RuntimeConnectionStatus(
            phase: phase,
            selectedNodeID: configuration.snapshot.selectedNode.id,
            selectedNodeName: configuration.snapshot.selectedNode.name,
            updatedAt: Date(),
            message: message
        ))
    }

    private func appendLog(message: String, phase: RuntimeConnectionPhase) throws {
        try reporter?.appendLog(RuntimeLogEntry(
            id: "log-\(UUID().uuidString)",
            timestamp: Date(),
            level: .user,
            message: message,
            nodeID: configuration.snapshot.selectedNode.id,
            phase: phase
        ))
    }
}
```

- [ ] **Step 4: Run runtime tests**

Run:

```bash
swift test --filter PacketTunnelRuntimeTests
```

Expected: PASS with existing and new runtime tests passing.

- [ ] **Step 5: Commit runtime status integration**

```bash
git add packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift
git commit -m "feat: publish tunnel runtime status"
```

---

### Task 5: Add app-facing runtime feedback refresh

**Files:**
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`

- [ ] **Step 1: Add failing app refresh tests**

Append these tests inside `AppViewModelsTests` before `private func makeNode(...)`:

```swift
    @MainActor
    func testAppViewModelRefreshesRuntimeFeedback() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let status = RuntimeConnectionStatus(
            phase: .connected,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_030),
            message: "Connected"
        )
        let log = RuntimeLogEntry(
            id: "log-1",
            timestamp: Date(timeIntervalSince1970: 1_715_000_031),
            level: .user,
            message: "Tunnel runtime connected",
            nodeID: NodeID(rawValue: "node-1"),
            phase: .connected
        )
        try statusStore.save(status)
        try logStore.append(log)
        let model = AppViewModel(nodes: [], runtimeStatusStore: statusStore, runtimeLogStore: logStore)

        let result = model.refreshRuntimeFeedback()

        XCTAssertEqual(result, .refreshed)
        XCTAssertEqual(model.runtimeConnectionStatus, status)
        XCTAssertEqual(model.runtimeLogs, [log])
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
        XCTAssertEqual(model.overviewState.recentLogMessages, ["Tunnel runtime connected"])
    }

    @MainActor
    func testAppViewModelRefreshUsesDisconnectedWhenStatusIsMissing() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let model = AppViewModel(nodes: [], runtimeStatusStore: statusStore, runtimeLogStore: logStore)

        let result = model.refreshRuntimeFeedback()

        XCTAssertEqual(result, .refreshed)
        XCTAssertEqual(model.runtimeConnectionStatus?.phase, .disconnected)
        XCTAssertEqual(model.overviewState.connectionStatus, .disconnected)
    }
```

- [ ] **Step 2: Run app tests to verify failure**

Run:

```bash
swift test --filter 'AppViewModelsTests/testAppViewModelRefreshesRuntimeFeedback'
```

Expected: FAIL with compiler errors for missing `runtimeStatusStore`, `runtimeLogStore`, `refreshRuntimeFeedback`, `runtimeConnectionStatus`, `runtimeLogs`, and `RuntimeFeedbackRefreshResult`.

- [ ] **Step 3: Implement app refresh state**

In `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`, insert this enum above `AppViewModel`:

```swift
public enum RuntimeFeedbackRefreshResult: Equatable, Sendable {
    case refreshed
    case statusLoadFailed(String)
    case logLoadFailed(String)
}
```

Update `AppViewModel` properties and initializer to include runtime feedback stores and state:

```swift
    @Published public private(set) var runtimeConnectionStatus: RuntimeConnectionStatus?
    @Published public private(set) var runtimeLogs: [RuntimeLogEntry]

    private let logLimit: Int
    private let runtimeSnapshotPublisher: RuntimeSnapshotPublisher
    private let runtimeStatusStore: RuntimeStatusStore
    private let runtimeLogStore: RuntimeLogStore
    private var routingRuleText: String

    public init(
        nodes: [ProxyNode],
        logLimit: Int = 5,
        runtimeSnapshotStore: RuntimeSnapshotStore = InMemoryRuntimeSnapshotStore(),
        runtimeStatusStore: RuntimeStatusStore = InMemoryRuntimeStatusStore(),
        runtimeLogStore: RuntimeLogStore = InMemoryRuntimeLogStore()
    ) {
        self.logLimit = max(0, logLimit)
        self.runtimeSnapshotPublisher = RuntimeSnapshotPublisher(store: runtimeSnapshotStore)
        self.runtimeStatusStore = runtimeStatusStore
        self.runtimeLogStore = runtimeLogStore
        self.routingRuleText = ""
        self.runtimeConnectionStatus = nil
        self.runtimeLogs = []
        self.nodeListState = NodeListState(nodes: nodes, selectedNodeID: nil)
        self.overviewState = OverviewState(connectionStatus: .disconnected, selectedNode: nil, routeMode: .ruleBased, recentLogMessages: [])
        self.settingsState = SettingsState(vpnPermissionStatus: "未配置", appGroupStatus: "未验证", debugLoggingEnabled: false)
    }
```

Add this method before `appendLog(_:)`:

```swift
    @discardableResult
    public func refreshRuntimeFeedback() -> RuntimeFeedbackRefreshResult {
        let status: RuntimeConnectionStatus
        do {
            status = try runtimeStatusStore.load() ?? .disconnected()
        } catch {
            return .statusLoadFailed(String(describing: error))
        }

        let logs: [RuntimeLogEntry]
        do {
            logs = try runtimeLogStore.loadRecent()
        } catch {
            return .logLoadFailed(String(describing: error))
        }

        runtimeConnectionStatus = status
        runtimeLogs = logs
        overviewState = OverviewState(
            connectionStatus: appConnectionStatus(from: status.phase),
            selectedNode: overviewState.selectedNode,
            routeMode: overviewState.routeMode,
            recentLogMessages: Array(logs.suffix(logLimit).map(\.message))
        )
        return .refreshed
    }

    private func appConnectionStatus(from phase: RuntimeConnectionPhase) -> ConnectionStatus {
        switch phase {
        case .disconnected, .disconnecting:
            return .disconnected
        case .preparing, .connecting, .reconnecting:
            return .connecting
        case .connected:
            return .connected
        case .failed:
            return .failed
        }
    }
```

- [ ] **Step 4: Run app feature tests**

Run:

```bash
swift test --filter IrockAppFeatureTests
```

Expected: PASS with all app feature tests passing.

- [ ] **Step 5: Commit app refresh integration**

```bash
git add packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
git commit -m "feat: refresh runtime feedback in app model"
```

---

### Task 6: Final verification and documentation check

**Files:**
- Verify only; no source edits expected.

- [ ] **Step 1: Run focused cross-package tests**

Run:

```bash
swift test --filter IrockCoreTests && swift test --filter IrockStorageTests && swift test --filter IrockTunnelCoreTests && swift test --filter IrockAppFeatureTests
```

Expected: PASS for all four package test groups.

- [ ] **Step 2: Run full SwiftPM test suite**

Run:

```bash
swift test
```

Expected: PASS with all tests passing.

- [ ] **Step 3: Inspect git status**

Run:

```bash
git status --short
```

Expected: no uncommitted source changes.

- [ ] **Step 4: If verification changed no files, create no commit**

If `git status --short` is empty, do not create an empty commit. Report verification evidence instead.

---

## Self-Review

Spec coverage:

- Core status/log models: Task 1.
- In-memory and file-backed stores: Task 2.
- Tunnel reporter: Task 3.
- Packet runtime lifecycle publication: Task 4.
- App model refresh: Task 5.
- SwiftPM verification: Task 6.

Placeholder scan: no unfinished marker phrases remain in this plan.

Type consistency: later tasks use `RuntimeConnectionStatus`, `RuntimeLogEntry`, `RuntimeStatusStore`, `RuntimeLogStore`, `TunnelRuntimeReporter`, and `RuntimeFeedbackRefreshResult` exactly as defined in earlier tasks.
