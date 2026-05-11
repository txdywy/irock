import IrockTunnelCore
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
        let task = startTunnelTask
        task?.cancel()
        startTunnelTask = nil
        if let task {
            do {
                try await task.value
            } catch {}
        }
        reportStoppedLifecycle()
    }

    private func reportStoppedLifecycle() {
        guard let stores = try? PacketTunnelAppGroupStoreResolver().makeRuntimeStoreBundle() else {
            return
        }
        let reporter = TunnelRuntimeReporter(statusStore: stores.statusStore, logStore: stores.logStore)
        try? reporter.reportStopped()
    }
}
