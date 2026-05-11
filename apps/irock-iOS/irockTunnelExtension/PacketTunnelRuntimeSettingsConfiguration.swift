struct PacketTunnelRuntimeSettingsConfiguration: Equatable, Sendable {
    let tunnelRemoteAddress: String
    let ipv4Address: String
    let ipv4SubnetMask: String
    let dnsServers: [String]
    let mtu: Int

    init(
        tunnelRemoteAddress: String = "127.0.0.1",
        ipv4Address: String = "10.255.0.2",
        ipv4SubnetMask: String = "255.255.255.0",
        dnsServers: [String] = ["1.1.1.1", "8.8.8.8"],
        mtu: Int = 1500
    ) {
        self.tunnelRemoteAddress = tunnelRemoteAddress
        self.ipv4Address = ipv4Address
        self.ipv4SubnetMask = ipv4SubnetMask
        self.dnsServers = dnsServers
        self.mtu = mtu
    }
}
