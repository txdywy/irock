import NetworkExtension

struct PacketTunnelRuntimeSettingsApplicator: Sendable {
    private let factory: PacketTunnelRuntimeSettingsFactory

    init(factory: PacketTunnelRuntimeSettingsFactory = PacketTunnelRuntimeSettingsFactory()) {
        self.factory = factory
    }

    func apply(to provider: NEPacketTunnelProvider) async throws {
        try await provider.setTunnelNetworkSettings(factory.makeNetworkSettings())
    }
}
