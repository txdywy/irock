import IrockProtocols
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

    func validateStartup() throws {
        let stores = try storeResolver.makeRuntimeStoreBundle()
        guard try stores.snapshotStore.load() != nil else {
            throw TunnelRuntimeControllerError.missingRuntimeSnapshot
        }
    }

    func runOnce(packetFlow: NEPacketTunnelFlow) async throws -> PacketTunnelRuntimeSummary {
        let stores = try storeResolver.makeRuntimeStoreBundle()
        return try await TunnelRuntimeController.runShadowsocksTCPBatch(
            snapshotStore: stores.snapshotStore,
            flow: NEPacketTunnelFlowPacketFlowIO(packetFlow: packetFlow),
            statusStore: stores.statusStore,
            logStore: stores.logStore,
            plain: TCPTransportAdapter(dialer: IOSPlatformTCPDialer()),
            tls: UnsupportedTransportAdapter(transport: .tcp),
            credentialResolver: MissingShadowsocksCredentialResolver(),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
}
