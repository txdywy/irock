import CryptoKit
import Darwin
import Foundation
import CIrockNativeHysteria2Runtime
import CNgtcp2
import CNgtcp2CryptoOpenSSL
import CNghttp3

public struct NativeHysteria2RuntimeInfo: Equatable, Sendable {
    public let ngtcp2Version: String
    public let nghttp3Version: String

    public init(ngtcp2Version: String, nghttp3Version: String) {
        self.ngtcp2Version = ngtcp2Version
        self.nghttp3Version = nghttp3Version
    }
}

public struct NativeHysteria2ConnectedUDPPath: Equatable, Sendable {
    public let fileDescriptor: Int32
    public let remotePort: Int

    public init(fileDescriptor: Int32, remotePort: Int) throws {
        guard fileDescriptor >= 0 else {
            throw NativeHysteria2Error.invalidConfiguration("invalid connected udp socket")
        }
        guard (1...65_535).contains(remotePort) else {
            throw NativeHysteria2Error.invalidConfiguration("invalid connected udp remote port")
        }
        self.fileDescriptor = fileDescriptor
        self.remotePort = remotePort
    }
}

public struct NativeHysteria2ClientConfiguration: Equatable, Sendable {
    public let serverHost: String
    public let serverPort: Int
    public let serverName: String
    public let alpn: [String]
    public let allowInsecure: Bool
    public let connectedUDPPath: NativeHysteria2ConnectedUDPPath?

    public init(serverHost: String, serverPort: Int, serverName: String? = nil, alpn: [String] = ["h3"], allowInsecure: Bool = false, connectedUDPPath: NativeHysteria2ConnectedUDPPath? = nil) throws {
        let trimmedHost = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing server host")
        }
        guard (1...65_535).contains(serverPort) else {
            throw NativeHysteria2Error.invalidConfiguration("invalid server port")
        }
        let resolvedServerName = (serverName ?? trimmedHost).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedServerName.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing server name")
        }
        let resolvedALPN = alpn.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !resolvedALPN.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing alpn")
        }
        self.serverHost = trimmedHost
        self.serverPort = serverPort
        self.serverName = resolvedServerName
        self.alpn = resolvedALPN
        self.allowInsecure = allowInsecure
        self.connectedUDPPath = connectedUDPPath
    }
}

public enum NativeHysteria2RealmPunchPacketType: UInt8, Equatable, Sendable {
    case hello = 0x01
    case ack = 0x02
}

public struct NativeHysteria2RealmPunchMetadata: Equatable, Sendable {
    public let nonce: String
    public let obfs: String
    let nonceBytes: Data
    let obfsBytes: Data

    public init(nonce: String, obfs: String) throws {
        let nonceBytes = try Self.hexData(nonce, byteCount: 16, name: "nonce")
        let obfsBytes = try Self.hexData(obfs, byteCount: 32, name: "obfs")
        self.nonce = nonce.lowercased()
        self.obfs = obfs.lowercased()
        self.nonceBytes = nonceBytes
        self.obfsBytes = obfsBytes
    }

    private static func hexData(_ text: String, byteCount: Int, name: String) throws -> Data {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == byteCount * 2 else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm punch \(name)")
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)
        var index = value.startIndex
        while index < value.endIndex {
            let nextIndex = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<nextIndex], radix: 16) else {
                throw NativeHysteria2Error.invalidConfiguration("invalid realm punch \(name)")
            }
            bytes.append(byte)
            index = nextIndex
        }
        return Data(bytes)
    }
}

public struct NativeHysteria2RealmPunchPacket: Equatable, Sendable {
    public let type: NativeHysteria2RealmPunchPacketType
    public let paddingLength: Int

    public static func encode(type: NativeHysteria2RealmPunchPacketType, metadata: NativeHysteria2RealmPunchMetadata, salt: Data, padding: Data) throws -> Data {
        guard salt.count == 8 else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm punch salt")
        }
        guard padding.count <= 1024 else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm punch padding")
        }
        var plain = Data("HYRLMv1\0".utf8)
        plain.append(type.rawValue)
        plain.append(metadata.nonceBytes)
        plain.append(padding)
        return salt + xorRealmPunchPayload(plain, metadata: metadata, salt: salt)
    }

    public static func decode(_ packet: Data, metadata: NativeHysteria2RealmPunchMetadata) throws -> NativeHysteria2RealmPunchPacket {
        guard (33...1057).contains(packet.count) else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm punch packet length")
        }
        let salt = packet.prefix(8)
        let plain = xorRealmPunchPayload(packet.dropFirst(8), metadata: metadata, salt: salt)
        guard plain.count >= 25, plain.prefix(8) == Data("HYRLMv1\0".utf8) else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm punch magic")
        }
        guard let type = NativeHysteria2RealmPunchPacketType(rawValue: plain[plain.index(plain.startIndex, offsetBy: 8)]) else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm punch type")
        }
        let nonceStart = plain.index(plain.startIndex, offsetBy: 9)
        let nonceEnd = plain.index(nonceStart, offsetBy: 16)
        guard plain[nonceStart..<nonceEnd] == metadata.nonceBytes else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm punch nonce")
        }
        return NativeHysteria2RealmPunchPacket(type: type, paddingLength: plain.count - 25)
    }

    private static func xorRealmPunchPayload(_ payload: Data.SubSequence, metadata: NativeHysteria2RealmPunchMetadata, salt: Data.SubSequence) -> Data {
        let mask = Data(SHA256.hash(data: metadata.obfsBytes + salt))
        return Data(payload.enumerated().map { index, byte in byte ^ mask[index % mask.count] })
    }
}

public struct NativeHysteria2RealmConfiguration: Equatable, Sendable {
    public let rendezvousBaseURL: URL
    public let realmID: String
    public let token: String
    public let stunServers: [String]
    public let localPort: Int?

    public init(rendezvousBaseURL: URL, realmID: String, token: String, stunServers: [String], localPort: Int? = nil) throws {
        let trimmedRealmID = realmID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rendezvousBaseURL.scheme == "https" || rendezvousBaseURL.scheme == "http" else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm rendezvous scheme")
        }
        guard rendezvousBaseURL.host != nil else {
            throw NativeHysteria2Error.invalidConfiguration("missing realm rendezvous host")
        }
        guard !trimmedRealmID.isEmpty, !trimmedRealmID.contains("/") else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm id")
        }
        guard !trimmedToken.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing realm token")
        }
        if let localPort {
            guard (1...65_535).contains(localPort) else {
                throw NativeHysteria2Error.invalidConfiguration("invalid realm local port")
            }
        }
        let resolvedSTUNServers = stunServers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !resolvedSTUNServers.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing realm stun servers")
        }
        self.rendezvousBaseURL = rendezvousBaseURL
        self.realmID = trimmedRealmID
        self.token = trimmedToken
        self.stunServers = resolvedSTUNServers
        self.localPort = localPort
    }
}

public struct NativeHysteria2RealmRendezvousResponse: Equatable, Sendable {
    public let addresses: [String]
    public let metadata: NativeHysteria2RealmPunchMetadata
}

public struct NativeHysteria2RealmResolver: Sendable {
    public typealias MetadataGenerator = @Sendable () throws -> NativeHysteria2RealmPunchMetadata
    public typealias UDPSocketBinder = @Sendable (Int?) throws -> Int32
    public typealias STUNDiscoverer = @Sendable (Int32, [String]) async throws -> [String]
    public typealias RendezvousConnector = @Sendable (String, [String], NativeHysteria2RealmPunchMetadata) async throws -> NativeHysteria2RealmRendezvousResponse
    public typealias Puncher = @Sendable (Int32, [String], [String], NativeHysteria2RealmPunchMetadata) async throws -> NativeHysteria2ConnectedUDPPath

    private let metadataGenerator: MetadataGenerator
    private let udpSocketBinder: UDPSocketBinder
    private let stunDiscoverer: STUNDiscoverer
    private let rendezvousConnector: RendezvousConnector
    private let puncher: Puncher

    public init(configuration: NativeHysteria2RealmConfiguration) {
        self.metadataGenerator = { try Self.randomMetadata() }
        self.udpSocketBinder = { try Self.bindUDPSocket(localPort: $0) }
        self.stunDiscoverer = { try await Self.discoverSTUNAddresses(fd: $0, servers: $1) }
        let rendezvousClient = NativeHysteria2RealmRendezvousClient(baseURL: configuration.rendezvousBaseURL, token: configuration.token)
        self.rendezvousConnector = { realmID, localAddresses, metadata in
            try await rendezvousClient.connect(realmID: realmID, localAddresses: localAddresses, metadata: metadata)
        }
        self.puncher = { try await Self.punch(fd: $0, localAddresses: $1, peerAddresses: $2, metadata: $3) }
    }

    public init(
        metadataGenerator: @escaping MetadataGenerator,
        udpSocketBinder: @escaping UDPSocketBinder,
        stunDiscoverer: @escaping STUNDiscoverer,
        rendezvousConnector: @escaping RendezvousConnector,
        puncher: @escaping Puncher
    ) {
        self.metadataGenerator = metadataGenerator
        self.udpSocketBinder = udpSocketBinder
        self.stunDiscoverer = stunDiscoverer
        self.rendezvousConnector = rendezvousConnector
        self.puncher = puncher
    }

    public func resolve(configuration: NativeHysteria2RealmConfiguration) async throws -> NativeHysteria2ConnectedUDPPath {
        let fd = try udpSocketBinder(configuration.localPort)
        let localAddresses = try await stunDiscoverer(fd, configuration.stunServers)
        let metadata = try metadataGenerator()
        let rendezvousResponse = try await rendezvousConnector(configuration.realmID, localAddresses, metadata)
        return try await puncher(fd, localAddresses, rendezvousResponse.addresses, rendezvousResponse.metadata)
    }

    private static func randomMetadata() throws -> NativeHysteria2RealmPunchMetadata {
        try NativeHysteria2RealmPunchMetadata(nonce: randomHex(byteCount: 16), obfs: randomHex(byteCount: 32))
    }

    private static func randomHex(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<byteCount).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }

    private static func bindUDPSocket(localPort: Int?) throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw NativeHysteria2Error.networkFailed("realm udp socket failed")
        }
        if let localPort {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(localPort).bigEndian
            address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result != 0 {
                Darwin.close(fd)
                throw NativeHysteria2Error.networkFailed("realm udp bind failed")
            }
        }
        return fd
    }

    private static func discoverSTUNAddresses(fd: Int32, servers: [String]) async throws -> [String] {
        guard !servers.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing realm stun servers")
        }
        var addresses: [String] = []
        for server in servers {
            if let address = try? await discoverSTUNAddress(fd: fd, server: server) {
                addresses.append(address)
            }
        }
        guard !addresses.isEmpty else {
            throw NativeHysteria2Error.networkFailed("realm stun discovery failed")
        }
        return addresses
    }

    private static func punch(fd: Int32, localAddresses: [String], peerAddresses: [String], metadata: NativeHysteria2RealmPunchMetadata) async throws -> NativeHysteria2ConnectedUDPPath {
        guard let peerAddress = peerAddresses.compactMap(parseHostPort).first else {
            throw NativeHysteria2Error.invalidConfiguration("missing realm peer addresses")
        }
        let packet = try NativeHysteria2RealmPunchPacket.encode(type: .hello, metadata: metadata, salt: randomBytes(count: 8), padding: randomBytes(count: 0))
        for _ in 0..<100 {
            try sendUDP(packet, fd: fd, host: peerAddress.host, port: peerAddress.port)
            if let received = try receiveUDPPunch(fd: fd, metadata: metadata), let remote = parseHostPort(received.address) {
                try connectUDP(fd: fd, host: remote.host, port: remote.port)
                return try NativeHysteria2ConnectedUDPPath(fileDescriptor: fd, remotePort: remote.port)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NativeHysteria2Error.networkFailed("realm punch timed out")
    }
}

private func randomBytes(count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
}

private func parseHostPort(_ text: String) -> (host: String, port: Int)? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("[") {
        guard let close = value.firstIndex(of: "]"), value[value.index(after: close)..<value.endIndex].hasPrefix(":"), let port = Int(value[value.index(close, offsetBy: 2)..<value.endIndex]), (1...65_535).contains(port) else { return nil }
        return (String(value[value.index(after: value.startIndex)..<close]), port)
    }
    let parts = value.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, let port = Int(parts[1]), (1...65_535).contains(port) else { return nil }
    return (String(parts[0]), port)
}

private func discoverSTUNAddress(fd: Int32, server: String) async throws -> String {
    guard let serverAddress = parseHostPort(server) ?? parseHostPort("\(server):3478") else {
        throw NativeHysteria2Error.invalidConfiguration("invalid stun server")
    }
    let transactionID = randomBytes(count: 12)
    var request = Data([0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xa4, 0x42])
    request.append(transactionID)
    try sendUDP(request, fd: fd, host: serverAddress.host, port: serverAddress.port)
    for _ in 0..<40 {
        if let mapped = try receiveSTUNAddress(fd: fd, transactionID: transactionID) {
            return mapped
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw NativeHysteria2Error.networkFailed("stun response timed out")
}

private func receiveSTUNAddress(fd: Int32, transactionID: Data) throws -> String? {
    var buffer = [UInt8](repeating: 0, count: 1500)
    let received = Darwin.recv(fd, &buffer, buffer.count, 0)
    if received < 0 {
        if errno == EAGAIN || errno == EWOULDBLOCK { return nil }
        throw NativeHysteria2Error.networkFailed("udp receive failed")
    }
    guard received >= 20 else { return nil }
    let data = Data(buffer.prefix(received))
    guard data[0] == 0x01, data[1] == 0x01, data[4..<8] == Data([0x21, 0x12, 0xa4, 0x42]), data[8..<20] == transactionID else { return nil }
    var index = 20
    while index + 4 <= data.count {
        let type = UInt16(data[index]) << 8 | UInt16(data[index + 1])
        let length = Int(data[index + 2]) << 8 | Int(data[index + 3])
        let valueStart = index + 4
        let valueEnd = valueStart + length
        guard valueEnd <= data.count else { return nil }
        if type == 0x0020, length >= 8, data[valueStart + 1] == 0x01 {
            let port = (UInt16(data[valueStart + 2]) << 8 | UInt16(data[valueStart + 3])) ^ 0x2112
            let ip = [data[valueStart + 4] ^ 0x21, data[valueStart + 5] ^ 0x12, data[valueStart + 6] ^ 0xa4, data[valueStart + 7] ^ 0x42].map(String.init).joined(separator: ".")
            return "\(ip):\(port)"
        }
        if type == 0x0001, length >= 8, data[valueStart + 1] == 0x01 {
            let port = UInt16(data[valueStart + 2]) << 8 | UInt16(data[valueStart + 3])
            let ip = data[valueStart + 4..<valueStart + 8].map(String.init).joined(separator: ".")
            return "\(ip):\(port)"
        }
        index = valueEnd + ((4 - (length % 4)) % 4)
    }
    return nil
}

private func sendUDP(_ data: Data, fd: Int32, host: String, port: Int) throws {
    var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_DGRAM, ai_protocol: IPPROTO_UDP, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else {
        throw NativeHysteria2Error.networkFailed("udp address resolution failed")
    }
    defer { freeaddrinfo(result) }
    let sent = data.withUnsafeBytes { rawBuffer in
        Darwin.sendto(fd, rawBuffer.baseAddress, data.count, 0, first.pointee.ai_addr, first.pointee.ai_addrlen)
    }
    if sent != data.count {
        throw NativeHysteria2Error.networkFailed("udp send failed")
    }
}

private func connectUDP(fd: Int32, host: String, port: Int) throws {
    var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_DGRAM, ai_protocol: IPPROTO_UDP, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else {
        throw NativeHysteria2Error.networkFailed("udp peer resolution failed")
    }
    defer { freeaddrinfo(result) }
    if Darwin.connect(fd, first.pointee.ai_addr, first.pointee.ai_addrlen) != 0 {
        throw NativeHysteria2Error.networkFailed("udp peer connect failed")
    }
}

private func receiveUDPPunch(fd: Int32, metadata: NativeHysteria2RealmPunchMetadata) throws -> (address: String, packet: NativeHysteria2RealmPunchPacket)? {
    var buffer = [UInt8](repeating: 0, count: 1057)
    var storage = sockaddr_storage()
    var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
    let received = withUnsafeMutablePointer(to: &storage) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.recvfrom(fd, &buffer, buffer.count, 0, sockaddrPointer, &length)
        }
    }
    if received < 0 {
        if errno == EAGAIN || errno == EWOULDBLOCK { return nil }
        throw NativeHysteria2Error.networkFailed("realm punch receive failed")
    }
    let packet = try NativeHysteria2RealmPunchPacket.decode(Data(buffer.prefix(received)), metadata: metadata)
    guard let address = addressString(from: storage) else { return nil }
    return (address, packet)
}

private func addressString(from storage: sockaddr_storage) -> String? {
    var storage = storage
    if storage.ss_family == sa_family_t(AF_INET) {
        return withUnsafePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addressPointer in
                let address = addressPointer.pointee
                var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var sinAddress = address.sin_addr
                guard inet_ntop(AF_INET, &sinAddress, &ipBuffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return "\(String(cString: ipBuffer)):\(Int(UInt16(bigEndian: address.sin_port)))"
            }
        }
    }
    return nil
}

public struct NativeHysteria2RealmRendezvousClient: Sendable {
    private struct ConnectRequest: Encodable {
        let addresses: [String]
        let nonce: String
        let obfs: String
    }

    private struct ConnectResponse: Decodable {
        let addresses: [String]
        let nonce: String
        let obfs: String
    }

    public typealias Executor = @Sendable (URLRequest, Data) async throws -> Data

    private let baseURL: URL
    private let token: String
    private let executor: Executor

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
        self.executor = Self.defaultExecutor
    }

    public init(baseURL: URL, token: String, executor: @escaping Executor) {
        self.baseURL = baseURL
        self.token = token
        self.executor = executor
    }

    public func connect(realmID: String, localAddresses: [String], metadata: NativeHysteria2RealmPunchMetadata) async throws -> NativeHysteria2RealmRendezvousResponse {
        let trimmedRealmID = realmID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRealmID.isEmpty, !trimmedRealmID.contains("/") else {
            throw NativeHysteria2Error.invalidConfiguration("invalid realm id")
        }
        guard !trimmedToken.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing realm token")
        }
        guard !localAddresses.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing realm local addresses")
        }

        let body = try JSONEncoder().encode(ConnectRequest(addresses: localAddresses, nonce: metadata.nonce, obfs: metadata.obfs))
        let encodedRealmID = trimmedRealmID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmedRealmID
        var request = URLRequest(url: baseURL.appendingPathComponent("v1").appendingPathComponent(encodedRealmID).appendingPathComponent("connect"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let responseData = try await executor(request, body)
        let response = try JSONDecoder().decode(ConnectResponse.self, from: responseData)
        let responseMetadata = try NativeHysteria2RealmPunchMetadata(nonce: response.nonce, obfs: response.obfs)
        return NativeHysteria2RealmRendezvousResponse(addresses: response.addresses, metadata: responseMetadata)
    }

    private static let defaultExecutor: Executor = { request, body in
        var request = request
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NativeHysteria2Error.networkFailed("realm rendezvous connect failed")
        }
        return data
    }
}

public enum NativeHysteria2Error: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case authenticationFailed(String)
    case networkFailed(String)
    case blocked(String)
    case unsupportedRuntime(String)

    public var description: String {
        switch self {
        case .invalidConfiguration:
            return "Invalid native Hysteria2 configuration"
        case .authenticationFailed:
            return "Native Hysteria2 authentication failed"
        case .networkFailed:
            return "Native Hysteria2 network failed"
        case .blocked:
            return "Native Hysteria2 operation blocked"
        case .unsupportedRuntime:
            return "Native Hysteria2 runtime unavailable"
        }
    }
}

public enum NativeHysteria2Runtime {
    public static var info: NativeHysteria2RuntimeInfo {
        NativeHysteria2RuntimeInfo(
            ngtcp2Version: String(cString: ngtcp2_version(0).pointee.version_str),
            nghttp3Version: String(cString: nghttp3_version(0).pointee.version_str)
        )
    }
}

public struct NativeHysteria2Client: Sendable {
    public let configuration: NativeHysteria2ClientConfiguration

    public init(configuration: NativeHysteria2ClientConfiguration) {
        self.configuration = configuration
    }

    public func connect(authentication: String) async throws -> NativeHysteria2Session {
        let trimmedAuthentication = authentication.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthentication.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing authentication")
        }
        var session: irock_hy2_session_ref?
        let result = configuration.serverHost.withCString { serverHost in
            configuration.serverName.withCString { serverName in
                configuration.alpn.joined(separator: ",").withCString { alpn in
                    trimmedAuthentication.withCString { authentication in
                        var nativeConfiguration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: UInt16(configuration.serverPort),
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: configuration.allowInsecure ? 1 : 0
                        )
                        if let connectedUDPPath = configuration.connectedUDPPath {
                            return irock_hy2_connect_with_connected_udp_socket(&nativeConfiguration, authentication, connectedUDPPath.fileDescriptor, Int32(connectedUDPPath.remotePort), &session)
                        }
                        return irock_hy2_connect(&nativeConfiguration, authentication, &session)
                    }
                }
            }
        }
        switch result {
        case IROCK_HY2_OK:
            guard let session else {
                throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 connect returned no session")
            }
            return NativeHysteria2Session(nativeSession: session)
        case IROCK_HY2_INVALID_CONFIGURATION:
            throw NativeHysteria2Error.invalidConfiguration("native hysteria2 configuration rejected")
        case IROCK_HY2_AUTH_FAILED:
            throw NativeHysteria2Error.authenticationFailed("native hysteria2 authentication rejected")
        case IROCK_HY2_NETWORK_FAILED:
            throw NativeHysteria2Error.networkFailed("native hysteria2 connect network failed")
        case IROCK_HY2_BLOCKED:
            throw NativeHysteria2Error.blocked("native hysteria2 connect blocked")
        case IROCK_HY2_UNSUPPORTED:
            throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 connect returned unsupported")
        default:
            throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 connect failed")
        }
    }
}

public final class NativeHysteria2Session: @unchecked Sendable {
    private let nativeSession: irock_hy2_session_ref
    private let lock = NSLock()

    init(nativeSession: irock_hy2_session_ref) {
        self.nativeSession = nativeSession
    }

    deinit {
        lock.lock()
        irock_hy2_session_free(nativeSession)
        lock.unlock()
    }

    func withNativeSessionLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    func receivePendingPacketsForStreamRead() {
        withNativeSessionLock {
            var packetsRead: Int32 = 0
            _ = irock_hy2_session_receive_quic_for_testing(nativeSession, &packetsRead)
        }
    }

    public func openTCPStream(address: String) async throws -> any NativeHysteria2ByteStream {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw NativeHysteria2Error.invalidConfiguration("missing tcp address")
        }
        var stream: irock_hy2_stream_ref?
        let result = withNativeSessionLock {
            trimmedAddress.withCString { address in
                irock_hy2_session_open_tcp_stream(nativeSession, address, &stream)
            }
        }
        switch result {
        case IROCK_HY2_OK:
            guard let stream else {
                throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 tcp stream returned no stream")
            }
            return NativeHysteria2NativeByteStream(nativeStream: stream, session: self)
        case IROCK_HY2_INVALID_CONFIGURATION:
            throw NativeHysteria2Error.invalidConfiguration("native hysteria2 tcp stream rejected")
        case IROCK_HY2_AUTH_FAILED:
            throw NativeHysteria2Error.authenticationFailed("native hysteria2 tcp stream authentication failed")
        case IROCK_HY2_NETWORK_FAILED:
            throw NativeHysteria2Error.networkFailed("native hysteria2 tcp stream network failed")
        case IROCK_HY2_BLOCKED:
            throw NativeHysteria2Error.blocked("native hysteria2 tcp stream blocked")
        case IROCK_HY2_UNSUPPORTED:
            throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 tcp stream returned unsupported")
        default:
            throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 tcp stream failed")
        }
    }
}

final class NativeHysteria2NativeByteStream: NativeHysteria2ByteStream, @unchecked Sendable {
    private let nativeStream: irock_hy2_stream_ref
    private let session: NativeHysteria2Session

    init(nativeStream: irock_hy2_stream_ref, session: NativeHysteria2Session) {
        self.nativeStream = nativeStream
        self.session = session
    }

    deinit {
        session.withNativeSessionLock {
            irock_hy2_stream_free(nativeStream)
        }
    }

    func read(maxLength: Int) async throws -> Data? {
        guard maxLength > 0 else {
            throw NativeHysteria2Error.invalidConfiguration("invalid stream read length")
        }
        while true {
            var buffer = [UInt8](repeating: 0, count: maxLength)
            var bytesRead: Int32 = 0
            let result = session.withNativeSessionLock {
                irock_hy2_stream_read(nativeStream, &buffer, Int32(maxLength), &bytesRead)
            }
            switch result {
            case IROCK_HY2_OK:
                return bytesRead > 0 ? Data(buffer.prefix(Int(bytesRead))) : nil
            case IROCK_HY2_INVALID_CONFIGURATION:
                throw NativeHysteria2Error.invalidConfiguration("native hysteria2 stream read rejected")
            case IROCK_HY2_AUTH_FAILED:
                throw NativeHysteria2Error.authenticationFailed("native hysteria2 stream read authentication failed")
            case IROCK_HY2_NETWORK_FAILED:
                throw NativeHysteria2Error.networkFailed("native hysteria2 stream read network failed")
            case IROCK_HY2_BLOCKED:
                session.receivePendingPacketsForStreamRead()
                try await Task.sleep(nanoseconds: 1_000_000)
            case IROCK_HY2_UNSUPPORTED:
                throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 stream read returned unsupported")
            default:
                throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 stream read failed")
            }
        }
    }

    func write(_ data: Data) async throws {
        let result = session.withNativeSessionLock {
            data.withUnsafeBytes { rawBuffer in
                irock_hy2_stream_write(nativeStream, rawBuffer.bindMemory(to: UInt8.self).baseAddress, Int32(data.count))
            }
        }
        switch result {
        case IROCK_HY2_OK:
            return
        case IROCK_HY2_INVALID_CONFIGURATION:
            throw NativeHysteria2Error.invalidConfiguration("native hysteria2 stream write rejected")
        case IROCK_HY2_AUTH_FAILED:
            throw NativeHysteria2Error.authenticationFailed("native hysteria2 stream write authentication failed")
        case IROCK_HY2_NETWORK_FAILED:
            throw NativeHysteria2Error.networkFailed("native hysteria2 stream write network failed")
        case IROCK_HY2_BLOCKED:
            throw NativeHysteria2Error.blocked("native hysteria2 stream write blocked")
        case IROCK_HY2_UNSUPPORTED:
            throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 stream write returned unsupported")
        default:
            throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 stream write failed")
        }
    }

    func closeWrite() async throws {
        let result = session.withNativeSessionLock {
            irock_hy2_stream_close_write(nativeStream)
        }
        switch result {
        case IROCK_HY2_OK:
            return
        case IROCK_HY2_INVALID_CONFIGURATION:
            throw NativeHysteria2Error.invalidConfiguration("native hysteria2 stream closeWrite rejected")
        case IROCK_HY2_AUTH_FAILED:
            throw NativeHysteria2Error.authenticationFailed("native hysteria2 stream closeWrite authentication failed")
        case IROCK_HY2_NETWORK_FAILED:
            throw NativeHysteria2Error.networkFailed("native hysteria2 stream closeWrite network failed")
        case IROCK_HY2_BLOCKED:
            throw NativeHysteria2Error.blocked("native hysteria2 stream closeWrite blocked")
        case IROCK_HY2_UNSUPPORTED:
            throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 stream closeWrite returned unsupported")
        default:
            throw NativeHysteria2Error.unsupportedRuntime("native hysteria2 stream closeWrite failed")
        }
    }

    func close() async {}
}

public protocol NativeHysteria2ByteStream: Sendable {
    func read(maxLength: Int) async throws -> Data?
    func write(_ data: Data) async throws
    func closeWrite() async throws
    func close() async
}
