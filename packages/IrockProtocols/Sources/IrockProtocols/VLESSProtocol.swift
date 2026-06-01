import Foundation
import IrockCore

public struct VLESSRealityHandshakeConfiguration: Equatable, Sendable {
    public let serverName: String
    public let clientFingerprint: String
    public let publicKeyBytes: Data
    public let shortIDBytes: Data
    public let spiderX: String
    public let metadata: [String: String]

    public init(tls: TLSOptions) throws {
        guard tls.enabled else {
            throw ProxyProtocolError.invalidConfiguration("missing reality tls")
        }
        let normalizedServerName = tls.serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedServerName.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing reality server name")
        }
        guard let reality = tls.reality else {
            throw ProxyProtocolError.invalidConfiguration("missing reality options")
        }
        let normalizedFingerprint = tls.fingerprint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalizedFingerprint.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing reality fingerprint")
        }
        let publicKeyBytes = try Self.publicKeyBytes(reality.publicKey)
        let shortIDBytes = try Self.shortIDBytes(reality.shortID)
        let spiderX = reality.spiderX?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? reality.spiderX!.trimmingCharacters(in: .whitespacesAndNewlines) : "/"
        self.serverName = normalizedServerName
        self.clientFingerprint = normalizedFingerprint
        self.publicKeyBytes = publicKeyBytes
        self.shortIDBytes = shortIDBytes
        self.spiderX = spiderX
        self.metadata = [
            "vlessRealityPresent": "true",
            "vlessRealityServerName": normalizedServerName,
            "vlessRealityShortIDBytes": String(shortIDBytes.count),
            "vlessRealitySpiderX": spiderX,
            "vlessRealityFingerprint": normalizedFingerprint
        ]
    }

    private static func publicKeyBytes(_ value: String) throws -> Data {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.unicodeScalars.allSatisfy(Self.isBase64URLScalar) else {
            throw ProxyProtocolError.invalidConfiguration("invalid reality public key")
        }
        var base64 = normalized.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: padding))
        }
        guard let data = Data(base64Encoded: base64), data.count == 32 else {
            throw ProxyProtocolError.invalidConfiguration("invalid reality public key")
        }
        return data
    }

    private static func isBase64URLScalar(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value) || value == 45 || value == 95
    }

    private static func shortIDBytes(_ value: String?) throws -> Data {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard normalized.count <= 16, normalized.count % 2 == 0 else {
            throw ProxyProtocolError.invalidConfiguration("invalid reality short id")
        }
        guard !normalized.isEmpty else { return Data() }
        var bytes = Data()
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else {
                throw ProxyProtocolError.invalidConfiguration("invalid reality short id")
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}

public struct VLESSOpenRequest: Equatable, Sendable {
    public let destinationDescription: String
    public let security: String
    public let flow: String
    public let openBytes: Data

    public var metadata: [String: String] {
        [
            "vlessUserIDPresent": "true",
            "vlessDestination": destinationDescription,
            "vlessSecurity": security,
            "vlessFlow": flow
        ]
    }

    public init(userID: String, destination: ProxyDestination, security: String = "none", flow: String = "") throws {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard UUID(uuidString: normalizedUserID) != nil else {
            throw ProxyProtocolError.invalidConfiguration("invalid vless user id")
        }
        let normalizedSecurity = security.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSecurity.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("invalid vless security")
        }

        let uuid = try Self.uuidBytes(normalizedUserID)
        let normalizedFlow = flow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedSecurity == "none" else {
            throw ProxyProtocolError.invalidConfiguration("unsupported vless security")
        }
        guard normalizedFlow.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("unsupported vless flow")
        }
        let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x02, ipv4Type: 0x01, ipv6Type: 0x03)
        self.destinationDescription = frame.description
        self.security = normalizedSecurity
        self.flow = normalizedFlow
        var bytes = Data([0x00])
        bytes.append(contentsOf: uuid)
        bytes.append(0x00)
        bytes.append(0x01)
        bytes.append(frame.bytes.suffix(2))
        bytes.append(frame.bytes.prefix(frame.bytes.count - 2))
        self.openBytes = bytes
    }

    private static func uuidBytes(_ value: String) throws -> [UInt8] {
        guard let uuid = UUID(uuidString: value) else {
            throw ProxyProtocolError.invalidConfiguration("invalid vless user id")
        }
        let tuple = uuid.uuid
        return [tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7, tuple.8, tuple.9, tuple.10, tuple.11, tuple.12, tuple.13, tuple.14, tuple.15]
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
