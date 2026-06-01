import Foundation
import IrockCore

public struct SOCKSOpenRequest: Equatable, Sendable {
    public let destinationDescription: String
    public let openBytes: Data
    private let authenticationPresent: Bool
    private let usernamePresent: Bool

    public var metadata: [String: String] {
        [
            "socksAuthenticationPresent": authenticationPresent ? "true" : "false",
            "socksUsernamePresent": usernamePresent ? "true" : "false",
            "socksDestination": destinationDescription
        ]
    }

    public init(credential: String?, destination: ProxyDestination) throws {
        let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04)
        let userPassword = try Self.userPassword(from: credential)
        self.destinationDescription = frame.description
        self.authenticationPresent = userPassword != nil
        self.usernamePresent = userPassword != nil

        var bytes = Data()
        if let userPassword {
            bytes.append(contentsOf: [0x05, 0x02, 0x00, 0x02, 0x01, UInt8(userPassword.username.count)])
            bytes.append(userPassword.username)
            bytes.append(UInt8(userPassword.password.count))
            bytes.append(userPassword.password)
        } else {
            bytes.append(contentsOf: [0x05, 0x01, 0x00])
        }
        bytes.append(contentsOf: [0x05, 0x01, 0x00])
        bytes.append(frame.bytes)
        self.openBytes = bytes
    }

    private struct UserPassword: Equatable, Sendable {
        let username: Data
        let password: Data
    }

    private static func userPassword(from credential: String?) throws -> UserPassword? {
        guard let credential else { return nil }
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "anonymous" else { return nil }

        let usernameText: String
        let passwordText: String
        if let separator = trimmed.firstIndex(of: ":") {
            usernameText = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            passwordText = String(trimmed[trimmed.index(after: separator)...])
        } else {
            usernameText = trimmed
            passwordText = ""
        }

        let username = Data(usernameText.utf8)
        let password = Data(passwordText.utf8)
        guard !username.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing socks username")
        }
        guard username.count <= UInt8.max else {
            throw ProxyProtocolError.invalidConfiguration("invalid socks username")
        }
        guard password.count <= UInt8.max else {
            throw ProxyProtocolError.invalidConfiguration("invalid socks password")
        }
        return UserPassword(username: username, password: password)
    }
}
