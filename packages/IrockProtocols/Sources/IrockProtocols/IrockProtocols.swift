import IrockCore
import IrockTransport

public enum ProxyDestination: Equatable, Sendable {
    case host(String, port: Int)
    case ipv4(String, port: Int)
    case ipv6(String, port: Int)
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
}

public struct EstablishedProxyConnection: ProxyConnection, Equatable, Sendable {
    public let nodeID: NodeID
    public let destination: ProxyDestination

    public init(nodeID: NodeID, destination: ProxyDestination) {
        self.nodeID = nodeID
        self.destination = destination
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

public struct ShadowsocksProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType = .shadowsocks
    private let transportBackedAdapter: TransportBackedProxyAdapter

    public init(transportRegistry: TransportAdapterRegistry) {
        self.transportBackedAdapter = TransportBackedProxyAdapter(protocolType: .shadowsocks, transportRegistry: transportRegistry)
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        try validate(request.node)
        return try await transportBackedAdapter.connect(request: request)
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .shadowsocks else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
    }
}
