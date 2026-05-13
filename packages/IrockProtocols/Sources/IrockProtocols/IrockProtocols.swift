import CryptoKit
import Darwin
import Foundation
import IrockCore
import IrockTransport

public enum ProxyDestination: Equatable, Sendable {
    case host(String, port: Int)
    case ipv4(String, port: Int)
    case ipv6(String, port: Int)
}

struct ProtocolAddressFrame: Equatable, Sendable {
    let bytes: Data
    let description: String

    init(destination: ProxyDestination, domainType: UInt8, ipv4Type: UInt8, ipv6Type: UInt8) throws {
        switch destination {
        case let .host(host, port):
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.utf8.count <= UInt8.max else {
                throw ProxyProtocolError.invalidConfiguration("invalid destination host")
            }
            var data = Data([domainType, UInt8(trimmed.utf8.count)])
            data.append(Data(trimmed.utf8))
            data.append(try Self.portBytes(port))
            self.bytes = data
            self.description = "host:\(trimmed):\(port)"
        case let .ipv4(address, port):
            let octets = try Self.ipv4Bytes(address)
            var data = Data([ipv4Type])
            data.append(contentsOf: octets)
            data.append(try Self.portBytes(port))
            self.bytes = data
            self.description = "ipv4:\(address):\(port)"
        case let .ipv6(address, port):
            let segments = try Self.ipv6Bytes(address)
            var data = Data([ipv6Type])
            data.append(contentsOf: segments)
            data.append(try Self.portBytes(port))
            self.bytes = data
            self.description = "ipv6:\(address):\(port)"
        }
    }

    private static func portBytes(_ port: Int) throws -> Data {
        guard (1...65_535).contains(port) else {
            throw ProxyProtocolError.invalidConfiguration("invalid destination port")
        }
        return Data([UInt8(port >> 8), UInt8(port & 0xff)])
    }

    private static func ipv4Bytes(_ address: String) throws -> [UInt8] {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            throw ProxyProtocolError.invalidConfiguration("invalid ipv4 destination")
        }
        return try parts.map { part in
            guard let value = UInt8(part) else {
                throw ProxyProtocolError.invalidConfiguration("invalid ipv4 destination")
            }
            return value
        }
    }

    private static func ipv6Bytes(_ address: String) throws -> [UInt8] {
        var storage = in6_addr()
        let result = address.withCString { inet_pton(AF_INET6, $0, &storage) }
        guard result == 1 else {
            throw ProxyProtocolError.invalidConfiguration("invalid ipv6 destination")
        }
        return withUnsafeBytes(of: storage) { Array($0) }
    }
}

public struct ShadowsocksAEADStreamEncoder: Sendable {
    private var nonceValue: UInt64
    private let subkey: SymmetricKey
    private let cipher: ShadowsocksCipher

    public init(credential: String, salt: Data, initialNonce: UInt64 = 0) throws {
        let parsed = try ShadowsocksStreamRequest.parseCredential(credential)
        guard let cipher = ShadowsocksCipher.lookup(method: parsed.method) else {
            throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks method")
        }
        self.cipher = cipher
        self.subkey = try cipher.deriveSubkey(password: parsed.password, salt: salt)
        self.nonceValue = initialNonce
    }

    public mutating func encrypt(_ payload: Data) throws -> Data {
        guard payload.count <= UInt16.max else {
            throw ProxyProtocolError.invalidConfiguration("shadowsocks payload chunk too large")
        }
        let length = Data([UInt8(payload.count >> 8), UInt8(payload.count & 0xff)])
        let encryptedLength = try cipher.seal(length, using: subkey, nonceValue: nonceValue)
        nonceValue += 1
        let encryptedPayload = try cipher.seal(payload, using: subkey, nonceValue: nonceValue)
        nonceValue += 1
        var frame = Data()
        frame.append(encryptedLength)
        frame.append(encryptedPayload)
        return frame
    }
}

public struct ShadowsocksAEADStreamDecoder: Sendable {
    private var nonceValue: UInt64
    private let subkey: SymmetricKey
    private let cipher: ShadowsocksCipher
    private var buffer: Data
    private var responseRequestSalt: Data?
    private var responseFirstPayloadLength: Int?

    public init(credential: String, salt: Data, initialNonce: UInt64 = 0, requestSalt: Data? = nil) throws {
        let parsed = try ShadowsocksStreamRequest.parseCredential(credential)
        guard let cipher = ShadowsocksCipher.lookup(method: parsed.method) else {
            throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks method")
        }
        if cipher.kind == .shadowsocks2022, let requestSalt, requestSalt.count != cipher.saltLength {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks salt")
        }
        self.cipher = cipher
        self.subkey = try cipher.deriveSubkey(password: parsed.password, salt: salt)
        self.nonceValue = initialNonce
        self.buffer = Data()
        self.responseRequestSalt = cipher.kind == .shadowsocks2022 ? requestSalt : nil
        self.responseFirstPayloadLength = nil
    }

    public mutating func decrypt(_ frame: Data) throws -> Data {
        buffer.append(frame)
        guard let payload = try decryptNextBufferedFrame() else {
            throw ProxyProtocolError.invalidConfiguration("incomplete shadowsocks frame")
        }
        guard buffer.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("trailing shadowsocks frame bytes")
        }
        return payload
    }

    public mutating func appendAndDecrypt<T: DataProtocol>(_ frame: T) throws -> Data? {
        buffer.append(contentsOf: frame)
        return try decryptNextBufferedFrame()
    }

    public mutating func appendAndDecryptAvailable<T: DataProtocol>(_ frame: T) throws -> [Data] {
        buffer.append(contentsOf: frame)
        var payloads: [Data] = []
        while let payload = try decryptNextBufferedFrame() {
            payloads.append(payload)
        }
        return payloads
    }

    private mutating func decryptNextBufferedFrame() throws -> Data? {
        if let requestSalt = responseRequestSalt {
            try decryptResponseHeader(requestSalt: requestSalt)
        }
        if let payloadLength = responseFirstPayloadLength {
            return try decryptFirstResponsePayload(length: payloadLength)
        }

        let lengthFrameSize = 2 + 16
        guard buffer.count >= lengthFrameSize else { return nil }
        let encryptedLength = buffer.prefix(lengthFrameSize)
        let lengthData = try cipher.open(Data(encryptedLength), using: subkey, nonceValue: nonceValue)
        nonceValue += 1
        let payloadLength = Int(lengthData[0]) << 8 | Int(lengthData[1])
        let payloadFrameSize = payloadLength + 16
        guard buffer.count >= lengthFrameSize + payloadFrameSize else {
            nonceValue -= 1
            return nil
        }
        buffer.removeFirst(lengthFrameSize)
        let encryptedPayload = buffer.prefix(payloadFrameSize)
        let payload = try cipher.open(Data(encryptedPayload), using: subkey, nonceValue: nonceValue)
        nonceValue += 1
        buffer.removeFirst(payloadFrameSize)
        return payload
    }

    private mutating func decryptResponseHeader(requestSalt: Data) throws {
        let headerSize = 1 + 8 + cipher.saltLength + 2
        let encryptedHeaderSize = headerSize + 16
        guard buffer.count >= encryptedHeaderSize else { return }
        let header = try cipher.open(Data(buffer.prefix(encryptedHeaderSize)), using: subkey, nonceValue: nonceValue)
        guard header.count == headerSize, header[0] == 1 else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks 2022 response header")
        }
        let saltRange = 9..<(9 + cipher.saltLength)
        guard Data(header[saltRange]) == requestSalt else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks 2022 response salt")
        }
        let lengthIndex = 9 + cipher.saltLength
        responseFirstPayloadLength = Int(header[lengthIndex]) << 8 | Int(header[lengthIndex + 1])
        responseRequestSalt = nil
        nonceValue += 1
        buffer.removeFirst(encryptedHeaderSize)
    }

    private mutating func decryptFirstResponsePayload(length: Int) throws -> Data? {
        let payloadFrameSize = length + 16
        guard buffer.count >= payloadFrameSize else { return nil }
        let payload = try cipher.open(Data(buffer.prefix(payloadFrameSize)), using: subkey, nonceValue: nonceValue)
        nonceValue += 1
        buffer.removeFirst(payloadFrameSize)
        responseFirstPayloadLength = nil
        return payload
    }
}

public struct ShadowsocksStreamRequest: Equatable, Sendable {
    public let cipher: String
    public let addressFrame: Data
    public let openBytes: Data

    public var addressFrameHex: String {
        addressFrame.hexString
    }

    public var openBytesHex: String {
        openBytes.hexString
    }

    public var metadata: [String: String] {
        [
            "shadowsocksCipher": cipher,
            "shadowsocksAddressFrameHex": addressFrameHex,
            "shadowsocksStreamOpenHex": openBytesHex
        ]
    }

    public static func supportsCredential(_ credential: String) -> Bool {
        (try? ShadowsocksCipher.supportsKnownCredential(credential)) == true
    }

    public static func saltLength(forCredential credential: String) throws -> Int {
        let parsed = try parseCredential(credential)
        guard let cipher = ShadowsocksCipher.lookup(method: parsed.method) else {
            throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks method")
        }
        return cipher.saltLength
    }

    public init(
        credential: String,
        destination: ProxyDestination,
        salt: Data,
        timestamp: Date = Date(),
        padding: Data? = nil
    ) throws {
        let parsed = try Self.parseCredential(credential)
        guard let cipher = ShadowsocksCipher.lookup(method: parsed.method) else {
            throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks method")
        }

        self.cipher = cipher.method
        self.addressFrame = try Self.addressFrame(for: destination)
        let subkey = try cipher.deriveSubkey(password: parsed.password, salt: salt)

        switch cipher.kind {
        case .legacyAEAD:
            let length = Data([UInt8(addressFrame.count >> 8), UInt8(addressFrame.count & 0xff)])
            let encryptedLength = try cipher.seal(length, using: subkey, nonceValue: 0)
            let encryptedPayload = try cipher.seal(addressFrame, using: subkey, nonceValue: 1)
            self.openBytes = salt + encryptedLength + encryptedPayload
        case .shadowsocks2022:
            self.openBytes = try Self.shadowsocks2022OpenBytes(
                addressFrame: addressFrame,
                salt: salt,
                subkey: subkey,
                cipher: cipher,
                timestamp: timestamp,
                padding: padding ?? Data([0])
            )
        }
    }

    private static func shadowsocks2022OpenBytes(
        addressFrame: Data,
        salt: Data,
        subkey: SymmetricKey,
        cipher: ShadowsocksCipher,
        timestamp: Date,
        padding: Data
    ) throws -> Data {
        guard !padding.isEmpty, padding.count <= 900 else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks 2022 padding")
        }
        let timestampValue = UInt64(timestamp.timeIntervalSince1970)
        var fixedHeader = Data([0])
        fixedHeader.append(UInt8((timestampValue >> 56) & 0xff))
        fixedHeader.append(UInt8((timestampValue >> 48) & 0xff))
        fixedHeader.append(UInt8((timestampValue >> 40) & 0xff))
        fixedHeader.append(UInt8((timestampValue >> 32) & 0xff))
        fixedHeader.append(UInt8((timestampValue >> 24) & 0xff))
        fixedHeader.append(UInt8((timestampValue >> 16) & 0xff))
        fixedHeader.append(UInt8((timestampValue >> 8) & 0xff))
        fixedHeader.append(UInt8(timestampValue & 0xff))

        var variableHeader = Data()
        variableHeader.append(addressFrame)
        variableHeader.append(UInt8((padding.count >> 8) & 0xff))
        variableHeader.append(UInt8(padding.count & 0xff))
        variableHeader.append(padding)

        fixedHeader.append(UInt8((variableHeader.count >> 8) & 0xff))
        fixedHeader.append(UInt8(variableHeader.count & 0xff))

        let encryptedFixed = try cipher.seal(fixedHeader, using: subkey, nonceValue: 0)
        let encryptedVariable = try cipher.seal(variableHeader, using: subkey, nonceValue: 1)
        return salt + encryptedFixed + encryptedVariable
    }

    static func seal(_ data: Data, using key: SymmetricKey, nonceValue: UInt64) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key, nonce: AES.GCM.Nonce(data: nonceBytes(nonceValue)))
        return sealed.ciphertext + sealed.tag
    }

    static func open(_ data: Data, using key: SymmetricKey, nonceValue: UInt64) throws -> Data {
        guard data.count >= 16 else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks encrypted frame")
        }
        let ciphertext = data.prefix(data.count - 16)
        let tag = data.suffix(16)
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceBytes(nonceValue)), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private static func nonceBytes(_ value: UInt64) -> Data {
        var bytes = Data(repeating: 0, count: 12)
        var current = value
        for index in 0..<8 {
            bytes[index] = UInt8(current & 0xff)
            current >>= 8
        }
        return bytes
    }

    static func evpBytesToKey(password: Data, keyLength: Int) -> Data {
        var key = Data()
        var previous = Data()
        while key.count < keyLength {
            var input = Data()
            input.append(previous)
            input.append(password)
            previous = Data(Insecure.MD5.hash(data: input))
            key.append(previous)
        }
        return key.prefix(keyLength)
    }

    static func parseCredential(_ credential: String) throws -> (method: String, password: String) {
        guard let separator = credential.firstIndex(of: ":") else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks credential")
        }
        let method = credential[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let password = credential[credential.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !method.isEmpty, !password.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks credential")
        }
        return (method, password)
    }

    private static func addressFrame(for destination: ProxyDestination) throws -> Data {
        switch destination {
        case let .host(host, port):
            let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            let hostBytes = Data(normalizedHost.utf8)
            guard !hostBytes.isEmpty, hostBytes.count <= 255 else {
                throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks host")
            }
            return try Data([0x03, UInt8(hostBytes.count)]) + hostBytes + portBytes(port)
        case let .ipv4(address, port):
            let octets = address.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard octets.count == 4 else {
                throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks ipv4 destination")
            }
            let bytes = try octets.map { octet -> UInt8 in
                guard let value = UInt8(octet) else {
                    throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks ipv4 destination")
                }
                return value
            }
            return try Data([0x01]) + Data(bytes) + portBytes(port)
        case let .ipv6(address, port):
            let bytes = try ipv6Bytes(address)
            return try Data([0x04]) + Data(bytes) + portBytes(port)
        }
    }

    private static func ipv6Bytes(_ address: String) throws -> [UInt8] {
        let parts = address.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 8 else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks ipv6 destination")
        }
        return try parts.flatMap { part -> [UInt8] in
            guard part.count <= 4, let value = UInt16(part, radix: 16) else {
                throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks ipv6 destination")
            }
            return [UInt8(value >> 8), UInt8(value & 0xff)]
        }
    }

    private static func portBytes(_ port: Int) throws -> Data {
        guard (1...65_535).contains(port) else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks destination port")
        }
        return Data([UInt8(port >> 8), UInt8(port & 0xff)])
    }
}

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

public struct TrojanOpenRequest: Equatable, Sendable {
    public let destinationDescription: String
    public let serverName: String
    public let openBytes: Data

    public var metadata: [String: String] {
        [
            "trojanPasswordPresent": "true",
            "trojanDestination": destinationDescription,
            "trojanServerName": serverName
        ]
    }

    public init(password: String, destination: ProxyDestination, serverName: String = "") throws {
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing trojan password")
        }

        let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04)
        self.destinationDescription = frame.description
        self.serverName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        var bytes = Data(SHA224.hashHex(password.trimmingCharacters(in: .whitespacesAndNewlines)).utf8)
        bytes.append(Data([0x0d, 0x0a, 0x01]))
        bytes.append(frame.bytes)
        bytes.append(Data([0x0d, 0x0a]))
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

public struct Hysteria2AuthRequest: Equatable, Sendable {
    public let path: String
    public let method: String
    public let headers: [String: String]

    public var metadata: [String: String] {
        [
            "hysteria2AuthPresent": "true",
            "hysteria2AuthMethod": "http3-post"
        ]
    }

    public init(authentication: String, receiveMbps: Int = 100, padding: String? = nil) throws {
        let trimmedAuthentication = authentication.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthentication.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing hysteria2 authentication")
        }
        self.path = "/auth"
        self.method = "POST"
        var headers = [
            "Hysteria-Auth": trimmedAuthentication,
            "Hysteria-CC-RX": String(max(1, receiveMbps))
        ]
        if let padding, !padding.isEmpty {
            headers["Hysteria-Padding"] = padding
        }
        self.headers = headers
    }
}

public struct Hysteria2OpenRequest: Equatable, Sendable {
    public let destinationDescription: String
    public let sni: String
    public let obfuscationPresent: Bool
    public let openBytes: Data

    public var metadata: [String: String] {
        [
            "hysteria2AuthPresent": "true",
            "hysteria2Destination": destinationDescription,
            "hysteria2SNI": sni,
            "hysteria2ObfsPresent": obfuscationPresent ? "true" : "false",
            "hysteria2TCPCommand": "connect"
        ]
    }

    public init(authentication: String, destination: ProxyDestination, sni: String = "", obfuscation: String? = nil) throws {
        guard !authentication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing hysteria2 authentication")
        }
        let trimmedSNI = sni.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = Self.addressString(for: destination)
        self.destinationDescription = Self.destinationDescription(destination)
        self.sni = trimmedSNI
        self.obfuscationPresent = obfuscation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        var bytes = Self.encodeQUICVariableInteger(0x401)
        bytes.append(Self.encodeQUICVariableInteger(UInt64(address.utf8.count)))
        bytes.append(Data(address.utf8))
        bytes.append(Self.encodeQUICVariableInteger(0))
        self.openBytes = bytes
    }

    private static func addressString(for destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port), let .ipv4(host, port):
            return "\(host):\(port)"
        case let .ipv6(address, port):
            return "[\(address)]:\(port)"
        }
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

    private static func encodeQUICVariableInteger(_ value: UInt64) -> Data {
        if value < 0x40 {
            return Data([UInt8(value)])
        }
        if value < 0x4000 {
            let encoded = UInt16(value) | 0x4000
            return Data([UInt8(encoded >> 8), UInt8(encoded & 0xff)])
        }
        if value < 0x4000_0000 {
            let encoded = UInt32(value) | 0x8000_0000
            return Data([
                UInt8((encoded >> 24) & 0xff),
                UInt8((encoded >> 16) & 0xff),
                UInt8((encoded >> 8) & 0xff),
                UInt8(encoded & 0xff)
            ])
        }
        let encoded = value | 0xc000_0000_0000_0000
        return Data([
            UInt8((encoded >> 56) & 0xff),
            UInt8((encoded >> 48) & 0xff),
            UInt8((encoded >> 40) & 0xff),
            UInt8((encoded >> 32) & 0xff),
            UInt8((encoded >> 24) & 0xff),
            UInt8((encoded >> 16) & 0xff),
            UInt8((encoded >> 8) & 0xff),
            UInt8(encoded & 0xff)
        ])
    }
}

public struct Hysteria2StreamOpener<Dialer: QUICStreamDialer>: Sendable {
    private let streamAdapter: QUICStreamTransportAdapter<Dialer>

    public init(streamAdapter: QUICStreamTransportAdapter<Dialer>) {
        self.streamAdapter = streamAdapter
    }

    public func openStream(node: ProxyNode, credential: String, destination: ProxyDestination, metadata: [String: String] = [:]) async throws -> any TransportByteStream {
        try validate(node)
        let authRequest = try Hysteria2AuthRequest(authentication: credential)
        let openRequest = try Hysteria2OpenRequest(
            authentication: credential,
            destination: destination,
            sni: node.tls.serverName ?? node.serverHost
        )
        var requestMetadata = metadata
        requestMetadata["proxyProtocol"] = node.protocolType.rawValue
        requestMetadata["quicServerName"] = node.tls.serverName ?? node.serverHost
        requestMetadata["quicProtocol"] = "hysteria2"
        requestMetadata["quicALPN"] = node.tls.alpn.isEmpty ? "h3" : node.tls.alpn.joined(separator: ",")
        requestMetadata["quicHandshake"] = "native"
        for (key, value) in authRequest.metadata {
            requestMetadata[key] = value
        }
        for (key, value) in openRequest.metadata {
            requestMetadata[key] = value
        }
        let request = TransportRequest(
            host: node.serverHost,
            port: node.serverPort,
            transport: node.transport,
            tls: node.tls.enabled ? node.tls : nil,
            metadata: requestMetadata,
            initialPayload: openRequest.openBytes
        )
        do {
            let stream = try await streamAdapter.openStream(request: request)
            try await validateTCPResponse(from: stream)
            return stream
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .hysteria2 else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard node.transport == .quic else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing hysteria2 server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid hysteria2 server port")
        }
    }

    private func validateTCPResponse(from stream: any TransportByteStream) async throws {
        let status = try await readTCPResponseBytes(1, from: stream)[0]
        let messageLength = Int(try await readQUICVariableInteger(from: stream))
        _ = try await readTCPResponseBytes(messageLength, from: stream)
        let paddingLength = Int(try await readQUICVariableInteger(from: stream))
        _ = try await readTCPResponseBytes(paddingLength, from: stream)
        guard status == 0x00 else {
            throw ProxyProtocolError.remoteClosed
        }
    }

    private func readTCPResponseBytes(_ count: Int, from stream: any TransportByteStream) async throws -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try await stream.read(maxLength: count - data.count), !chunk.isEmpty else {
                throw ProxyProtocolError.remoteClosed
            }
            data.append(chunk)
        }
        return data
    }

    private func readQUICVariableInteger(from stream: any TransportByteStream) async throws -> UInt64 {
        let first = try await readTCPResponseBytes(1, from: stream)[0]
        let prefix = first >> 6
        let byteCount: Int
        switch prefix {
        case 0: byteCount = 1
        case 1: byteCount = 2
        case 2: byteCount = 4
        default: byteCount = 8
        }
        var bytes = Data([first])
        if byteCount > 1 {
            bytes.append(try await readTCPResponseBytes(byteCount - 1, from: stream))
        }
        var value = UInt64(bytes[0] & 0x3f)
        for byte in bytes.dropFirst() {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }

    private func proxyProtocolError(for error: TransportError) -> ProxyProtocolError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration("transport invalid")
        case .dnsFailed:
            return .dnsFailed("transport dns failed")
        case .tcpConnectFailed:
            return .tcpConnectFailed("transport tcp connect failed")
        case .tlsHandshakeFailed:
            return .tlsHandshakeFailed("transport tls handshake failed")
        case let .unsupportedTransport(transport):
            return .unsupportedTransport(transport)
        case .quicHandshakeFailed:
            return .quicHandshakeFailed("transport quic handshake failed")
        case .remoteClosed:
            return .remoteClosed
        case .timeout:
            return .timeout
        }
    }
}

public struct TUICOpenRequest: Equatable, Sendable {
    public let destinationDescription: String
    public let sni: String
    public let openBytes: Data

    public var metadata: [String: String] {
        [
            "tuicUUIDPresent": "true",
            "tuicPasswordPresent": "true",
            "tuicDestination": destinationDescription,
            "tuicSNI": sni
        ]
    }

    public init(credential: String, destination: ProxyDestination, sni: String = "") throws {
        let parts = credential.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic credential")
        }
        let uuid = try Self.uuidBytes(String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines))
        guard !String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing tuic password")
        }

        let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04)
        let trimmedSNI = sni.trimmingCharacters(in: .whitespacesAndNewlines)
        self.destinationDescription = frame.description
        self.sni = trimmedSNI
        var bytes = Data([0x54, 0x55, 0x49, 0x43, 0x05])
        bytes.append(contentsOf: uuid)
        bytes.append(UInt8(trimmedSNI.utf8.count))
        bytes.append(Data(trimmedSNI.utf8))
        bytes.append(frame.bytes)
        self.openBytes = bytes
    }

    private static func uuidBytes(_ value: String) throws -> [UInt8] {
        guard let uuid = UUID(uuidString: value) else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic uuid")
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

private extension Data {
    static func random(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) })
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

enum SHA224 {
    static func hashHex(_ string: String) -> String {
        hash(Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ data: Data) -> [UInt8] {
        var message = Array(data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        message.append(contentsOf: (0..<8).reversed().map { UInt8((bitLength >> UInt64($0 * 8)) & 0xff) })

        var h0: UInt32 = 0xc1059ed8
        var h1: UInt32 = 0x367cd507
        var h2: UInt32 = 0x3070dd17
        var h3: UInt32 = 0xf70e5939
        var h4: UInt32 = 0xffc00b31
        var h5: UInt32 = 0x68581511
        var h6: UInt32 = 0x64f98fa7
        var h7: UInt32 = 0xbefa4fa4

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let offset = chunkStart + index * 4
                words[index] = UInt32(message[offset]) << 24 | UInt32(message[offset + 1]) << 16 | UInt32(message[offset + 2]) << 8 | UInt32(message[offset + 3])
            }
            for index in 16..<64 {
                let s0 = words[index - 15].rotateRight(7) ^ words[index - 15].rotateRight(18) ^ (words[index - 15] >> 3)
                let s1 = words[index - 2].rotateRight(17) ^ words[index - 2].rotateRight(19) ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4
            var f = h5
            var g = h6
            var h = h7

            for index in 0..<64 {
                let sum1 = e.rotateRight(6) ^ e.rotateRight(11) ^ e.rotateRight(25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ sum1 &+ ch &+ SHA224.k[index] &+ words[index]
                let sum0 = a.rotateRight(2) ^ a.rotateRight(13) ^ a.rotateRight(22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = sum0 &+ maj
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
            h5 = h5 &+ f
            h6 = h6 &+ g
            h7 = h7 &+ h
        }

        var digest: [UInt8] = []
        digest.reserveCapacity(28)
        appendBigEndian(h0, to: &digest)
        appendBigEndian(h1, to: &digest)
        appendBigEndian(h2, to: &digest)
        appendBigEndian(h3, to: &digest)
        appendBigEndian(h4, to: &digest)
        appendBigEndian(h5, to: &digest)
        appendBigEndian(h6, to: &digest)
        return digest
    }

    private static func appendBigEndian(_ word: UInt32, to digest: inout [UInt8]) {
        digest.append(UInt8(word >> 24))
        digest.append(UInt8((word >> 16) & 0xff))
        digest.append(UInt8((word >> 8) & 0xff))
        digest.append(UInt8(word & 0xff))
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]
}

private extension UInt32 {
    func rotateRight(_ count: UInt32) -> UInt32 {
        (self >> count) | (self << (32 - count))
    }
}

public struct ProxyRequest: Equatable, Sendable {
    public let node: ProxyNode
    public let destination: ProxyDestination
    public let metadata: [String: String]

    public init(node: ProxyNode, destination: ProxyDestination, metadata: [String: String] = [:]) {
        self.node = node
        self.destination = destination
        self.metadata = metadata
    }
}

public protocol ProxyConnection: Sendable {
    var nodeID: NodeID { get }
    var destination: ProxyDestination { get }
    var initialResponseBytes: [UInt8]? { get }
}

public struct EstablishedProxyConnection: ProxyConnection, Equatable, Sendable {
    public let nodeID: NodeID
    public let destination: ProxyDestination
    public let initialResponseBytes: [UInt8]?

    public init(nodeID: NodeID, destination: ProxyDestination, initialResponseBytes: [UInt8]? = nil) {
        self.nodeID = nodeID
        self.destination = destination
        self.initialResponseBytes = initialResponseBytes
    }
}

public enum ProxyProtocolError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case dnsFailed(String)
    case tcpConnectFailed(String)
    case tlsHandshakeFailed(String)
    case authenticationFailed(String)
    case unsupportedTransport(TransportType)
    case unsupportedProtocol(ProxyProtocolType)
    case protocolHandshakeFailed(String)
    case quicHandshakeFailed(String)
    case udpUnsupported
    case remoteClosed
    case timeout

    public var description: String {
        switch self {
        case .invalidConfiguration:
            return "Invalid configuration"
        case .dnsFailed:
            return "DNS failed"
        case .tcpConnectFailed:
            return "TCP connect failed"
        case .tlsHandshakeFailed:
            return "TLS handshake failed"
        case .authenticationFailed:
            return "Authentication failed"
        case let .unsupportedTransport(transport):
            return "Unsupported transport: \(transport.rawValue)"
        case let .unsupportedProtocol(protocolType):
            return "Unsupported protocol: \(protocolType.rawValue)"
        case .protocolHandshakeFailed:
            return "Protocol handshake failed"
        case .quicHandshakeFailed:
            return "QUIC handshake failed"
        case .udpUnsupported:
            return "UDP unsupported"
        case .remoteClosed:
            return "Remote closed"
        case .timeout:
            return "Timeout"
        }
    }
}

public protocol ProxyAdapter: Sendable {
    var supportedProtocol: ProxyProtocolType { get }
    func connect(request: ProxyRequest) async throws -> any ProxyConnection
}

public struct UnsupportedProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType

    public init(protocolType: ProxyProtocolType) {
        self.supportedProtocol = protocolType
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        throw ProxyProtocolError.unsupportedProtocol(request.node.protocolType)
    }
}

public struct NoopProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType

    public init(protocolType: ProxyProtocolType = .shadowsocks) {
        self.supportedProtocol = protocolType
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        throw ProxyProtocolError.unsupportedProtocol(request.node.protocolType)
    }
}

public struct ProxyAdapterRegistry: Sendable {
    private let adapters: [ProxyProtocolType: any ProxyAdapter]

    public init(adapters: [any ProxyAdapter]) {
        var indexed: [ProxyProtocolType: any ProxyAdapter] = [:]
        for adapter in adapters {
            indexed[adapter.supportedProtocol] = adapter
        }
        self.adapters = indexed
    }

    public func adapter(for protocolType: ProxyProtocolType) -> any ProxyAdapter {
        adapters[protocolType] ?? UnsupportedProxyAdapter(protocolType: protocolType)
    }
}

public struct TransportBackedProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType
    private let transportRegistry: TransportAdapterRegistry

    public init(protocolType: ProxyProtocolType, transportRegistry: TransportAdapterRegistry) {
        self.supportedProtocol = protocolType
        self.transportRegistry = transportRegistry
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        guard request.node.protocolType == supportedProtocol else {
            throw ProxyProtocolError.unsupportedProtocol(request.node.protocolType)
        }

        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request)
        )
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func transportMetadata(for request: ProxyRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        metadata["destination"] = destinationDescription(request.destination)
        return metadata
    }

    private func destinationDescription(_ destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port):
            return "host:\(host):\(port)"
        case let .ipv4(address, port):
            return "ipv4:\(address):\(port)"
        case let .ipv6(address, port):
            return "ipv6:\(address):\(port)"
        }
    }

    private func proxyProtocolError(for error: TransportError) -> ProxyProtocolError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration("transport invalid")
        case .dnsFailed:
            return .dnsFailed("transport dns failed")
        case .tcpConnectFailed:
            return .tcpConnectFailed("transport tcp connect failed")
        case .tlsHandshakeFailed:
            return .tlsHandshakeFailed("transport tls handshake failed")
        case let .unsupportedTransport(transport):
            return .unsupportedTransport(transport)
        case .quicHandshakeFailed:
            return .quicHandshakeFailed("transport quic handshake failed")
        case .remoteClosed:
            return .remoteClosed
        case .timeout:
            return .timeout
        }
    }
}

private func applyTransportOptions(from node: ProxyNode, to metadata: inout [String: String]) {
    if let webSocket = node.transportOptions.webSocket {
        if let host = webSocket.host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["webSocketHost"] = host
        }
        metadata["webSocketPath"] = webSocket.path
    }
    if let http2 = node.transportOptions.http2 {
        if let authority = http2.authority, !authority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["http2Authority"] = authority
        }
        metadata["http2Path"] = http2.path
    }
    if let grpc = node.transportOptions.grpc {
        if let authority = grpc.authority, !authority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["grpcAuthority"] = authority
        }
        metadata["grpcService"] = grpc.service
    }
}

public struct VMessProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .vmess
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let openRequest = try VMessOpenRequest(userID: credential, destination: request.destination)
        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request, openRequest: openRequest),
            initialPayload: openRequest.openBytes
        )
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .vmess else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing vmess server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid vmess server port")
        }
        guard node.transport == .tcp || node.transport == .webSocket || node.transport == .http2 || node.transport == .grpc else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: VMessOpenRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        applyTransportOptions(from: request.node, to: &metadata)
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }

    private func proxyProtocolError(for error: TransportError) -> ProxyProtocolError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration("transport invalid")
        case .dnsFailed:
            return .dnsFailed("transport dns failed")
        case .tcpConnectFailed:
            return .tcpConnectFailed("transport tcp connect failed")
        case .tlsHandshakeFailed:
            return .tlsHandshakeFailed("transport tls handshake failed")
        case let .unsupportedTransport(transport):
            return .unsupportedTransport(transport)
        case .quicHandshakeFailed:
            return .quicHandshakeFailed("transport quic handshake failed")
        case .remoteClosed:
            return .remoteClosed
        case .timeout:
            return .timeout
        }
    }
}

public struct VLESSProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .vless
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let openRequest = try VLESSOpenRequest(userID: credential, destination: request.destination)
        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request, openRequest: openRequest),
            initialPayload: openRequest.openBytes
        )
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .vless else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing vless server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid vless server port")
        }
        guard node.transport == .tcp || node.transport == .webSocket || node.transport == .http2 || node.transport == .grpc else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: VLESSOpenRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        applyTransportOptions(from: request.node, to: &metadata)
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }

    private func proxyProtocolError(for error: TransportError) -> ProxyProtocolError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration("transport invalid")
        case .dnsFailed:
            return .dnsFailed("transport dns failed")
        case .tcpConnectFailed:
            return .tcpConnectFailed("transport tcp connect failed")
        case .tlsHandshakeFailed:
            return .tlsHandshakeFailed("transport tls handshake failed")
        case let .unsupportedTransport(transport):
            return .unsupportedTransport(transport)
        case .quicHandshakeFailed:
            return .quicHandshakeFailed("transport quic handshake failed")
        case .remoteClosed:
            return .remoteClosed
        case .timeout:
            return .timeout
        }
    }
}

public struct TrojanProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .trojan
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let openRequest = try TrojanOpenRequest(
            password: credential,
            destination: request.destination,
            serverName: request.node.tls.serverName ?? ""
        )
        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request, openRequest: openRequest),
            initialPayload: openRequest.openBytes
        )
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .trojan else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing trojan server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid trojan server port")
        }
        guard node.transport == .tcp || node.transport == .webSocket || node.transport == .http2 || node.transport == .grpc else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: TrojanOpenRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        applyTransportOptions(from: request.node, to: &metadata)
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }

    private func proxyProtocolError(for error: TransportError) -> ProxyProtocolError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration("transport invalid")
        case .dnsFailed:
            return .dnsFailed("transport dns failed")
        case .tcpConnectFailed:
            return .tcpConnectFailed("transport tcp connect failed")
        case .tlsHandshakeFailed:
            return .tlsHandshakeFailed("transport tls handshake failed")
        case let .unsupportedTransport(transport):
            return .unsupportedTransport(transport)
        case .quicHandshakeFailed:
            return .quicHandshakeFailed("transport quic handshake failed")
        case .remoteClosed:
            return .remoteClosed
        case .timeout:
            return .timeout
        }
    }
}

public struct Hysteria2ProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .hysteria2
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let openRequest = try Hysteria2OpenRequest(
            authentication: credential,
            destination: request.destination,
            sni: request.node.tls.serverName ?? request.node.serverHost
        )
        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request, openRequest: openRequest),
            initialPayload: openRequest.openBytes
        )
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .hysteria2 else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard node.transport == .quic else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing hysteria2 server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid hysteria2 server port")
        }
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: Hysteria2OpenRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        if let realm = request.node.hysteria2?.realm {
            metadata["hysteria2RealmPresent"] = "true"
            metadata["hysteria2RealmNamePresent"] = "true"
            metadata["hysteria2RealmTLS"] = realm.useTLS ? "true" : "false"
            metadata["hysteria2RealmStunServerCount"] = String(realm.stunServers.count)
        }
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }

    private func proxyProtocolError(for error: TransportError) -> ProxyProtocolError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration("transport invalid")
        case .dnsFailed:
            return .dnsFailed("transport dns failed")
        case .tcpConnectFailed:
            return .tcpConnectFailed("transport tcp connect failed")
        case .tlsHandshakeFailed:
            return .tlsHandshakeFailed("transport tls handshake failed")
        case let .unsupportedTransport(transport):
            return .unsupportedTransport(transport)
        case .quicHandshakeFailed:
            return .quicHandshakeFailed("transport quic handshake failed")
        case .remoteClosed:
            return .remoteClosed
        case .timeout:
            return .timeout
        }
    }
}

public struct TUICProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .tuic
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let openRequest = try TUICOpenRequest(
            credential: credential,
            destination: request.destination,
            sni: request.node.tls.serverName ?? request.node.serverHost
        )
        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request, openRequest: openRequest),
            initialPayload: openRequest.openBytes
        )
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .tuic else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard node.transport == .quic else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing tuic server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic server port")
        }
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: TUICOpenRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }

    private func proxyProtocolError(for error: TransportError) -> ProxyProtocolError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration("transport invalid")
        case .dnsFailed:
            return .dnsFailed("transport dns failed")
        case .tcpConnectFailed:
            return .tcpConnectFailed("transport tcp connect failed")
        case .tlsHandshakeFailed:
            return .tlsHandshakeFailed("transport tls handshake failed")
        case let .unsupportedTransport(transport):
            return .unsupportedTransport(transport)
        case .quicHandshakeFailed:
            return .quicHandshakeFailed("transport quic handshake failed")
        case .remoteClosed:
            return .remoteClosed
        case .timeout:
            return .timeout
        }
    }
}

public protocol ProxyCredentialResolver: Sendable {
    func credential(for reference: CredentialReference) throws -> String
}

public typealias ShadowsocksCredentialResolver = ProxyCredentialResolver

public struct MissingProxyCredentialResolver: ProxyCredentialResolver {
    public init() {}

    public func credential(for reference: CredentialReference) throws -> String {
        throw ProxyProtocolError.invalidConfiguration("missing proxy credential material")
    }
}

public typealias MissingShadowsocksCredentialResolver = MissingProxyCredentialResolver

public struct ShadowsocksProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .shadowsocks
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let streamRequest = try ShadowsocksStreamRequest(
            credential: credential,
            destination: request.destination,
            salt: Data.random(count: try ShadowsocksStreamRequest.saltLength(forCredential: credential))
        )
        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request, streamRequest: streamRequest),
            initialPayload: streamRequest.openBytes
        )
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw proxyProtocolError(for: error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .shadowsocks else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing shadowsocks server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks server port")
        }
        guard !node.credentialReference.account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing shadowsocks credential account")
        }
        guard node.transport == .tcp else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
    }

    private func transportMetadata(for request: ProxyRequest, streamRequest: ShadowsocksStreamRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        metadata["destination"] = destinationDescription(request.destination)
        for (key, value) in streamRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }

    private func destinationDescription(_ destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port):
            return "host:\(host):\(port)"
        case let .ipv4(address, port):
            return "ipv4:\(address):\(port)"
        case let .ipv6(address, port):
            return "ipv6:\(address):\(port)"
        }
    }

    private func proxyProtocolError(for error: TransportError) -> ProxyProtocolError {
        switch error {
        case .invalidConfiguration:
            return .invalidConfiguration("transport invalid")
        case .dnsFailed:
            return .dnsFailed("transport dns failed")
        case .tcpConnectFailed:
            return .tcpConnectFailed("transport tcp connect failed")
        case .tlsHandshakeFailed:
            return .tlsHandshakeFailed("transport tls handshake failed")
        case let .unsupportedTransport(transport):
            return .unsupportedTransport(transport)
        case .quicHandshakeFailed:
            return .quicHandshakeFailed("transport quic handshake failed")
        case .remoteClosed:
            return .remoteClosed
        case .timeout:
            return .timeout
        }
    }
}

public extension ShadowsocksProxyAdapter where CredentialResolver == MissingProxyCredentialResolver {
    init(transportRegistry: TransportAdapterRegistry) {
        self.init(transportRegistry: transportRegistry, credentialResolver: MissingProxyCredentialResolver())
    }
}
