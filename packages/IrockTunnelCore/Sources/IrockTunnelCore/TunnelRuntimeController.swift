import IrockStorage
import IrockTransport

public enum TunnelRuntimeControllerError: Error, Equatable, Sendable {
    case missingRuntimeSnapshot
}

public struct TunnelRuntimeController: Sendable {
    public static func runShadowsocksTCPBatch<Flow: PacketFlowIO, Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary {
        guard let snapshot = try snapshotStore.load() else {
            throw TunnelRuntimeControllerError.missingRuntimeSnapshot
        }
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: batchLimit)
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: snapshot,
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tls,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        return try await runtime.runOnce()
    }
}
