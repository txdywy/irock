import IrockStorage
import IrockTransport
import IrockTunnelCore
import NetworkExtension

struct IOSPacketTunnelSmokeRunner: Sendable {
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

    func runOnce(packetFlow: NEPacketTunnelFlow) async throws -> PacketTunnelRuntimeSummary {
        let stores = try storeResolver.makeRuntimeStoreBundle()
        return try await TunnelRuntimeController.runShadowsocksTCPBatch(
            snapshotStore: stores.snapshotStore,
            flow: NEPacketTunnelFlowPacketFlowIO(packetFlow: packetFlow),
            statusStore: stores.statusStore,
            logStore: stores.logStore,
            plain: UnsupportedTransportAdapter(transport: .tcp),
            tls: UnsupportedTransportAdapter(transport: .tcp),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
}
