import Foundation

struct IOSVPNManagerConfiguration: Equatable, Sendable {
    let providerBundleIdentifier: String
    let localizedDescription: String
    let serverAddress: String
    let appGroupIdentifier: String

    static let `default` = IOSVPNManagerConfiguration(
        providerBundleIdentifier: "dev.irock.app.tunnel",
        localizedDescription: "irock Packet Tunnel",
        serverAddress: "irock.local",
        appGroupIdentifier: "group.dev.irock.shared"
    )
}
