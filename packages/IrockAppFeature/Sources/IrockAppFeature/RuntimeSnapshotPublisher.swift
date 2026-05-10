import Foundation
import IrockCore
import IrockStorage

public enum RuntimeSnapshotPublishResult: Equatable, Sendable {
    case published(SnapshotID)
    case missingSelectedNode
    case storageFailed(String)
}

public struct RuntimeSnapshotPublisher: Sendable {
    private let store: RuntimeSnapshotStore

    public init(store: RuntimeSnapshotStore) {
        self.store = store
    }

    public func publish(selectedNode: ProxyNode?, routeMode: RouteMode, logLevel: IrockLogLevel) -> RuntimeSnapshotPublishResult {
        guard let selectedNode else {
            return .missingSelectedNode
        }

        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-\(UUID().uuidString)"),
            selectedNode: selectedNode,
            routeMode: routeMode,
            logLevel: logLevel
        )

        do {
            try store.save(snapshot)
            return .published(snapshot.id)
        } catch {
            return .storageFailed(String(describing: error))
        }
    }
}
