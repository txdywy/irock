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
