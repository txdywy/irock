import Foundation
import IrockCore

public struct HTTPProxyOpenRequest: Equatable, Sendable {
    public let destinationAuthority: String
    public let openBytes: Data
    private let authorizationPresent: Bool

    public var metadata: [String: String] {
        [
            "httpProxyAuthorizationPresent": authorizationPresent ? "true" : "false",
            "httpProxyDestination": destinationAuthority
        ]
    }

    public init(credential: String?, destination: ProxyDestination) throws {
        let authority = Self.authority(for: destination)
        let authorization = try Self.authorizationHeader(from: credential)
        self.destinationAuthority = authority
        self.authorizationPresent = authorization != nil

        var text = "CONNECT \(authority) HTTP/1.1\r\nHost: \(authority)\r\n"
        if let authorization {
            text += "Proxy-Authorization: \(authorization)\r\n"
        }
        text += "\r\n"
        self.openBytes = Data(text.utf8)
    }

    private static func authorizationHeader(from credential: String?) throws -> String? {
        guard let credential else { return nil }
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "anonymous" else { return nil }

        let usernameText: String
        if let separator = trimmed.firstIndex(of: ":") {
            usernameText = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            usernameText = trimmed
        }
        guard !usernameText.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing http proxy username")
        }
        return "Basic \(Data(trimmed.utf8).base64EncodedString())"
    }

    private static func authority(for destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port):
            return "\(host):\(port)"
        case let .ipv4(address, port):
            return "\(address):\(port)"
        case let .ipv6(address, port):
            return "[\(address)]:\(port)"
        }
    }
}
