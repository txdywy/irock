import IrockCore

public struct TransportRequest: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let transport: TransportType

    public init(host: String, port: Int, transport: TransportType) {
        self.host = host
        self.port = port
        self.transport = transport
    }
}

public struct TransportConnection: Sendable {
    public init() {}
}

public enum TransportError: Error, Equatable, Sendable {
    case unsupportedTransport(TransportType)
}

public protocol TransportAdapter: Sendable {
    func open(_ request: TransportRequest) async throws -> TransportConnection
}

public struct NoopTransportAdapter: TransportAdapter {
    public init() {}

    public func open(_ request: TransportRequest) async throws -> TransportConnection {
        throw TransportError.unsupportedTransport(request.transport)
    }
}
