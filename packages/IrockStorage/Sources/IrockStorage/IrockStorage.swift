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
