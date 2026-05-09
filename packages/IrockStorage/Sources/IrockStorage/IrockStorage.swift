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
