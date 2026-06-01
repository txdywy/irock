import Foundation
import IrockCore
import IrockTransport

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
            throw mapTransportErrorToProxyProtocolError(error)
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
    private let streamRegistry: TransportStreamAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, streamRegistry: TransportStreamAdapterRegistry = TransportStreamAdapterRegistry(adapters: []), credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.streamRegistry = streamRegistry
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
            if let streamAdapter = streamRegistry.adapter(for: request.node.transport) {
                let stream = try await streamAdapter.openStream(request: transportRequest)
                return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination, retainedStream: stream)
            }
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw mapTransportErrorToProxyProtocolError(error)
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
        if request.node.transport == .grpc {
            metadata["grpcProtocol"] = request.node.protocolType.rawValue
        }
        applyTransportOptions(from: request.node, to: &metadata)
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
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
        let realityConfiguration = try request.node.tls.reality.map { _ in try VLESSRealityHandshakeConfiguration(tls: request.node.tls) }
        let transportRequest = TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: transportMetadata(for: request, openRequest: openRequest, realityConfiguration: realityConfiguration),
            initialPayload: openRequest.openBytes
        )
        do {
            _ = try await transportRegistry.adapter(for: request.node.transport).open(request: transportRequest)
        } catch let error as TransportError {
            throw mapTransportErrorToProxyProtocolError(error)
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

    private func transportMetadata(for request: ProxyRequest, openRequest: VLESSOpenRequest, realityConfiguration: VLESSRealityHandshakeConfiguration?) -> [String: String] {
        var metadata = request.metadata
        Self.removeSensitiveMetadata(from: &metadata)
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        applyTransportOptions(from: request.node, to: &metadata)
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        for (key, value) in realityConfiguration?.metadata ?? [:] {
            metadata[key] = value
        }
        return metadata
    }

    private static func removeSensitiveMetadata(from metadata: inout [String: String]) {
        metadata.removeValue(forKey: "vlessUserID")
        metadata.removeValue(forKey: "vlessRealityPublicKey")
        metadata.removeValue(forKey: "realityPublicKey")
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
            throw mapTransportErrorToProxyProtocolError(error)
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
            throw mapTransportErrorToProxyProtocolError(error)
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
}

public struct TrustTunnelProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .trustTunnel
    private let streamRegistry: TransportStreamAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(streamRegistry: TransportStreamAdapterRegistry, credentialResolver: CredentialResolver) {
        self.streamRegistry = streamRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let stream = try await streamRegistry.adapter(for: request.node.transport)?.openStream(request: transportRequest(for: request, credential: credential))
        guard let stream else {
            throw ProxyProtocolError.unsupportedTransport(request.node.transport)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination, retainedStream: stream)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .trustTunnel else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard node.transport == .http2 || node.transport == .quic else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
        guard node.tls.enabled else {
            throw ProxyProtocolError.invalidConfiguration("trusttunnel requires tls")
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing trusttunnel server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid trusttunnel server port")
        }
    }

    private func transportRequest(for request: ProxyRequest, credential: String) throws -> TransportRequest {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        metadata["http2Method"] = "CONNECT"
        metadata["http2Authority"] = authority(for: request.destination)
        metadata["userAgent"] = "irock trusttunnel"
        metadata["proxyAuthorization"] = "Basic \(Data(credential.utf8).base64EncodedString())"
        return TransportRequest(
            host: request.node.serverHost,
            port: request.node.serverPort,
            transport: request.node.transport,
            tls: request.node.tls.enabled ? request.node.tls : nil,
            metadata: metadata,
            initialPayload: nil
        )
    }

    private func authority(for destination: ProxyDestination) -> String {
        switch destination {
        case .host(let host, let port): return "\(host):\(port)"
        case .ipv4(let address, let port): return "\(address):\(port)"
        case .ipv6(let address, let port): return "[\(address)]:\(port)"
        }
    }
}

public struct TUICProxyAdapter<Dialer: TUICQUICSessionDialer, CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .tuic
    private let sessionDialer: Dialer
    private let credentialResolver: CredentialResolver

    public init(sessionDialer: Dialer, credentialResolver: CredentialResolver) {
        self.sessionDialer = sessionDialer
        self.credentialResolver = credentialResolver
    }

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) where Dialer == UnavailableTUICQUICSessionDialer {
        self.sessionDialer = UnavailableTUICQUICSessionDialer()
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let stream = try await TUICStreamOpener(sessionDialer: sessionDialer).openStream(node: request.node, credential: credential, destination: request.destination, metadata: request.metadata)
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination, retainedStream: stream)
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

}

public struct HTTPProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .httpProxy
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let openRequest = try HTTPProxyOpenRequest(credential: credential, destination: request.destination)
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
            throw mapTransportErrorToProxyProtocolError(error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .httpProxy else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing http proxy server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid http proxy server port")
        }
        guard node.transport == .tcp else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: HTTPProxyOpenRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        metadata["destination"] = openRequest.destinationAuthority
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }
}

public extension HTTPProxyAdapter where CredentialResolver == MissingProxyCredentialResolver {
    init(transportRegistry: TransportAdapterRegistry) {
        self.init(transportRegistry: transportRegistry, credentialResolver: MissingProxyCredentialResolver())
    }
}

public struct SOCKSProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .socks
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let openRequest = try SOCKSOpenRequest(credential: credential, destination: request.destination)
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
            throw mapTransportErrorToProxyProtocolError(error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .socks else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing socks server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid socks server port")
        }
        guard node.transport == .tcp else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: SOCKSOpenRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        metadata["destination"] = openRequest.destinationDescription
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }
}

public extension SOCKSProxyAdapter where CredentialResolver == MissingProxyCredentialResolver {
    init(transportRegistry: TransportAdapterRegistry) {
        self.init(transportRegistry: transportRegistry, credentialResolver: MissingProxyCredentialResolver())
    }
}

public struct SnellProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .snell
    private let transportRegistry: TransportAdapterRegistry
    private let credentialResolver: CredentialResolver

    public init(transportRegistry: TransportAdapterRegistry, credentialResolver: CredentialResolver) {
        self.transportRegistry = transportRegistry
        self.credentialResolver = credentialResolver
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let openRequest = try SnellOpenRequest(credential: credential, destination: request.destination)
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
            throw mapTransportErrorToProxyProtocolError(error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .snell else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing snell server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid snell server port")
        }
        guard node.transport == .tcp else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
    }

    private func transportMetadata(for request: ProxyRequest, openRequest: SnellOpenRequest) -> [String: String] {
        var metadata = request.metadata
        metadata["proxyProtocol"] = request.node.protocolType.rawValue
        metadata["destination"] = openRequest.destinationDescription
        for (key, value) in openRequest.metadata {
            metadata[key] = value
        }
        return metadata
    }
}

public extension SnellProxyAdapter where CredentialResolver == MissingProxyCredentialResolver {
    init(transportRegistry: TransportAdapterRegistry) {
        self.init(transportRegistry: transportRegistry, credentialResolver: MissingProxyCredentialResolver())
    }
}

public struct ShadowsocksRProxyAdapter<CredentialResolver: ProxyCredentialResolver>: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .shadowsocksR
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
            throw mapTransportErrorToProxyProtocolError(error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .shadowsocksR else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing shadowsocksr server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocksr server port")
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
        case let .host(host, port): return "host:\(host):\(port)"
        case let .ipv4(address, port): return "ipv4:\(address):\(port)"
        case let .ipv6(address, port): return "ipv6:\(address):\(port)"
        }
    }
}

public extension ShadowsocksRProxyAdapter where CredentialResolver == MissingProxyCredentialResolver {
    init(transportRegistry: TransportAdapterRegistry) {
        self.init(transportRegistry: transportRegistry, credentialResolver: MissingProxyCredentialResolver())
    }
}

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
            throw mapTransportErrorToProxyProtocolError(error)
        }
        return EstablishedProxyConnection(nodeID: request.node.id, destination: request.destination)
    }

    public func encodeUDPDatagram(request: ProxyUDPDatagramRequest) throws -> EncodedProxyUDPDatagram {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let datagram = try ShadowsocksUDPDatagramRequest(
            credential: credential,
            destination: request.destination,
            payload: request.payload,
            salt: Data.random(count: try ShadowsocksStreamRequest.saltLength(forCredential: credential))
        )
        return EncodedProxyUDPDatagram(server: .host(request.node.serverHost, port: request.node.serverPort), payload: datagram.packet)
    }

    public func decodeUDPDatagramResponse(_ response: Data, request: ProxyUDPDatagramRequest) throws -> ProxyUDPDatagramResponse? {
        try validate(request.node)
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let plaintext = try ShadowsocksUDPDatagramRequest.decryptPayload(response, credential: credential)
        let addressFrame = try request.destination.shadowsocksAddressFrame
        guard plaintext.starts(with: addressFrame) else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks udp response destination")
        }
        return ProxyUDPDatagramResponse(source: request.destination, payload: plaintext.dropFirst(addressFrame.count))
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
}

public extension ShadowsocksProxyAdapter where CredentialResolver == MissingProxyCredentialResolver {
    init(transportRegistry: TransportAdapterRegistry) {
        self.init(transportRegistry: transportRegistry, credentialResolver: MissingProxyCredentialResolver())
    }
}
