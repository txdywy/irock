import Foundation
import IrockCore

public protocol RuntimeSnapshotStore: Sendable {
    func save(_ snapshot: RuntimeSnapshot) throws
    func load() throws -> RuntimeSnapshot?
}

public final class InMemoryRuntimeSnapshotStore: RuntimeSnapshotStore, @unchecked Sendable {
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

public final class FileRuntimeSnapshotStore: RuntimeSnapshotStore, @unchecked Sendable {
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
    private let lock = NSLock()
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
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var entries = try loadRecentUnlocked()
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        let data = try encoder.encode(entries)
        try data.write(to: logsURL, options: .atomic)
    }

    public func loadRecent() throws -> [RuntimeLogEntry] {
        lock.lock()
        defer { lock.unlock() }

        return try loadRecentUnlocked()
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode([RuntimeLogEntry]())
        try data.write(to: logsURL, options: .atomic)
    }

    private func loadRecentUnlocked() throws -> [RuntimeLogEntry] {
        guard fileManager.fileExists(atPath: logsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: logsURL)
        return try decoder.decode([RuntimeLogEntry].self, from: data)
    }
}
