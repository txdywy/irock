import CryptoKit
import Foundation

enum ShadowsocksAEADFamily: Equatable {
    case aes128GCM
    case aes256GCM
    case chacha20Poly1305
}

enum ShadowsocksCipherKind: Equatable {
    case legacyAEAD
    case shadowsocks2022
}

struct ShadowsocksCipher: Equatable {
    let method: String
    let keyLength: Int
    let saltLength: Int
    let family: ShadowsocksAEADFamily
    let kind: ShadowsocksCipherKind

    static func lookup(method: String) -> ShadowsocksCipher? {
        switch method.lowercased() {
        case "aes-256-gcm":
            return ShadowsocksCipher(method: "aes-256-gcm", keyLength: 32, saltLength: 32, family: .aes256GCM, kind: .legacyAEAD)
        case "2022-blake3-aes-128-gcm":
            return ShadowsocksCipher(method: "2022-blake3-aes-128-gcm", keyLength: 16, saltLength: 16, family: .aes128GCM, kind: .shadowsocks2022)
        case "2022-blake3-aes-256-gcm":
            return ShadowsocksCipher(method: "2022-blake3-aes-256-gcm", keyLength: 32, saltLength: 32, family: .aes256GCM, kind: .shadowsocks2022)
        case "2022-blake3-chacha20-poly1305":
            return ShadowsocksCipher(method: "2022-blake3-chacha20-poly1305", keyLength: 32, saltLength: 32, family: .chacha20Poly1305, kind: .shadowsocks2022)
        default:
            return nil
        }
    }

    static func supportsKnownCredential(_ credential: String) throws -> Bool {
        let parsed = try ShadowsocksStreamRequest.parseCredential(credential)
        guard let cipher = lookup(method: parsed.method) else { return false }
        guard cipher.kind == .shadowsocks2022 else { return true }
        return (try? cipher.preSharedKey(password: parsed.password)) != nil
    }

    func deriveSubkey(password: String, salt: Data) throws -> SymmetricKey {
        guard salt.count == saltLength else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks salt")
        }
        switch kind {
        case .legacyAEAD:
            let masterKey = SymmetricKey(data: ShadowsocksStreamRequest.evpBytesToKey(password: Data(password.utf8), keyLength: keyLength))
            return HKDF<Insecure.SHA1>.deriveKey(inputKeyMaterial: masterKey, salt: salt, info: Data("ss-subkey".utf8), outputByteCount: keyLength)
        case .shadowsocks2022:
            let psk = try preSharedKey(password: password)
            let material = psk + salt
            let key = InternalBLAKE3.deriveKey(context: "shadowsocks 2022 session subkey", material: material, outputByteCount: keyLength)
            return SymmetricKey(data: key)
        }
    }

    private func preSharedKey(password: String) throws -> Data {
        var normalized = password.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let key = Data(base64Encoded: normalized), key.count == keyLength else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks 2022 key")
        }
        return key
    }

    func seal(_ data: Data, using key: SymmetricKey, nonceValue: UInt64) throws -> Data {
        switch family {
        case .aes128GCM, .aes256GCM:
            let sealed = try AES.GCM.seal(data, using: key, nonce: AES.GCM.Nonce(data: nonceBytes(nonceValue)))
            return sealed.ciphertext + sealed.tag
        case .chacha20Poly1305:
            let sealed = try ChaChaPoly.seal(data, using: key, nonce: ChaChaPoly.Nonce(data: nonceBytes(nonceValue)))
            return sealed.ciphertext + sealed.tag
        }
    }

    func open(_ data: Data, using key: SymmetricKey, nonceValue: UInt64) throws -> Data {
        guard data.count >= 16 else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks encrypted frame")
        }
        let ciphertext = data.prefix(data.count - 16)
        let tag = data.suffix(16)
        switch family {
        case .aes128GCM, .aes256GCM:
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceBytes(nonceValue)), ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: key)
        case .chacha20Poly1305:
            let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonceBytes(nonceValue)), ciphertext: ciphertext, tag: tag)
            return try ChaChaPoly.open(box, using: key)
        }
    }

    private func nonceBytes(_ value: UInt64) -> Data {
        var bytes = Data(repeating: 0, count: 12)
        var current = value
        for index in 0..<8 {
            bytes[index] = UInt8(current & 0xff)
            current >>= 8
        }
        return bytes
    }
}
