import IrockCore

public enum IrockAppFeatureModule {
    public static let name = "IrockAppFeature"
}

public enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case preparing
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case failed

    public var displayText: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .preparing, .connecting, .reconnecting:
            return "连接中"
        case .connected:
            return "已连接"
        case .disconnecting:
            return "断开中"
        case .failed:
            return "连接失败"
        }
    }
}

public struct OverviewState: Equatable, Sendable {
    public let connectionStatus: ConnectionStatus
    public let selectedNode: ProxyNode?
    public let routeMode: RouteMode
    public let recentLogMessages: [String]

    public init(connectionStatus: ConnectionStatus, selectedNode: ProxyNode?, routeMode: RouteMode, recentLogMessages: [String]) {
        self.connectionStatus = connectionStatus
        self.selectedNode = selectedNode
        self.routeMode = routeMode
        self.recentLogMessages = recentLogMessages
    }
}

public struct NodeListState: Equatable, Sendable {
    public let nodes: [ProxyNode]
    public let selectedNodeID: NodeID?

    public init(nodes: [ProxyNode], selectedNodeID: NodeID?) {
        self.nodes = nodes
        self.selectedNodeID = selectedNodeID
    }
}

public struct SettingsState: Equatable, Sendable {
    public let vpnPermissionStatus: String
    public let appGroupStatus: String
    public let debugLoggingEnabled: Bool

    public init(vpnPermissionStatus: String, appGroupStatus: String, debugLoggingEnabled: Bool) {
        self.vpnPermissionStatus = vpnPermissionStatus
        self.appGroupStatus = appGroupStatus
        self.debugLoggingEnabled = debugLoggingEnabled
    }
}
