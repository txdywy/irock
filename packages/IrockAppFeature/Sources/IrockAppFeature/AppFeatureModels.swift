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

public struct LocalProxyEndpoint: Equatable, Sendable {
    public let host: String
    public let socksPort: Int
    public let httpPort: Int

    public var socksAddress: String { "\(host):\(socksPort)" }
    public var httpAddress: String { "\(host):\(httpPort)" }
    public var displayAddress: String { "SOCKS \(socksAddress)，HTTP \(httpAddress)" }

    public init(host: String, socksPort: Int, httpPort: Int) {
        self.host = host
        self.socksPort = socksPort
        self.httpPort = httpPort
    }

    public init(host: String, port: Int) {
        self.init(host: host, socksPort: port, httpPort: port + 1)
    }
}

public struct SystemProxyGuidance: Equatable, Sendable {
    public let enableSOCKSCommand: String
    public let enableHTTPCommand: String
    public let disableCommand: String
    public let message: String

    public init(serviceName: String = "Wi-Fi", endpoint: LocalProxyEndpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)) {
        self.enableSOCKSCommand = "networksetup -setsocksfirewallproxy \(serviceName) \(endpoint.host) \(endpoint.socksPort)"
        self.enableHTTPCommand = "networksetup -setwebproxy \(serviceName) \(endpoint.host) \(endpoint.httpPort)"
        self.disableCommand = "networksetup -setsocksfirewallproxystate \(serviceName) off && networksetup -setwebproxystate \(serviceName) off"
        self.message = "无签名包不会静默修改系统代理；请复制命令或在系统设置中手动指向本地代理。"
    }
}

public struct PacketTunnelGuidance: Equatable, Sendable {
    public let message: String
    public let userModeTunMessage: String

    public init() {
        self.message = "Packet Tunnel 需要 Apple Developer Network Extension 权限和 App Group 签名；无签名包请使用本地 SOCKS/HTTP 代理。"
        self.userModeTunMessage = "用户态 TUN 需要 root/管理员授权创建 tun 设备；未授权时请退回本地代理或系统代理模式。"
    }
}

public enum ConnectResult: Equatable, Sendable {
    case localProxyStarted(LocalProxyEndpoint)
    case missingSelectedNode
    case runtimeSnapshotFailed(String)
    case localProxyFailed(String)
}

public struct UserModeTunEndpoint: Equatable, Sendable {
    public let interfaceName: String
    public let address: String
    public let gateway: String
    public let mtu: Int

    public var displayAddress: String { "\(interfaceName) \(address)/\(mtu)" }

    public init(interfaceName: String, address: String, gateway: String, mtu: Int) {
        self.interfaceName = interfaceName
        self.address = address
        self.gateway = gateway
        self.mtu = mtu
    }
}

public enum UserModeTunPhase: Equatable, Sendable {
    case stopped
    case running
    case failed
}

public struct UserModeTunState: Equatable, Sendable {
    public let phase: UserModeTunPhase
    public let endpoint: UserModeTunEndpoint?
    public let message: String

    public init(phase: UserModeTunPhase, endpoint: UserModeTunEndpoint?, message: String) {
        self.phase = phase
        self.endpoint = endpoint
        self.message = message
    }
}

public enum UserModeTunError: Error, Equatable, Sendable {
    case missingSelectedNode
    case missingCredential
    case authorizationRequired
    case unavailable
}

public protocol UserModeTunControlling: AnyObject {
    func start(node: ProxyNode, credential: String) throws -> UserModeTunEndpoint
    func stop() throws
}

public final class DisabledUserModeTunController: UserModeTunControlling {
    public init() {}

    public func start(node: ProxyNode, credential: String) throws -> UserModeTunEndpoint {
        throw UserModeTunError.unavailable
    }

    public func stop() throws {}
}

public enum LocalProxyPhase: Equatable, Sendable {
    case stopped
    case running
    case failed
}

public struct LocalProxyState: Equatable, Sendable {
    public let phase: LocalProxyPhase
    public let endpoint: LocalProxyEndpoint?
    public let message: String

    public init(phase: LocalProxyPhase, endpoint: LocalProxyEndpoint?, message: String) {
        self.phase = phase
        self.endpoint = endpoint
        self.message = message
    }
}

public enum LocalProxyError: Error, Equatable, Sendable {
    case missingSelectedNode
    case missingCredential
    case unsupportedCredential
    case unavailable
}

public protocol LocalProxyControlling: AnyObject {
    func start(node: ProxyNode, credential: String) throws -> LocalProxyEndpoint
    func stop() throws
}

public final class DisabledLocalProxyController: LocalProxyControlling {
    public init() {}

    public func start(node: ProxyNode, credential: String) throws -> LocalProxyEndpoint {
        throw LocalProxyError.unavailable
    }

    public func stop() throws {}
}
