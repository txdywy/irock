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

    func testFileRuntimeLogStorePreservesConcurrentAppends() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        let entryCount = 200
        let store = FileRuntimeLogStore(directoryURL: directoryURL, limit: entryCount)
        let errorLock = NSLock()
        var appendErrors: [Error] = []

        DispatchQueue.concurrentPerform(iterations: entryCount) { index in
            do {
                try store.append(makeLog(id: "\(index)", message: "message-\(index)"))
            } catch {
                errorLock.lock()
                appendErrors.append(error)
                errorLock.unlock()
            }
        }

        XCTAssertTrue(appendErrors.isEmpty)
        let messages = try store.loadRecent().map(\.message)
        XCTAssertEqual(messages.count, entryCount)
        XCTAssertEqual(Set(messages).count, entryCount)
    }

    func testFileRuntimeLogStoreThrowsForCorruptJSON() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directoryURL.appendingPathComponent("runtime-logs.json", isDirectory: false))
        let store = FileRuntimeLogStore(directoryURL: directoryURL)

        XCTAssertThrowsError(try store.loadRecent())
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

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IrockStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
