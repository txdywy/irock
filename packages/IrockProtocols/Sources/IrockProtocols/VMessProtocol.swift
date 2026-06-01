import Foundation
import IrockCore

public struct VMessOpenRequest: Equatable, Sendable {
    public let destinationDescription: String
    public let security: String
    public let alterID: Int
    public let openBytes: Data

    public var metadata: [String: String] {
        [
            "vmessUserIDPresent": "true",
            "vmessDestination": destinationDescription,
            "vmessSecurity": security,
            "vmessAlterID": String(alterID)
        ]
    }

    public init(userID: String, destination: ProxyDestination, security: String = "auto", alterID: Int = 0) throws {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard UUID(uuidString: normalizedUserID) != nil else {
            throw ProxyProtocolError.invalidConfiguration("invalid vmess user id")
        }
        guard alterID >= 0 else {
            throw ProxyProtocolError.invalidConfiguration("invalid vmess alter id")
        }
        let normalizedSecurity = security.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSecurity.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("invalid vmess security")
        }

        let allowedSecurity = ["auto", "none", "aes-128-gcm", "chacha20-poly1305"]
        guard allowedSecurity.contains(normalizedSecurity) else {
            throw ProxyProtocolError.invalidConfiguration("unsupported vmess security")
        }
        let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x02, ipv4Type: 0x01, ipv6Type: 0x03)
        let securityCode: UInt8
        switch normalizedSecurity {
        case "none": securityCode = 0x05
        case "aes-128-gcm": securityCode = 0x03
        case "chacha20-poly1305": securityCode = 0x04
        default: securityCode = 0x00
        }
        self.destinationDescription = frame.description
        self.security = normalizedSecurity
        self.alterID = alterID
        var bytes = Data([0x01, 0x01, UInt8(min(alterID, 255)), securityCode])
        bytes.append(frame.bytes.suffix(2))
        bytes.append(frame.bytes.prefix(frame.bytes.count - 2))
        self.openBytes = bytes
    }

    private static func destinationDescription(_ destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port):
            return "host:\(host):\(port)"
        case let .ipv4(address, port):
            return "ipv4:\(address):\(port)"
        case let .ipv6(address, port):
            return "ipv6:\(address):\(port)"
        }
    }
}
