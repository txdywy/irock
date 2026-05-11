import Foundation

struct MacOSVPNManagerConfiguration: Equatable, Sendable {
    let providerBundleIdentifier: String
    let localizedDescription: String
    let serverAddress: String
    let appGroupIdentifier: String

    static let `default` = MacOSVPNManagerConfiguration(
        providerBundleIdentifier: "dev.irock.mac.app.tunnel",
        localizedDescription: "irock macOS Packet Tunnel",
        serverAddress: "irock.local",
        appGroupIdentifier: "group.dev.irock.shared"
    )
}
