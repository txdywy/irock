import CryptoKit
import Foundation
import IrockCore

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

public struct ShadowsocksUDPDatagramRequest: Equatable, Sendable {
    public let cipher: String
    public let addressFrame: Data
    public let packet: Data

    public var addressFrameHex: String {
        addressFrame.hexString
    }

    public var metadata: [String: String] {
        [
            "shadowsocksCipher": cipher,
            "shadowsocksUDPAddressFrameHex": addressFrameHex,
            "shadowsocksUDPPacketHex": packet.hexString
        ]
    }

    public init(credential: String, destination: ProxyDestination, payload: Data, salt: Data) throws {
        let parsed = try ShadowsocksStreamRequest.parseCredential(credential)
        guard let cipher = ShadowsocksCipher.lookup(method: parsed.method) else {
            throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks method")
        }
        guard cipher.kind == .legacyAEAD else {
            throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks udp method")
        }
        let streamRequest = try ShadowsocksStreamRequest(credential: credential, destination: destination, salt: salt)
        let subkey = try cipher.deriveSubkey(password: parsed.password, salt: salt)
        let plaintext = streamRequest.addressFrame + payload
        self.cipher = cipher.method
        self.addressFrame = streamRequest.addressFrame
        self.packet = salt + (try cipher.seal(plaintext, using: subkey, nonceValue: 0))
    }

    public static func decryptPayload(_ packet: Data, credential: String) throws -> Data {
        let parsed = try ShadowsocksStreamRequest.parseCredential(credential)
        guard let cipher = ShadowsocksCipher.lookup(method: parsed.method) else {
            throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks method")
        }
        guard cipher.kind == .legacyAEAD else {
            throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks udp method")
        }
        guard packet.count > cipher.saltLength + 16 else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks udp packet")
        }
        let salt = Data(packet.prefix(cipher.saltLength))
        let encryptedPayload = Data(packet.dropFirst(cipher.saltLength))
        let subkey = try cipher.deriveSubkey(password: parsed.password, salt: salt)
        return try cipher.open(encryptedPayload, using: subkey, nonceValue: 0)
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
        try destination.shadowsocksAddressFrame
    }
}
