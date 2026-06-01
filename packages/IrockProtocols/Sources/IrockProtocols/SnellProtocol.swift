import Foundation
import IrockCore

public struct SnellOpenRequest: Equatable, Sendable {
    public let version: Int
    public let destinationDescription: String
    public let openBytes: Data
    private let passwordPresent: Bool
    private let marker: String

    public var metadata: [String: String] {
        [
            "snellVersion": "\(version)",
            "snellPasswordPresent": passwordPresent ? "true" : "false",
            "snellDestination": destinationDescription,
            "snellNativeStreamMarker": marker
        ]
    }

    public init(credential: String, destination: ProxyDestination) throws {
        let parsed = try Self.parseCredential(credential)
        self.version = parsed.version
        self.passwordPresent = true
        self.destinationDescription = Self.destinationDescription(destination)
        self.marker = "irock-snell-native:v\(parsed.version):\(destinationDescription)"
        self.openBytes = Data(marker.utf8)
    }

    private static func parseCredential(_ credential: String) throws -> (version: Int, password: String) {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing snell credential")
        }
        guard !trimmed.contains("?obfs=") && !trimmed.contains("&obfs=") else {
            throw ProxyProtocolError.invalidConfiguration("unsupported snell obfs")
        }
        guard let separator = trimmed.firstIndex(of: ":") else {
            throw ProxyProtocolError.invalidConfiguration("missing snell version")
        }
        let versionText = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let password = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let version = Int(versionText) else {
            throw ProxyProtocolError.invalidConfiguration("invalid snell version")
        }
        guard version == 1 else {
            throw ProxyProtocolError.invalidConfiguration("unsupported snell version")
        }
        guard !password.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing snell password")
        }
        return (version, password)
    }

    private static func destinationDescription(_ destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port): return "host:\(host):\(port)"
        case let .ipv4(address, port): return "ipv4:\(address):\(port)"
        case let .ipv6(address, port): return "ipv6:\(address):\(port)"
        }
    }
}
