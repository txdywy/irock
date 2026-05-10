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
