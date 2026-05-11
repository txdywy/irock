import Foundation
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

    public func reportStopped() throws {
        try reportLifecycle(message: "Tunnel stopped", phase: .disconnected)
    }

    public func reportRuntimeStoreUnavailable() throws {
        try reportLifecycle(message: "Runtime store unavailable", phase: .failed)
    }

    private func reportLifecycle(message: String, phase: RuntimeConnectionPhase) throws {
        try publishStatus(RuntimeConnectionStatus(
            phase: phase,
            selectedNodeID: nil,
            selectedNodeName: nil,
            updatedAt: Date(),
            message: message
        ))
        try appendLog(RuntimeLogEntry(
            id: "log-\(UUID().uuidString)",
            timestamp: Date(),
            level: .user,
            message: message,
            nodeID: nil,
            phase: phase
        ))
    }
}
