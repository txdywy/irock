import Foundation
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
    func open(host: String, port: Int) async throws -> TCPDialResult
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
        let result = try await dialer.open(host: host, port: request.port)
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
        let host = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let underlyingRequest = TransportRequest(host: host, port: request.port, transport: request.transport, tls: nil, metadata: request.metadata)
        let connection = try await underlying.open(request: underlyingRequest)
        return EstablishedTransportConnection(host: connection.host, port: connection.port, transport: .tcp)
    }
}
