import Darwin
import Foundation
import IrockCore

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

extension ProxyDestination {
    var shadowsocksAddressFrame: Data {
        get throws {
            switch self {
            case let .host(host, port):
                let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
                let hostBytes = Data(normalizedHost.utf8)
                guard !hostBytes.isEmpty, hostBytes.count <= 255 else {
                    throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks host")
                }
                return try Data([0x03, UInt8(hostBytes.count)]) + hostBytes + shadowsocksPortBytes(port)
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
                return try Data([0x01]) + Data(bytes) + shadowsocksPortBytes(port)
            case let .ipv6(address, port):
                let parts = address.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 8 else {
                    throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks ipv6 destination")
                }
                let bytes = try parts.flatMap { part -> [UInt8] in
                    guard part.count <= 4, let value = UInt16(part, radix: 16) else {
                        throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks ipv6 destination")
                    }
                    return [UInt8(value >> 8), UInt8(value & 0xff)]
                }
                return try Data([0x04]) + Data(bytes) + shadowsocksPortBytes(port)
        }
    }
}

    private func shadowsocksPortBytes(_ port: Int) throws -> Data {
        guard (1...65_535).contains(port) else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks destination port")
        }
        return Data([UInt8(port >> 8), UInt8(port & 0xff)])
    }
}
