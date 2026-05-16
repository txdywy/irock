import NetworkExtension

struct MacOSPacketTunnelLoopRunner: Sendable {
    private let smokeRunner: MacOSPacketTunnelSmokeRunner
    private let loopDelayNanoseconds: UInt64

    init(
        smokeRunner: MacOSPacketTunnelSmokeRunner = MacOSPacketTunnelSmokeRunner(),
        loopDelayNanoseconds: UInt64 = 50_000_000
    ) {
        self.smokeRunner = smokeRunner
        self.loopDelayNanoseconds = loopDelayNanoseconds
    }

    func validateStartup() throws {
        try smokeRunner.validateStartup()
    }

    func run(packetFlow: NEPacketTunnelFlow) async throws {
        let runtime = try smokeRunner.makeSession(packetFlow: packetFlow)
        do {
            while !Task.isCancelled {
                _ = try await runtime.runOnce()
                try await Task.sleep(nanoseconds: loopDelayNanoseconds)
            }
            await runtime.closeProxyConnections()
        } catch {
            await runtime.closeProxyConnections()
            throw error
        }
    }
}
