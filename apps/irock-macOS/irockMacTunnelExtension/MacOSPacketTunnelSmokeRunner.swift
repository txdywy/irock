import Foundation
import IrockCore
import IrockStorage
import IrockTunnelCore
import NetworkExtension

struct MacOSPacketTunnelSmokeRunner: Sendable {
    private let storeResolver: PacketTunnelAppGroupStoreResolver

    init(storeResolver: PacketTunnelAppGroupStoreResolver = PacketTunnelAppGroupStoreResolver()) {
        self.storeResolver = storeResolver
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
        reportScaffoldReady(stores: stores)
        return PacketTunnelRuntimeSummary(readCount: 0, writtenCount: 0, dropCount: 0)
    }

    private func reportMissingSnapshot(stores: RuntimeStoreBundle) {
        report(message: "Runtime snapshot unavailable", phase: .failed, stores: stores)
    }

    private func reportScaffoldReady(stores: RuntimeStoreBundle) {
        report(message: "macOS Packet Tunnel scaffold ready", phase: .preparing, stores: stores)
    }

    private func report(message: String, phase: RuntimeConnectionPhase, stores: RuntimeStoreBundle) {
        try? stores.statusStore.save(RuntimeConnectionStatus(
            phase: phase,
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
            phase: phase
        ))
    }
}
