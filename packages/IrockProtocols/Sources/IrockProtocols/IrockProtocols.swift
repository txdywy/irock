import CryptoKit
import Foundation
import IrockCore
import IrockTransport

public enum ProxyDestination: Equatable, Sendable {
    case host(String, port: Int)
    case ipv4(String, port: Int)
    case ipv6(String, port: Int)
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

    public init(credential: String, destination: ProxyDestination, salt: Data) throws {
        let parsed = try Self.parseCredential(credential)
        guard parsed.method == "aes-256-gcm" else {
            throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks method")
        }
        guard salt.count == 32 else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks salt")
        }

        self.cipher = parsed.method
        self.addressFrame = try Self.addressFrame(for: destination)
        let masterKey = SymmetricKey(data: Self.evpBytesToKey(password: Data(parsed.password.utf8), keyLength: 32))
        let subkey = HKDF<Insecure.SHA1>.deriveKey(inputKeyMaterial: masterKey, salt: salt, info: Data("ss-subkey".utf8), outputByteCount: 32)
        let length = Data([UInt8(addressFrame.count >> 8), UInt8(addressFrame.count & 0xff)])
        let encryptedLength = try Self.seal(length, using: subkey, nonceValue: 0)
        let encryptedPayload = try Self.seal(addressFrame, using: subkey, nonceValue: 1)
        self.openBytes = salt + encryptedLength + encryptedPayload
    }

    private static func seal(_ data: Data, using key: SymmetricKey, nonceValue: UInt64) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key, nonce: AES.GCM.Nonce(data: nonceBytes(nonceValue)))
        return sealed.ciphertext + sealed.tag
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

    private static func evpBytesToKey(password: Data, keyLength: Int) -> Data {
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

    private static func parseCredential(_ credential: String) throws -> (method: String, password: String) {
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

        let destinationDescription = Self.destinationDescription(destination)
        self.destinationDescription = destinationDescription
        self.security = normalizedSecurity
        self.alterID = alterID
        self.openBytes = Data("vmess-foundation:\(destinationDescription):\(normalizedSecurity):\(alterID)".utf8)
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

        let destinationDescription = Self.destinationDescription(destination)
        self.destinationDescription = destinationDescription
        self.security = normalizedSecurity
        self.flow = flow.trimmingCharacters(in: .whitespacesAndNewlines)
        self.openBytes = Data("vless-foundation:\(destinationDescription):\(normalizedSecurity):\(self.flow)".utf8)
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

        let destinationDescription = Self.destinationDescription(destination)
        self.destinationDescription = destinationDescription
        self.serverName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.openBytes = Data("trojan-foundation:\(destinationDescription):\(self.serverName)".utf8)
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
            "hysteria2ObfsPresent": obfuscationPresent ? "true" : "false"
        ]
    }

    public init(authentication: String, destination: ProxyDestination, sni: String = "", obfuscation: String? = nil) throws {
        guard !authentication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing hysteria2 authentication")
        }
        let destinationDescription = Self.destinationDescription(destination)
        self.destinationDescription = destinationDescription
        self.sni = sni.trimmingCharacters(in: .whitespacesAndNewlines)
        self.obfuscationPresent = obfuscation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        self.openBytes = Data("hysteria2-foundation:\(destinationDescription):\(self.sni):auth-present:\(obfuscationPresent ? "true" : "false")".utf8)
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
        guard UUID(uuidString: String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic uuid")
        }
        guard !String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing tuic password")
        }

        let destinationDescription = Self.destinationDescription(destination)
        self.destinationDescription = destinationDescription
        self.sni = sni.trimmingCharacters(in: .whitespacesAndNewlines)
        self.openBytes = Data("tuic-foundation:\(destinationDescription):\(self.sni):uuid-present:password-present".utf8)
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

public struct VMessProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .vmess
    private let transportRegistry: TransportAdapterRegistry

    public init(transportRegistry: TransportAdapterRegistry) {
        self.transportRegistry = transportRegistry
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let openRequest = try VMessOpenRequest(userID: request.node.credentialReference.account, destination: request.destination)
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
        _ = try VMessOpenRequest(userID: node.credentialReference.account, destination: .host("validation.local", port: 1))
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: VMessOpenRequest) -> [String: String] {
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

public struct VLESSProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .vless
    private let transportRegistry: TransportAdapterRegistry

    public init(transportRegistry: TransportAdapterRegistry) {
        self.transportRegistry = transportRegistry
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let openRequest = try VLESSOpenRequest(userID: request.node.credentialReference.account, destination: request.destination)
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
        _ = try VLESSOpenRequest(userID: node.credentialReference.account, destination: .host("validation.local", port: 1))
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: VLESSOpenRequest) -> [String: String] {
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

public struct TrojanProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .trojan
    private let transportRegistry: TransportAdapterRegistry

    public init(transportRegistry: TransportAdapterRegistry) {
        self.transportRegistry = transportRegistry
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let openRequest = try TrojanOpenRequest(
            password: request.node.credentialReference.account,
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
        _ = try TrojanOpenRequest(password: node.credentialReference.account, destination: .host("validation.local", port: 1), serverName: node.tls.serverName ?? "")
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: TrojanOpenRequest) -> [String: String] {
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

public struct Hysteria2ProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .hysteria2
    private let transportRegistry: TransportAdapterRegistry

    public init(transportRegistry: TransportAdapterRegistry) {
        self.transportRegistry = transportRegistry
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let openRequest = try Hysteria2OpenRequest(
            authentication: request.node.credentialReference.account,
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
        _ = try Hysteria2OpenRequest(authentication: node.credentialReference.account, destination: .host("validation.local", port: 1), sni: node.tls.serverName ?? node.serverHost)
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: Hysteria2OpenRequest) -> [String: String] {
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

public struct TUICProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .tuic
    private let transportRegistry: TransportAdapterRegistry

    public init(transportRegistry: TransportAdapterRegistry) {
        self.transportRegistry = transportRegistry
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let openRequest = try TUICOpenRequest(
            credential: request.node.credentialReference.account,
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
        _ = try TUICOpenRequest(credential: node.credentialReference.account, destination: .host("validation.local", port: 1), sni: node.tls.serverName ?? node.serverHost)
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

public protocol ShadowsocksCredentialResolver: Sendable {
    func credential(for reference: CredentialReference) throws -> String
}

public struct MissingShadowsocksCredentialResolver: ShadowsocksCredentialResolver {
    public init() {}

    public func credential(for reference: CredentialReference) throws -> String {
        throw ProxyProtocolError.invalidConfiguration("missing shadowsocks credential material")
    }
}

public struct ShadowsocksProxyAdapter<CredentialResolver: ShadowsocksCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .shadowsocks
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let streamRequest = try ShadowsocksStreamRequest(
            credential: credentialResolver.credential(for: request.node.credentialReference),
            destination: request.destination,
            salt: Data.random(count: 32)
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

public extension ShadowsocksProxyAdapter where CredentialResolver == MissingShadowsocksCredentialResolver {
    init(transportRegistry: TransportAdapterRegistry) {
        self.init(transportRegistry: transportRegistry, credentialResolver: MissingShadowsocksCredentialResolver())
    }
}
