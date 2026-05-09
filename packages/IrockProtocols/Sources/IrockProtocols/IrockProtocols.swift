import IrockCore
import IrockTransport

public struct ProxyRequest: Equatable, Sendable {
    public let node: ProxyNode
    public let destinationHost: String
    public let destinationPort: Int

    public init(node: ProxyNode, destinationHost: String, destinationPort: Int) {
        self.node = node
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
    }
}

public struct ProxyConnection: Sendable {
    public init() {}
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
