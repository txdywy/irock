import IrockCore

public struct TransportRequest: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let transport: TransportType
    public let tls: TLSOptions?
    public let metadata: [String: String]

    public init(host: String, port: Int, transport: TransportType, tls: TLSOptions? = nil, metadata: [String: String] = [:]) {
        self.host = host
        self.port = port
        self.transport = transport
        self.tls = tls
        self.metadata = metadata
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
