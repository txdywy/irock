import Foundation
import IrockCore

public struct TransportRequest: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let transport: TransportType
    public let tls: TLSOptions?
    public let metadata: [String: String]
    public let initialPayload: Data?

    public init(host: String, port: Int, transport: TransportType, tls: TLSOptions? = nil, metadata: [String: String] = [:], initialPayload: Data? = nil) {
        self.host = host
        self.port = port
        self.transport = transport
        self.tls = tls
        self.metadata = metadata
        self.initialPayload = initialPayload
    }
}

public protocol TransportConnection: Sendable {
    var host: String { get }
    var port: Int { get }
    var transport: TransportType { get }
}

public struct EstablishedTransportConnection: TransportConnection, Equatable, Sendable {
    public let host: String
    public let port: Int
    public let transport: TransportType

    public init(host: String, port: Int, transport: TransportType) {
        self.host = host
        self.port = port
        self.transport = transport
    }
}

public enum TransportError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case dnsFailed(String)
    case tcpConnectFailed(String)
    case tlsHandshakeFailed(String)
    case unsupportedTransport(TransportType)
    case quicHandshakeFailed(String)
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
        case let .unsupportedTransport(transport):
            return "Unsupported transport: \(transport.rawValue)"
        case .quicHandshakeFailed:
            return "QUIC handshake failed"
        case .remoteClosed:
            return "Remote closed"
        case .timeout:
            return "Timeout"
        }
    }
}

public protocol TransportAdapter: Sendable {
    var supportedTransport: TransportType { get }
    func open(request: TransportRequest) async throws -> any TransportConnection
}

public struct UnsupportedTransportAdapter: TransportAdapter {
    public let supportedTransport: TransportType

    public init(transport: TransportType) {
        self.supportedTransport = transport
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        throw TransportError.unsupportedTransport(request.transport)
    }
}

public struct NoopTransportAdapter: TransportAdapter {
    public let supportedTransport: TransportType

    public init(transport: TransportType = .tcp) {
        self.supportedTransport = transport
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        throw TransportError.unsupportedTransport(request.transport)
    }
}

public struct TransportAdapterRegistry: Sendable {
    private let adapters: [TransportType: any TransportAdapter]

    public init(adapters: [any TransportAdapter]) {
        var indexed: [TransportType: any TransportAdapter] = [:]
        for adapter in adapters {
            indexed[adapter.supportedTransport] = adapter
        }
        self.adapters = indexed
    }

    public func adapter(for transport: TransportType) -> any TransportAdapter {
        adapters[transport] ?? UnsupportedTransportAdapter(transport: transport)
    }
}

public struct TCPDialResult: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public protocol TCPDialer: Sendable {
    func open(host: String, port: Int, initialPayload: Data?) async throws -> TCPDialResult
}

public struct QUICDialResult: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public protocol QUICDialer: Sendable {
    func open(host: String, port: Int, metadata: [String: String], initialPayload: Data?) async throws -> QUICDialResult
}

public struct TCPTransportAdapter<Dialer: TCPDialer>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp
    private let dialer: Dialer

    public init(dialer: Dialer) {
        self.dialer = dialer
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        try validate(request)
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await dialer.open(host: host, port: request.port, initialPayload: request.initialPayload)
        return EstablishedTransportConnection(host: result.host, port: result.port, transport: .tcp)
    }

    private func validate(_ request: TransportRequest) throws {
        guard request.transport == .tcp else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        guard !request.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransportError.invalidConfiguration("missing tcp host")
        }
        guard (1...65_535).contains(request.port) else {
            throw TransportError.invalidConfiguration("invalid tcp port")
        }
        guard request.tls == nil else {
            throw TransportError.unsupportedTransport(.tcp)
        }
    }
}

public struct TLSTransportAdapter<Underlying: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp
    private let underlying: Underlying

    public init(underlying: Underlying) {
        self.underlying = underlying
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        try validate(request)
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let underlyingRequest = TransportRequest(host: host, port: request.port, transport: request.transport, tls: nil, metadata: request.metadata, initialPayload: request.initialPayload)
        let connection = try await underlying.open(request: underlyingRequest)
        return EstablishedTransportConnection(host: connection.host, port: connection.port, transport: .tcp)
    }

    private func validate(_ request: TransportRequest) throws {
        guard request.transport == .tcp else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        guard let tls = request.tls, tls.enabled else {
            throw TransportError.invalidConfiguration("missing tls options")
        }
        guard !request.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransportError.invalidConfiguration("missing tls host")
        }
        guard (1...65_535).contains(request.port) else {
            throw TransportError.invalidConfiguration("invalid tls port")
        }
        if let serverName = tls.serverName, serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TransportError.invalidConfiguration("invalid tls server name")
        }
        guard tls.reality == nil else {
            throw TransportError.unsupportedTransport(.tcp)
        }
    }
}

public struct TCPTLSTransportAdapter<Plain: TransportAdapter, TLS: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp
    private let plain: Plain
    private let tls: TLS

    public init(plain: Plain, tls: TLS) {
        self.plain = plain
        self.tls = tls
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        guard request.transport == .tcp else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        if request.tls?.enabled == true {
            return try await tls.open(request: request)
        }
        return try await plain.open(request: request)
    }
}

public struct QUICTransportAdapter<Dialer: QUICDialer>: TransportAdapter {
    public let supportedTransport: TransportType = .quic
    private let dialer: Dialer

    public init(dialer: Dialer) {
        self.dialer = dialer
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        let descriptor = try descriptor(for: request)
        let result = try await dialer.open(
            host: descriptor.host,
            port: request.port,
            metadata: descriptor.metadata,
            initialPayload: descriptor.initialPayload(appending: request.initialPayload)
        )
        return EstablishedTransportConnection(host: result.host, port: result.port, transport: .quic)
    }

    private func descriptor(for request: TransportRequest) throws -> QUICOpenDescriptor {
        guard request.transport == .quic else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw TransportError.invalidConfiguration("missing quic host")
        }
        guard (1...65_535).contains(request.port) else {
            throw TransportError.invalidConfiguration("invalid quic port")
        }
        let serverName = request.metadata["quicServerName", default: host].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverName.isEmpty else {
            throw TransportError.invalidConfiguration("invalid quic server name")
        }
        let protocolName = request.metadata["quicProtocol"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if request.metadata.keys.contains("quicProtocol"), protocolName.isEmpty {
            throw TransportError.invalidConfiguration("invalid quic protocol")
        }
        let metadataALPN = request.metadata["quicALPN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if request.metadata.keys.contains("quicALPN"), metadataALPN?.isEmpty != false {
            throw TransportError.invalidConfiguration("invalid quic alpn")
        }
        let alpn = metadataALPN?.isEmpty == false ? metadataALPN! : request.tls?.alpn.joined(separator: ",") ?? ""
        return QUICOpenDescriptor(host: host, serverName: serverName, protocolName: protocolName, alpn: alpn)
    }
}

private struct QUICOpenDescriptor {
    let host: String
    let serverName: String
    let protocolName: String
    let alpn: String

    var metadata: [String: String] {
        var metadata = [
            "quicServerName": serverName,
            "quicHandshake": "foundation"
        ]
        if !protocolName.isEmpty {
            metadata["quicProtocol"] = protocolName
        }
        if !alpn.isEmpty {
            metadata["quicALPN"] = alpn
        }
        return metadata
    }

    func initialPayload(appending payload: Data?) -> Data {
        var data = Data("quic-foundation:\(serverName):\(protocolName):\(alpn)\n".utf8)
        if let payload {
            data.append(payload)
        }
        return data
    }
}

public struct RealityTransportAdapter<Underlying: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .tcp
    private let underlying: Underlying

    public init(underlying: Underlying) {
        self.underlying = underlying
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        let descriptor = try descriptor(for: request)
        let underlyingRequest = TransportRequest(
            host: descriptor.host,
            port: request.port,
            transport: .tcp,
            tls: nil,
            metadata: descriptor.metadata(merging: request.metadata),
            initialPayload: descriptor.initialPayload(appending: request.initialPayload)
        )
        let connection = try await underlying.open(request: underlyingRequest)
        return EstablishedTransportConnection(host: connection.host, port: connection.port, transport: .tcp)
    }

    private func descriptor(for request: TransportRequest) throws -> RealityOpenDescriptor {
        guard request.transport == .tcp else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw TransportError.invalidConfiguration("missing reality host")
        }
        guard (1...65_535).contains(request.port) else {
            throw TransportError.invalidConfiguration("invalid reality port")
        }
        guard let tls = request.tls, tls.enabled, let reality = tls.reality else {
            throw TransportError.invalidConfiguration("missing reality tls options")
        }
        let serverName = tls.serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !serverName.isEmpty else {
            throw TransportError.invalidConfiguration("invalid reality server name")
        }
        let publicKey = reality.publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicKey.isEmpty else {
            throw TransportError.invalidConfiguration("invalid reality public key")
        }
        let shortID = reality.shortID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let shortID, shortID.isEmpty {
            throw TransportError.invalidConfiguration("invalid reality short id")
        }
        let spiderX = reality.spiderX?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let spiderX, spiderX.isEmpty {
            throw TransportError.invalidConfiguration("invalid reality spider x")
        }
        return RealityOpenDescriptor(serverName: serverName, shortIDPresent: shortID != nil, spiderX: spiderX ?? "", fingerprint: tls.fingerprint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", alpn: tls.alpn, host: host)
    }
}

private struct RealityOpenDescriptor {
    let serverName: String
    let shortIDPresent: Bool
    let spiderX: String
    let fingerprint: String
    let alpn: [String]
    let host: String

    func metadata(merging input: [String: String]) -> [String: String] {
        var metadata = input
        metadata["realityServerName"] = serverName
        metadata["realityPublicKeyPresent"] = "true"
        metadata["realityShortIDPresent"] = shortIDPresent ? "true" : "false"
        if !spiderX.isEmpty {
            metadata["realitySpiderX"] = spiderX
        }
        if !fingerprint.isEmpty {
            metadata["realityFingerprint"] = fingerprint
        }
        if !alpn.isEmpty {
            metadata["realityALPN"] = alpn.joined(separator: ",")
        }
        return metadata
    }

    func initialPayload(appending payload: Data?) -> Data {
        var data = Data("reality-foundation:\(serverName):public-key-present:\(shortIDPresent ? "true" : "false"):\(spiderX)\n".utf8)
        if let payload {
            data.append(payload)
        }
        return data
    }
}

public struct WebSocketTransportAdapter<Underlying: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .webSocket
    private let underlying: Underlying

    public init(underlying: Underlying) {
        self.underlying = underlying
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        let descriptor = try descriptor(for: request)
        let underlyingRequest = TransportRequest(
            host: descriptor.host,
            port: request.port,
            transport: .tcp,
            tls: request.tls,
            metadata: descriptor.metadata,
            initialPayload: descriptor.initialPayload(appending: request.initialPayload)
        )
        let connection = try await underlying.open(request: underlyingRequest)
        return EstablishedTransportConnection(host: connection.host, port: connection.port, transport: .webSocket)
    }

    private func descriptor(for request: TransportRequest) throws -> WebSocketOpenDescriptor {
        guard request.transport == .webSocket else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw TransportError.invalidConfiguration("missing websocket host")
        }
        guard (1...65_535).contains(request.port) else {
            throw TransportError.invalidConfiguration("invalid websocket port")
        }
        let path = request.metadata["webSocketPath", default: "/"].trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else {
            throw TransportError.invalidConfiguration("invalid websocket path")
        }
        let hostHeader = request.metadata["webSocketHost", default: host].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostHeader.isEmpty else {
            throw TransportError.invalidConfiguration("invalid websocket host header")
        }
        let protocolName = request.metadata["webSocketProtocol"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return WebSocketOpenDescriptor(host: host, hostHeader: hostHeader, path: path, protocolName: protocolName)
    }
}

private struct WebSocketOpenDescriptor {
    let host: String
    let hostHeader: String
    let path: String
    let protocolName: String

    var metadata: [String: String] {
        var metadata = [
            "webSocketHost": hostHeader,
            "webSocketPath": path,
            "webSocketUpgrade": "true"
        ]
        if !protocolName.isEmpty {
            metadata["webSocketProtocol"] = protocolName
        }
        return metadata
    }

    func initialPayload(appending payload: Data?) -> Data {
        var data = Data("websocket-foundation:\(hostHeader):\(path):\(protocolName)\n".utf8)
        if let payload {
            data.append(payload)
        }
        return data
    }
}

public struct HTTP2TransportAdapter<Underlying: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .http2
    private let underlying: Underlying

    public init(underlying: Underlying) {
        self.underlying = underlying
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        let descriptor = try descriptor(for: request)
        let underlyingRequest = TransportRequest(
            host: descriptor.host,
            port: request.port,
            transport: .tcp,
            tls: request.tls,
            metadata: descriptor.metadata,
            initialPayload: descriptor.initialPayload(appending: request.initialPayload)
        )
        let connection = try await underlying.open(request: underlyingRequest)
        return EstablishedTransportConnection(host: connection.host, port: connection.port, transport: .http2)
    }

    private func descriptor(for request: TransportRequest) throws -> HTTP2OpenDescriptor {
        guard request.transport == .http2 else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw TransportError.invalidConfiguration("missing http2 host")
        }
        guard (1...65_535).contains(request.port) else {
            throw TransportError.invalidConfiguration("invalid http2 port")
        }
        let path = request.metadata["http2Path", default: "/"].trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else {
            throw TransportError.invalidConfiguration("invalid http2 path")
        }
        let authority = request.metadata["http2Authority", default: host].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authority.isEmpty else {
            throw TransportError.invalidConfiguration("invalid http2 authority")
        }
        let protocolName = request.metadata["http2Protocol"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HTTP2OpenDescriptor(host: host, authority: authority, path: path, protocolName: protocolName)
    }
}

private struct HTTP2OpenDescriptor {
    let host: String
    let authority: String
    let path: String
    let protocolName: String

    var metadata: [String: String] {
        var metadata = [
            "http2Authority": authority,
            "http2Path": path,
            "http2Upgrade": "true"
        ]
        if !protocolName.isEmpty {
            metadata["http2Protocol"] = protocolName
        }
        return metadata
    }

    func initialPayload(appending payload: Data?) -> Data {
        var data = Data("http2-foundation:\(authority):\(path):\(protocolName)\n".utf8)
        if let payload {
            data.append(payload)
        }
        return data
    }
}

public struct GRPCTransportAdapter<Underlying: TransportAdapter>: TransportAdapter {
    public let supportedTransport: TransportType = .grpc
    private let underlying: Underlying

    public init(underlying: Underlying) {
        self.underlying = underlying
    }

    public func open(request: TransportRequest) async throws -> any TransportConnection {
        let descriptor = try descriptor(for: request)
        let underlyingRequest = TransportRequest(
            host: descriptor.host,
            port: request.port,
            transport: .tcp,
            tls: request.tls,
            metadata: descriptor.metadata,
            initialPayload: descriptor.initialPayload(appending: request.initialPayload)
        )
        let connection = try await underlying.open(request: underlyingRequest)
        return EstablishedTransportConnection(host: connection.host, port: connection.port, transport: .grpc)
    }

    private func descriptor(for request: TransportRequest) throws -> GRPCOpenDescriptor {
        guard request.transport == .grpc else {
            throw TransportError.unsupportedTransport(request.transport)
        }
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw TransportError.invalidConfiguration("missing grpc host")
        }
        guard (1...65_535).contains(request.port) else {
            throw TransportError.invalidConfiguration("invalid grpc port")
        }
        let service = request.metadata["grpcService", default: "/TunService/Connect"].trimmingCharacters(in: .whitespacesAndNewlines)
        guard service.hasPrefix("/") else {
            throw TransportError.invalidConfiguration("invalid grpc service")
        }
        let authority = request.metadata["grpcAuthority", default: host].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authority.isEmpty else {
            throw TransportError.invalidConfiguration("invalid grpc authority")
        }
        let protocolName = request.metadata["grpcProtocol"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GRPCOpenDescriptor(host: host, authority: authority, service: service, protocolName: protocolName)
    }
}

private struct GRPCOpenDescriptor {
    let host: String
    let authority: String
    let service: String
    let protocolName: String

    var metadata: [String: String] {
        var metadata = [
            "grpcAuthority": authority,
            "grpcService": service,
            "grpcUpgrade": "true"
        ]
        if !protocolName.isEmpty {
            metadata["grpcProtocol"] = protocolName
        }
        return metadata
    }

    func initialPayload(appending payload: Data?) -> Data {
        var data = Data("grpc-foundation:\(authority):\(service):\(protocolName)\n".utf8)
        if let payload {
            data.append(payload)
        }
        return data
    }
}
