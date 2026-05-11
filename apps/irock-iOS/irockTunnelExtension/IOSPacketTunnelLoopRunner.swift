import Foundation
import NetworkExtension

struct IOSPacketTunnelLoopRunner: Sendable {
    private let smokeRunner: IOSPacketTunnelSmokeRunner
    private let loopDelayNanoseconds: UInt64

    init(
        smokeRunner: IOSPacketTunnelSmokeRunner = IOSPacketTunnelSmokeRunner(),
        loopDelayNanoseconds: UInt64 = 50_000_000
    ) {
        self.smokeRunner = smokeRunner
        self.loopDelayNanoseconds = loopDelayNanoseconds
    }

    func runStartupBatch(packetFlow: NEPacketTunnelFlow) async throws {
        _ = try await smokeRunner.runOnce(packetFlow: packetFlow)
    }

    func run(packetFlow: NEPacketTunnelFlow) async throws {
        while !Task.isCancelled {
            _ = try await smokeRunner.runOnce(packetFlow: packetFlow)
            try await Task.sleep(nanoseconds: loopDelayNanoseconds)
        }
    }
}
