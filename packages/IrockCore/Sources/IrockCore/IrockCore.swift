public enum IrockCoreModule {
    public static let name = "IrockCore"
}

public struct NodeID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct SnapshotID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ProxyProtocolType: String, Codable, Sendable {
    case shadowsocks
    case vmess
    case vless
    case trojan
    case hysteria2
    case tuic
}

public enum TransportType: String, Codable, Sendable {
    case tcp
    case webSocket
    case http2
    case grpc
    case quic
}

public enum ProxyCredentials: Equatable, Codable, Sendable {
    case password(String)
    case uuid(String)
    case token(String)
}

public struct RealityOptions: Equatable, Codable, Sendable {
    public let publicKey: String
    public let shortID: String?
    public let spiderX: String?

    public init(publicKey: String, shortID: String?, spiderX: String?) {
        self.publicKey = publicKey
        self.shortID = shortID
        self.spiderX = spiderX
    }
}

public struct TLSOptions: Equatable, Codable, Sendable {
    public let enabled: Bool
    public let serverName: String?
    public let allowInsecure: Bool
    public let alpn: [String]
    public let fingerprint: String?
    public let reality: RealityOptions?

    public static let disabled = TLSOptions(
        enabled: false,
        serverName: nil,
        allowInsecure: false,
        alpn: [],
        fingerprint: nil,
        reality: nil
    )

    public init(enabled: Bool, serverName: String?, allowInsecure: Bool, alpn: [String], fingerprint: String?, reality: RealityOptions?) {
        self.enabled = enabled
        self.serverName = serverName
        self.allowInsecure = allowInsecure
        self.alpn = alpn
        self.fingerprint = fingerprint
        self.reality = reality
    }
}

public enum UDPPolicy: String, Codable, Sendable {
    case disabled
    case enabled
}

public struct ProxyNode: Equatable, Codable, Sendable {
    public let id: NodeID
    public let name: String
    public let protocolType: ProxyProtocolType
    public let serverHost: String
    public let serverPort: Int
    public let credentials: ProxyCredentials
    public let transport: TransportType
    public let tls: TLSOptions
    public let udpPolicy: UDPPolicy

    public init(
        id: NodeID,
        name: String,
        protocolType: ProxyProtocolType,
        serverHost: String,
        serverPort: Int,
        credentials: ProxyCredentials,
        transport: TransportType,
        tls: TLSOptions,
        udpPolicy: UDPPolicy
    ) {
        self.id = id
        self.name = name
        self.protocolType = protocolType
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.credentials = credentials
        self.transport = transport
        self.tls = tls
        self.udpPolicy = udpPolicy
    }
}

public enum RouteMode: String, Codable, Sendable {
    case globalProxy
    case ruleBased
    case direct
}

public enum IrockLogLevel: String, Codable, Sendable {
    case off
    case user
    case debug
}

public struct RuntimeSnapshot: Equatable, Codable, Sendable {
    public let id: SnapshotID
    public let selectedNode: ProxyNode
    public let routeMode: RouteMode
    public let logLevel: IrockLogLevel

    public init(id: SnapshotID, selectedNode: ProxyNode, routeMode: RouteMode, logLevel: IrockLogLevel) {
        self.id = id
        self.selectedNode = selectedNode
        self.routeMode = routeMode
        self.logLevel = logLevel
    }
}
