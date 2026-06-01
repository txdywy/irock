import Foundation
import IrockCore

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
