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
