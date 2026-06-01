import Foundation
import IrockCore
import IrockTransport

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
    func writePayload(_ payload: [UInt8]) async throws -> [UInt8]?
    func close() async
}

public extension ProxyConnection {
    func writePayload(_ payload: [UInt8]) async throws -> [UInt8]? {
        nil
    }

    func close() async {}
}

public struct EstablishedProxyConnection: ProxyConnection, Equatable, Sendable {
    public let nodeID: NodeID
    public let destination: ProxyDestination
    public let initialResponseBytes: [UInt8]?
    private let retainedStream: (any TransportByteStream)?

    public init(nodeID: NodeID, destination: ProxyDestination, initialResponseBytes: [UInt8]? = nil, retainedStream: (any TransportByteStream)? = nil) {
        self.nodeID = nodeID
        self.destination = destination
        self.initialResponseBytes = initialResponseBytes
        self.retainedStream = retainedStream
    }

    public static func == (lhs: EstablishedProxyConnection, rhs: EstablishedProxyConnection) -> Bool {
        lhs.nodeID == rhs.nodeID
            && lhs.destination == rhs.destination
            && lhs.initialResponseBytes == rhs.initialResponseBytes
    }

    public func writePayload(_ payload: [UInt8]) async throws -> [UInt8]? {
        guard let retainedStream, !payload.isEmpty else { return nil }
        try await retainedStream.write(Data(payload))
        return nil
    }

    public func close() async {
        await retainedStream?.close()
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
    case unsupportedNativeRuntime(ProxyProtocolType)
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
        case let .unsupportedNativeRuntime(protocolType):
            return "Unsupported native runtime: \(protocolType.rawValue)"
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

public struct ProxyUDPDatagramRequest: Equatable, Sendable {
    public let node: ProxyNode
    public let destination: ProxyDestination
    public let payload: Data
    public let metadata: [String: String]

    public init(node: ProxyNode, destination: ProxyDestination, payload: Data, metadata: [String: String] = [:]) {
        self.node = node
        self.destination = destination
        self.payload = payload
        self.metadata = metadata
    }
}

public struct EncodedProxyUDPDatagram: Equatable, Sendable {
    public let server: ProxyDestination
    public let payload: Data

    public init(server: ProxyDestination, payload: Data) {
        self.server = server
        self.payload = payload
    }
}

public struct ProxyUDPDatagramResponse: Equatable, Sendable {
    public let source: ProxyDestination
    public let payload: Data

    public init(source: ProxyDestination, payload: Data) {
        self.source = source
        self.payload = payload
    }
}

public protocol ProxyAdapter: Sendable {
    var supportedProtocol: ProxyProtocolType { get }
    func connect(request: ProxyRequest) async throws -> any ProxyConnection
    func encodeUDPDatagram(request: ProxyUDPDatagramRequest) throws -> EncodedProxyUDPDatagram
    func decodeUDPDatagramResponse(_ response: Data, request: ProxyUDPDatagramRequest) throws -> ProxyUDPDatagramResponse?
}

public extension ProxyAdapter {
    func encodeUDPDatagram(request: ProxyUDPDatagramRequest) throws -> EncodedProxyUDPDatagram {
        throw ProxyProtocolError.udpUnsupported
    }

    func decodeUDPDatagramResponse(_ response: Data, request: ProxyUDPDatagramRequest) throws -> ProxyUDPDatagramResponse? {
        throw ProxyProtocolError.udpUnsupported
    }
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

public struct UnsupportedNativeRuntimeProxyAdapter: ProxyAdapter {
    public let supportedProtocol: ProxyProtocolType

    public init(protocolType: ProxyProtocolType) {
        self.supportedProtocol = protocolType
    }

    public func connect(request: ProxyRequest) async throws -> any ProxyConnection {
        throw ProxyProtocolError.unsupportedNativeRuntime(request.node.protocolType)
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

public protocol ProxyCredentialResolver: Sendable {
    func credential(for reference: CredentialReference) throws -> String
}

public typealias ShadowsocksCredentialResolver = ProxyCredentialResolver

public struct MissingProxyCredentialResolver: ProxyCredentialResolver {
    public init() {}

    public func credential(for reference: CredentialReference) throws -> String {
        throw ProxyProtocolError.invalidConfiguration("missing proxy credential material")
    }
}

public typealias MissingShadowsocksCredentialResolver = MissingProxyCredentialResolver

extension Data {
    static func random(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) })
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
