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

public enum ProtocolAdapterError: Error, Equatable, Sendable {
    case unsupportedProtocol(ProxyProtocolType)
}

public protocol ProxyAdapter: Sendable {
    func connect(request: ProxyRequest) async throws -> ProxyConnection
}

public struct NoopProxyAdapter: ProxyAdapter {
    public init() {}

    public func connect(request: ProxyRequest) async throws -> ProxyConnection {
        throw ProtocolAdapterError.unsupportedProtocol(request.node.protocolType)
    }
}
