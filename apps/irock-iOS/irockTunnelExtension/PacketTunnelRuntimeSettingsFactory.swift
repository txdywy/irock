import NetworkExtension

struct PacketTunnelRuntimeSettingsFactory: Sendable {
    let configuration: PacketTunnelRuntimeSettingsConfiguration

    init(configuration: PacketTunnelRuntimeSettingsConfiguration = PacketTunnelRuntimeSettingsConfiguration()) {
        self.configuration = configuration
    }

    func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: configuration.tunnelRemoteAddress)
        let ipv4Settings = NEIPv4Settings(addresses: [configuration.ipv4Address], subnetMasks: [configuration.ipv4SubnetMask])
        ipv4Settings.includedRoutes = [.default()]
        settings.ipv4Settings = ipv4Settings
        settings.dnsSettings = NEDNSSettings(servers: configuration.dnsServers)
        settings.mtu = NSNumber(value: configuration.mtu)
        return settings
    }
}
