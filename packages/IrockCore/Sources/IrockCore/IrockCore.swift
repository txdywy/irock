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
    case shadowsocksR
    case vmess
    case vless
    case trojan
    case hysteria2
    case tuic
    case socks
    case httpProxy
    case snell
    case wireGuard
    case ssh
    case trustTunnel

    public static let shadowrocketDisplayNames: [String] = [
        "Shadowsocks",
        "ShadowsocksR",
        "VMess",
        "VLESS",
        "Trojan",
        "Hysteria2",
        "TUIC",
        "SOCKS",
        "HTTP Proxy",
        "Snell",
        "WireGuard",
        "SSH",
        "TrustTunnel"
    ]
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

public struct WebSocketTransportOptions: Equatable, Codable, Sendable {
    public let host: String?
    public let path: String

    public init(host: String?, path: String) {
        self.host = host
        self.path = path
    }
}

public struct HTTP2TransportOptions: Equatable, Codable, Sendable {
    public let authority: String?
    public let path: String

    public init(authority: String?, path: String) {
        self.authority = authority
        self.path = path
    }
}

public struct GRPCTransportOptions: Equatable, Codable, Sendable {
    public let authority: String?
    public let service: String

    public init(authority: String?, service: String) {
        self.authority = authority
        self.service = service
    }
}

public struct TransportOptions: Equatable, Codable, Sendable {
    public let webSocket: WebSocketTransportOptions?
    public let http2: HTTP2TransportOptions?
    public let grpc: GRPCTransportOptions?

    public init(webSocket: WebSocketTransportOptions? = nil, http2: HTTP2TransportOptions? = nil, grpc: GRPCTransportOptions? = nil) {
        self.webSocket = webSocket
        self.http2 = http2
        self.grpc = grpc
    }
}

public struct Hysteria2RealmOptions: Equatable, Codable, Sendable {
    public let tokenReference: CredentialReference
    public let rendezvousHost: String
    public let rendezvousPort: Int?
    public let name: String
    public let useTLS: Bool
    public let stunServers: [String]
    public let localPort: Int?

    public init(tokenReference: CredentialReference, rendezvousHost: String, rendezvousPort: Int?, name: String, useTLS: Bool, stunServers: [String], localPort: Int?) {
        self.tokenReference = tokenReference
        self.rendezvousHost = rendezvousHost
        self.rendezvousPort = rendezvousPort
        self.name = name
        self.useTLS = useTLS
        self.stunServers = stunServers
        self.localPort = localPort
    }
}

public struct Hysteria2Options: Equatable, Codable, Sendable {
    public let realm: Hysteria2RealmOptions?

    public init(realm: Hysteria2RealmOptions?) {
        self.realm = realm
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
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case protocolType
        case serverHost
        case serverPort
        case credentialReference
        case transport
        case transportOptions
        case tls
        case udpPolicy
        case hysteria2
    }
    public let id: NodeID
    public let name: String
    public let protocolType: ProxyProtocolType
    public let serverHost: String
    public let serverPort: Int
    public let credentialReference: CredentialReference
    public let transport: TransportType
    public let transportOptions: TransportOptions
    public let tls: TLSOptions
    public let udpPolicy: UDPPolicy
    public let hysteria2: Hysteria2Options?

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
        self.init(
            id: id,
            name: name,
            protocolType: protocolType,
            serverHost: serverHost,
            serverPort: serverPort,
            credentialReference: credentialReference,
            transport: transport,
            transportOptions: TransportOptions(),
            tls: tls,
            udpPolicy: udpPolicy,
            hysteria2: nil
        )
    }

    public init(
        id: NodeID,
        name: String,
        protocolType: ProxyProtocolType,
        serverHost: String,
        serverPort: Int,
        credentialReference: CredentialReference,
        transport: TransportType,
        transportOptions: TransportOptions,
        tls: TLSOptions,
        udpPolicy: UDPPolicy,
        hysteria2: Hysteria2Options? = nil
    ) {
        self.id = id
        self.name = name
        self.protocolType = protocolType
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.credentialReference = credentialReference
        self.transport = transport
        self.transportOptions = transportOptions
        self.tls = tls
        self.udpPolicy = udpPolicy
        self.hysteria2 = hysteria2
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(NodeID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.protocolType = try container.decode(ProxyProtocolType.self, forKey: .protocolType)
        self.serverHost = try container.decode(String.self, forKey: .serverHost)
        self.serverPort = try container.decode(Int.self, forKey: .serverPort)
        self.credentialReference = try container.decode(CredentialReference.self, forKey: .credentialReference)
        self.transport = try container.decode(TransportType.self, forKey: .transport)
        self.transportOptions = try container.decodeIfPresent(TransportOptions.self, forKey: .transportOptions) ?? TransportOptions()
        self.tls = try container.decode(TLSOptions.self, forKey: .tls)
        self.udpPolicy = try container.decode(UDPPolicy.self, forKey: .udpPolicy)
        self.hysteria2 = try container.decodeIfPresent(Hysteria2Options.self, forKey: .hysteria2)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(protocolType, forKey: .protocolType)
        try container.encode(serverHost, forKey: .serverHost)
        try container.encode(serverPort, forKey: .serverPort)
        try container.encode(credentialReference, forKey: .credentialReference)
        try container.encode(transport, forKey: .transport)
        try container.encode(transportOptions, forKey: .transportOptions)
        try container.encode(tls, forKey: .tls)
        try container.encode(udpPolicy, forKey: .udpPolicy)
        try container.encodeIfPresent(hysteria2, forKey: .hysteria2)
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

// MARK: - Performance Types (from IrockPerformanceKit)

public struct RuntimePerformanceEvidence: Equatable, Sendable {
    public let bytesProcessed: Int
    public let elapsedNanoseconds: UInt64
    public let baselineLatencyMs: Int
    public let observedLatencyMs: Int
    public let tunnelMemoryMB: Int

    public init(bytesProcessed: Int, elapsedNanoseconds: UInt64, baselineLatencyMs: Int, observedLatencyMs: Int, tunnelMemoryMB: Int) {
        self.bytesProcessed = bytesProcessed
        self.elapsedNanoseconds = elapsedNanoseconds
        self.baselineLatencyMs = baselineLatencyMs
        self.observedLatencyMs = observedLatencyMs
        self.tunnelMemoryMB = tunnelMemoryMB
    }
}

public struct PerformanceMeasurement: Equatable, Sendable {
    public let throughputMbps: Int
    public let addedLatencyMs: Int
    public let tunnelMemoryMB: Int

    public init(throughputMbps: Int, addedLatencyMs: Int, tunnelMemoryMB: Int) {
        self.throughputMbps = throughputMbps
        self.addedLatencyMs = addedLatencyMs
        self.tunnelMemoryMB = tunnelMemoryMB
    }

    public init(runtimeEvidence: RuntimePerformanceEvidence) {
        let bitsProcessed = runtimeEvidence.bytesProcessed * 8
        let throughputMbps = runtimeEvidence.elapsedNanoseconds == 0 ? bitsProcessed / 1_000_000 : Int(UInt64(bitsProcessed) * 1_000 / runtimeEvidence.elapsedNanoseconds)
        self.init(
            throughputMbps: throughputMbps,
            addedLatencyMs: max(0, runtimeEvidence.observedLatencyMs - runtimeEvidence.baselineLatencyMs),
            tunnelMemoryMB: runtimeEvidence.tunnelMemoryMB
        )
    }
}

public enum PerformanceBudgetFailure: Equatable, Sendable {
    case throughputBelowMinimum
    case latencyAboveMaximum
    case memoryAboveMaximum
}

public struct PerformanceBudgetAssessment: Equatable, Sendable {
    public let measurement: PerformanceMeasurement
    public let budget: PerformanceBudget
    public let failures: [PerformanceBudgetFailure]

    public var passed: Bool { failures.isEmpty }

    public init(measurement: PerformanceMeasurement, budget: PerformanceBudget, failures: [PerformanceBudgetFailure]) {
        self.measurement = measurement
        self.budget = budget
        self.failures = failures
    }
}

public struct PerformanceBudget: Equatable, Sendable {
    public let minimumThroughputMbps: Int
    public let maximumAddedLatencyMs: Int
    public let maximumTunnelMemoryMB: Int

    public static let alphaFlagship = PerformanceBudget(
        minimumThroughputMbps: 600,
        maximumAddedLatencyMs: 10,
        maximumTunnelMemoryMB: 50
    )

    public init(minimumThroughputMbps: Int, maximumAddedLatencyMs: Int, maximumTunnelMemoryMB: Int) {
        self.minimumThroughputMbps = minimumThroughputMbps
        self.maximumAddedLatencyMs = maximumAddedLatencyMs
        self.maximumTunnelMemoryMB = maximumTunnelMemoryMB
    }

    public func assess(_ measurement: PerformanceMeasurement) -> PerformanceBudgetAssessment {
        var failures: [PerformanceBudgetFailure] = []
        if measurement.throughputMbps < minimumThroughputMbps {
            failures.append(.throughputBelowMinimum)
        }
        if measurement.addedLatencyMs > maximumAddedLatencyMs {
            failures.append(.latencyAboveMaximum)
        }
        if measurement.tunnelMemoryMB > maximumTunnelMemoryMB {
            failures.append(.memoryAboveMaximum)
        }
        return PerformanceBudgetAssessment(measurement: measurement, budget: self, failures: failures)
    }

    public func assess(runtimeEvidence: RuntimePerformanceEvidence) -> PerformanceBudgetAssessment {
        assess(PerformanceMeasurement(runtimeEvidence: runtimeEvidence))
    }
}

// MARK: - Connection Log Types (from IrockDiagnostics)

public struct ConnectionLogEntry: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct RingConnectionLog: Equatable, Sendable {
    public private(set) var entries: [ConnectionLogEntry]
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.entries = []
    }

    public mutating func append(_ entry: ConnectionLogEntry) {
        guard capacity > 0 else { return }
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }
}
