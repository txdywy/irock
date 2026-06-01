import NetworkExtension

public struct PacketTunnelRuntimeSettingsApplicator: Sendable {
    private let factory: PacketTunnelRuntimeSettingsFactory

    public init(factory: PacketTunnelRuntimeSettingsFactory = PacketTunnelRuntimeSettingsFactory()) {
        self.factory = factory
    }

    public func apply(to provider: NEPacketTunnelProvider) async throws {
        try await provider.setTunnelNetworkSettings(factory.makeNetworkSettings())
    }
}
