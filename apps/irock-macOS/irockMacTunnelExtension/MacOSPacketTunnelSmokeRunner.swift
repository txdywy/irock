import Foundation
import IrockCore
import IrockProtocols
import IrockStorage
import IrockTransport
import IrockTunnelCore
import NetworkExtension

struct MacOSPacketTunnelSmokeRunner: Sendable {
    private let storeResolver: PacketTunnelAppGroupStoreResolver
    private let batchLimit: Int
    private let flowLimit: Int

    init(
        storeResolver: PacketTunnelAppGroupStoreResolver = PacketTunnelAppGroupStoreResolver(),
        batchLimit: Int = 8,
        flowLimit: Int = 64
    ) {
        self.storeResolver = storeResolver
        self.batchLimit = batchLimit
        self.flowLimit = flowLimit
    }

    func validateStartup() throws {
        let stores = try storeResolver.makeRuntimeStoreBundle()
        do {
            guard try stores.snapshotStore.load() != nil else {
                reportMissingSnapshot(stores: stores)
                throw TunnelRuntimeControllerError.missingRuntimeSnapshot
            }
        } catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
            throw TunnelRuntimeControllerError.missingRuntimeSnapshot
        } catch {
            let reporter = TunnelRuntimeReporter(statusStore: stores.statusStore, logStore: stores.logStore)
            try? reporter.reportRuntimeStoreUnavailable()
            throw error
        }
    }

    func runOnce(packetFlow: NEPacketTunnelFlow) async throws -> PacketTunnelRuntimeSummary {
        let stores = try storeResolver.makeRuntimeStoreBundle()
        return try await TunnelRuntimeController.runShadowsocksTCPBatch(
            snapshotStore: stores.snapshotStore,
            flow: NEPacketTunnelFlowPacketFlowIO(packetFlow: packetFlow),
            statusStore: stores.statusStore,
            logStore: stores.logStore,
            plain: TCPTransportAdapter(dialer: MacOSPlatformTCPDialer()),
            tls: UnsupportedTransportAdapter(transport: .tcp),
            credentialResolver: MissingShadowsocksCredentialResolver(),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    private func reportMissingSnapshot(stores: RuntimeStoreBundle) {
        let message = "Runtime snapshot unavailable"
        try? stores.statusStore.save(RuntimeConnectionStatus(
            phase: .failed,
            selectedNodeID: nil,
            selectedNodeName: nil,
            updatedAt: Date(),
            message: message
        ))
        try? stores.logStore.append(RuntimeLogEntry(
            id: "log-\(UUID().uuidString)",
            timestamp: Date(),
            level: .user,
            message: message,
            nodeID: nil,
            phase: .failed
        ))
    }
}
