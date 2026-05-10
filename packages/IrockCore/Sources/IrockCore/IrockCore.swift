import Foundation

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

public struct CredentialReference: Equatable, Codable, Sendable {
    public let keychainService: String
    public let account: String

    public init(keychainService: String, account: String) {
        self.keychainService = keychainService
        self.account = account
    }
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
    public let credentialReference: CredentialReference
    public let transport: TransportType
    public let tls: TLSOptions
    public let udpPolicy: UDPPolicy

    public init(
        id: NodeID,
        name: String,
        protocolType: ProxyProtocolType,
        serverHost: String,
        serverPort: Int,
        credentialReference: CredentialReference,
        transport: TransportType,
        tls: TLSOptions,
        udpPolicy: UDPPolicy
    ) {
        self.id = id
        self.name = name
        self.protocolType = protocolType
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.credentialReference = credentialReference
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

public enum RuntimeConnectionPhase: String, Codable, Sendable {
    case disconnected
    case preparing
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case failed
}

public struct RuntimeConnectionStatus: Equatable, Codable, Sendable {
    public let phase: RuntimeConnectionPhase
    public let selectedNodeID: NodeID?
    public let selectedNodeName: String?
    public let updatedAt: Date
    public let message: String?

    public static func disconnected(updatedAt: Date = Date()) -> RuntimeConnectionStatus {
        RuntimeConnectionStatus(
            phase: .disconnected,
            selectedNodeID: nil,
            selectedNodeName: nil,
            updatedAt: updatedAt,
            message: nil
        )
    }

    public init(phase: RuntimeConnectionPhase, selectedNodeID: NodeID?, selectedNodeName: String?, updatedAt: Date = Date(), message: String?) {
        self.phase = phase
        self.selectedNodeID = selectedNodeID
        self.selectedNodeName = selectedNodeName
        self.updatedAt = updatedAt
        self.message = message
    }
}

public enum RuntimeLogLevel: String, Codable, Sendable {
    case user
    case debug
}

public struct RuntimeLogEntry: Equatable, Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let level: RuntimeLogLevel
    public let message: String
    public let nodeID: NodeID?
    public let phase: RuntimeConnectionPhase?

    public init(id: String, timestamp: Date = Date(), level: RuntimeLogLevel, message: String, nodeID: NodeID?, phase: RuntimeConnectionPhase?) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.nodeID = nodeID
        self.phase = phase
    }
}

public enum RuntimeRoutingAction: String, Codable, Sendable {
    case direct
    case proxy
    case reject
}

public enum RuntimeRoutingRuleKind: String, Codable, Sendable {
    case domain
    case domainSuffix
    case domainKeyword
    case ipCIDR
    case finalRule = "final"
}

public struct RuntimeRoutingRule: Equatable, Codable, Sendable {
    public let kind: RuntimeRoutingRuleKind
    public let value: String?
    public let action: RuntimeRoutingAction

    public init(kind: RuntimeRoutingRuleKind, value: String?, action: RuntimeRoutingAction) {
        self.kind = kind
        self.value = value
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(RuntimeRoutingRuleKind.self, forKey: .kind)
        self.value = try container.decodeIfPresent(String.self, forKey: .value)
        self.action = try container.decode(RuntimeRoutingAction.self, forKey: .action)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encode(action, forKey: .action)
    }
}

public struct RuntimeRoutingRuleManifest: Equatable, Codable, Sendable {
    public static var empty: RuntimeRoutingRuleManifest {
        RuntimeRoutingRuleManifest(version: 1, rules: [])
    }

    public let version: Int
    public let rules: [RuntimeRoutingRule]

    public init(version: Int, rules: [RuntimeRoutingRule]) {
        self.version = version
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.rules = try container.decode([RuntimeRoutingRule].self, forKey: .rules)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(rules, forKey: .rules)
    }
}

public struct RuntimeSnapshot: Equatable, Codable, Sendable {
    public let id: SnapshotID
    public let selectedNode: ProxyNode
    public let routeMode: RouteMode
    public let logLevel: IrockLogLevel
    public let routingRuleManifest: RuntimeRoutingRuleManifest

    public init(id: SnapshotID, selectedNode: ProxyNode, routeMode: RouteMode, logLevel: IrockLogLevel) {
        self.init(
            id: id,
            selectedNode: selectedNode,
            routeMode: routeMode,
            logLevel: logLevel,
            routingRuleManifest: .empty
        )
    }

    public init(
        id: SnapshotID,
        selectedNode: ProxyNode,
        routeMode: RouteMode,
        logLevel: IrockLogLevel,
        routingRuleManifest: RuntimeRoutingRuleManifest
    ) {
        self.id = id
        self.selectedNode = selectedNode
        self.routeMode = routeMode
        self.logLevel = logLevel
        self.routingRuleManifest = routingRuleManifest
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case selectedNode
        case routeMode
        case logLevel
        case routingRuleManifest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(SnapshotID.self, forKey: .id)
        self.selectedNode = try container.decode(ProxyNode.self, forKey: .selectedNode)
        self.routeMode = try container.decode(RouteMode.self, forKey: .routeMode)
        self.logLevel = try container.decode(IrockLogLevel.self, forKey: .logLevel)
        self.routingRuleManifest = try container.decodeIfPresent(RuntimeRoutingRuleManifest.self, forKey: .routingRuleManifest) ?? .empty
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(selectedNode, forKey: .selectedNode)
        try container.encode(routeMode, forKey: .routeMode)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(routingRuleManifest, forKey: .routingRuleManifest)
    }
}
