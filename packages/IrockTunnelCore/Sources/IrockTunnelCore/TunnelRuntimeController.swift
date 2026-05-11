import Foundation
import IrockCore
import IrockProtocols
import IrockStorage
import IrockTransport

public enum TunnelRuntimeControllerError: Error, Equatable, Sendable {
    case missingRuntimeSnapshot
}

public struct TunnelRuntimeController: Sendable {
    public static func runShadowsocksTCPBatch<Flow: PacketFlowIO, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary {
        let snapshot: RuntimeSnapshot
        do {
            guard let loadedSnapshot = try snapshotStore.load() else {
                reportMissingSnapshot(statusStore: statusStore, logStore: logStore)
                throw TunnelRuntimeControllerError.missingRuntimeSnapshot
            }
            snapshot = loadedSnapshot
        } catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
            throw TunnelRuntimeControllerError.missingRuntimeSnapshot
        } catch {
            let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
            try? reporter.reportRuntimeStoreUnavailable()
            throw error
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
            credentialResolver: credentialResolver,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        return try await runtime.runOnce()
    }

    private static func reportMissingSnapshot(statusStore: RuntimeStatusStore, logStore: RuntimeLogStore) {
        let message = "Runtime snapshot unavailable"
        try? statusStore.save(RuntimeConnectionStatus(
            phase: .failed,
            selectedNodeID: nil,
            selectedNodeName: nil,
            updatedAt: Date(),
            message: message
        ))
        try? logStore.append(RuntimeLogEntry(
            id: "log-\(UUID().uuidString)",
            timestamp: Date(),
            level: .user,
            message: message,
            nodeID: nil,
            phase: .failed
        ))
    }
}
