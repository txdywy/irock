import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var startTunnelTask: Task<Void, Error>?

    override func startTunnel(options: [String: NSObject]?) async throws {
        try await PacketTunnelRuntimeSettingsApplicator().apply(to: self)
        let loopRunner = IOSPacketTunnelLoopRunner()
        try loopRunner.validateStartup()
        let task = Task {
            try await loopRunner.run(packetFlow: packetFlow)
        }
        startTunnelTask = task
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        startTunnelTask?.cancel()
        startTunnelTask = nil
    }
}
