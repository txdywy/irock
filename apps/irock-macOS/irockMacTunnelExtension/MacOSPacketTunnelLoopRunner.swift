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
        while !Task.isCancelled {
            _ = try await smokeRunner.runOnce(packetFlow: packetFlow)
            try await Task.sleep(nanoseconds: loopDelayNanoseconds)
        }
    }
}
