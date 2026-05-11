import NetworkExtension

struct MacOSVPNConnectionStatus: Equatable, Sendable {
    let isInstalled: Bool
    let isEnabled: Bool
    let statusDescription: String
}

final class MacOSVPNManager {
    private let configuration: MacOSVPNManagerConfiguration

    init(configuration: MacOSVPNManagerConfiguration = .default) {
        self.configuration = configuration
    }

    func installOrUpdate() async throws {
        let manager = try await loadOrCreateManager()
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = configuration.providerBundleIdentifier
        tunnelProtocol.serverAddress = configuration.serverAddress
        tunnelProtocol.providerConfiguration = ["appGroupIdentifier": configuration.appGroupIdentifier]
        manager.protocolConfiguration = tunnelProtocol
        manager.localizedDescription = configuration.localizedDescription
        manager.isEnabled = true
        try await manager.saveToPreferences()
    }

    func start() async throws {
        let manager = try await loadOrCreateManager()
        if manager.protocolConfiguration == nil || !manager.isEnabled {
            try await installOrUpdate()
        }
        let currentManager = try await loadOrCreateManager()
        try currentManager.connection.startVPNTunnel()
    }

    func stop() async throws {
        let manager = try await loadOrCreateManager()
        manager.connection.stopVPNTunnel()
    }

    func status() async throws -> MacOSVPNConnectionStatus {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first(where: matchesConfiguration) else {
            return MacOSVPNConnectionStatus(isInstalled: false, isEnabled: false, statusDescription: "notInstalled")
        }
        return MacOSVPNConnectionStatus(isInstalled: true, isEnabled: manager.isEnabled, statusDescription: statusDescription(manager.connection.status))
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first(where: matchesConfiguration) {
            return existing
        }
        return NETunnelProviderManager()
    }

    private func matchesConfiguration(_ manager: NETunnelProviderManager) -> Bool {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return false
        }
        return tunnelProtocol.providerBundleIdentifier == configuration.providerBundleIdentifier
    }

    private func statusDescription(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid:
            return "invalid"
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reasserting:
            return "reasserting"
        case .disconnecting:
            return "disconnecting"
        @unknown default:
            return "unknown"
        }
    }
}
