import Foundation
import IrockCore
import IrockDiagnostics
import IrockProtocols
import IrockRouting
import IrockStorage

public enum RuntimeFeedbackRefreshResult: Equatable, Sendable {
    case refreshed
    case statusLoadFailed(String)
    case logLoadFailed(String)
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var overviewState: OverviewState
    @Published public private(set) var nodeListState: NodeListState
    @Published public private(set) var settingsState: SettingsState
    @Published public private(set) var runtimeConnectionStatus: RuntimeConnectionStatus?
    @Published public private(set) var runtimeLogs: [RuntimeLogEntry]
    @Published public private(set) var localProxyState: LocalProxyState
    @Published public private(set) var userModeTunState: UserModeTunState
    @Published public private(set) var systemProxyGuidance: SystemProxyGuidance
    @Published public private(set) var packetTunnelGuidance: PacketTunnelGuidance

    private let logLimit: Int
    private let runtimeSnapshotPublisher: RuntimeSnapshotPublisher
    private let runtimeStatusStore: RuntimeStatusStore
    private let runtimeLogStore: RuntimeLogStore
    private let localProxyController: LocalProxyControlling
    private let userModeTunController: UserModeTunControlling
    private let userModeTunAuthorizationController: UserModeTunAuthorizationControlling
    private var importedCredentials: [NodeID: String]
    private var routingRuleText: String

    public init(
        nodes: [ProxyNode],
        logLimit: Int = 5,
        runtimeSnapshotStore: RuntimeSnapshotStore = InMemoryRuntimeSnapshotStore(),
        runtimeStatusStore: RuntimeStatusStore = InMemoryRuntimeStatusStore(),
        runtimeLogStore: RuntimeLogStore = InMemoryRuntimeLogStore(),
        localProxyController: LocalProxyControlling = DisabledLocalProxyController(),
        userModeTunController: UserModeTunControlling = DisabledUserModeTunController(),
        userModeTunAuthorizationController: UserModeTunAuthorizationControlling = DisabledUserModeTunAuthorizationController()
    ) {
        self.logLimit = max(0, logLimit)
        self.runtimeSnapshotPublisher = RuntimeSnapshotPublisher(store: runtimeSnapshotStore)
        self.runtimeStatusStore = runtimeStatusStore
        self.runtimeLogStore = runtimeLogStore
        self.localProxyController = localProxyController
        self.userModeTunController = userModeTunController
        self.userModeTunAuthorizationController = userModeTunAuthorizationController
        self.importedCredentials = [:]
        self.routingRuleText = ""
        self.runtimeConnectionStatus = nil
        self.runtimeLogs = []
        self.localProxyState = LocalProxyState(phase: .stopped, endpoint: nil, message: "本地代理未启动")
        self.userModeTunState = UserModeTunState(phase: .stopped, endpoint: nil, message: "用户态 TUN 未启动")
        self.systemProxyGuidance = SystemProxyGuidance()
        self.packetTunnelGuidance = PacketTunnelGuidance()
        self.nodeListState = NodeListState(nodes: nodes, selectedNodeID: nil)
        self.overviewState = OverviewState(connectionStatus: .disconnected, selectedNode: nil, routeMode: .ruleBased, recentLogMessages: [])
        self.settingsState = SettingsState(vpnPermissionStatus: "未配置", appGroupStatus: "未验证", debugLoggingEnabled: false)
    }

    public func selectNode(id: NodeID) {
        let selected = nodeListState.nodes.first { $0.id == id }
        nodeListState = NodeListState(nodes: nodeListState.nodes, selectedNodeID: selected?.id)
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: selected, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
    }

    @discardableResult
    public func importURI(_ text: String) throws -> ProxyNode {
        let draft = try URIImport.parseDraft(text)
        let node = try draft.buildNode(id: NodeID(rawValue: "imported-\(nodeListState.nodes.count + 1)"), keychainService: "com.irock.nodes")
        var nodes = nodeListState.nodes
        nodes.append(node)
        importedCredentials[node.id] = draft.credentialAccount
        if let realm = draft.hysteria2Realm {
            importedCredentials[NodeID(rawValue: "\(node.id.rawValue).hysteria2.realm-token")] = realm.token
        }
        nodeListState = NodeListState(nodes: nodes, selectedNodeID: node.id)
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: node, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
        appendLog("节点已导入：\(node.name)")
        return node
    }

    @discardableResult
    public func importShadowsocksURI(_ text: String) throws -> ProxyNode {
        try importURI(text)
    }

    @discardableResult
    public func startLocalProxyMode() throws -> LocalProxyEndpoint {
        guard let node = overviewState.selectedNode else {
            localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "请选择节点后再启动本地代理")
            appendLog("请选择节点后再启动本地代理")
            throw LocalProxyError.missingSelectedNode
        }
        guard let credential = importedCredentials[node.id] else {
            localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "本地代理缺少节点凭据")
            appendLog("本地代理缺少节点凭据")
            throw LocalProxyError.missingCredential
        }
        guard node.protocolType == .shadowsocks else {
            localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "当前协议请使用用户态 TUN 连接")
            appendLog("当前协议请使用用户态 TUN 连接")
            throw LocalProxyError.unsupportedCredential
        }
        guard ShadowsocksStreamRequest.supportsCredential(credential) else {
            localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "当前 Shadowsocks 加密方法暂不支持本地代理")
            appendLog("当前 Shadowsocks 加密方法暂不支持本地代理")
            throw LocalProxyError.unsupportedCredential
        }
        let endpoint = try localProxyController.start(node: node, credential: credential)
        localProxyState = LocalProxyState(phase: .running, endpoint: endpoint, message: "本地代理已启动：\(endpoint.displayAddress)")
        systemProxyGuidance = SystemProxyGuidance(endpoint: endpoint)
        appendLog("本地代理已启动：\(endpoint.displayAddress)")
        return endpoint
    }

    @discardableResult
    public func connect() -> ConnectResult {
        switch publishRuntimeSnapshot() {
        case .published:
            guard let node = overviewState.selectedNode else {
                return .missingSelectedNode
            }
            if node.protocolType == .shadowsocks {
                do {
                    let endpoint = try startLocalProxyMode()
                    overviewState = OverviewState(connectionStatus: .connected, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
                    appendLog("连接已就绪：\(endpoint.displayAddress)")
                    return .localProxyStarted(endpoint)
                } catch {
                    if localProxyState.phase == .failed {
                        return .localProxyFailed(localProxyState.message)
                    }
                    localProxyState = LocalProxyState(phase: .failed, endpoint: nil, message: "本地代理启动失败")
                    appendLog("本地代理启动失败")
                    return .localProxyFailed(localProxyState.message)
                }
            }
            do {
                let endpoint = try startUserModeTunMode()
                appendLog("连接已就绪：\(endpoint.displayAddress)")
                return .userModeTunStarted(endpoint)
            } catch {
                return .userModeTunFailed(userModeTunState.message)
            }
        case .missingSelectedNode:
            return .missingSelectedNode
        case let .storageFailed(message):
            return .runtimeSnapshotFailed(message)
        }
    }

    public func stopLocalProxyMode() {
        do {
            try localProxyController.stop()
            localProxyState = LocalProxyState(phase: .stopped, endpoint: nil, message: "本地代理已停止")
            overviewState = OverviewState(connectionStatus: .disconnected, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
            appendLog("本地代理已停止")
        } catch {
            localProxyState = LocalProxyState(phase: .failed, endpoint: localProxyState.endpoint, message: "本地代理停止失败")
            overviewState = OverviewState(connectionStatus: .failed, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
            appendLog("本地代理停止失败")
        }
    }

    public func stopConnection() {
        let shouldStopLocalProxy = localProxyState.phase == .running
        let shouldStopUserModeTun = userModeTunState.phase == .running
        if shouldStopLocalProxy {
            stopLocalProxyMode()
        }
        let localProxyFailed = localProxyState.phase == .failed
        if shouldStopUserModeTun {
            stopUserModeTunMode()
        }
        if localProxyFailed || userModeTunState.phase == .failed {
            overviewState = OverviewState(connectionStatus: .failed, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
        } else if !shouldStopLocalProxy && !shouldStopUserModeTun {
            overviewState = OverviewState(connectionStatus: .disconnected, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
        }
    }

    @discardableResult
    public func startUserModeTunMode() throws -> UserModeTunEndpoint {
        guard let node = overviewState.selectedNode else {
            userModeTunState = UserModeTunState(phase: .failed, endpoint: nil, message: "请选择节点后再启动用户态 TUN")
            appendLog("请选择节点后再启动用户态 TUN")
            throw UserModeTunError.missingSelectedNode
        }
        guard let credential = importedCredentials[node.id] else {
            userModeTunState = UserModeTunState(phase: .failed, endpoint: nil, message: "用户态 TUN 缺少节点凭据")
            appendLog("用户态 TUN 缺少节点凭据")
            throw UserModeTunError.missingCredential
        }
        guard case .published = publishRuntimeSnapshot() else {
            userModeTunState = UserModeTunState(phase: .failed, endpoint: nil, message: "用户态 TUN 运行配置发布失败")
            appendLog("用户态 TUN 运行配置发布失败")
            throw UserModeTunError.unavailable
        }
        do {
            let endpoint = try userModeTunController.start(node: node, credential: credential)
            userModeTunState = UserModeTunState(phase: .running, endpoint: endpoint, message: "用户态 TUN 已启动：\(endpoint.displayAddress)")
            overviewState = OverviewState(connectionStatus: .connected, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
            appendLog("用户态 TUN 已启动：\(endpoint.displayAddress)")
            return endpoint
        } catch UserModeTunError.authorizationRequired {
            userModeTunState = UserModeTunState(phase: .authorizationRequired, endpoint: nil, message: "用户态 TUN 需要管理员授权")
            appendLog("用户态 TUN 需要管理员授权")
            throw UserModeTunError.authorizationRequired
        } catch {
            userModeTunState = UserModeTunState(phase: .failed, endpoint: nil, message: "用户态 TUN 启动失败")
            appendLog("用户态 TUN 启动失败")
            throw UserModeTunError.unavailable
        }
    }

    public func requestUserModeTunAuthorization() {
        userModeTunState = UserModeTunState(phase: .authorizing, endpoint: nil, message: "正在请求管理员授权…")
        appendLog("正在请求管理员授权…")
        switch userModeTunAuthorizationController.requestAuthorization() {
        case let .instructionsReady(command):
            userModeTunState = UserModeTunState(phase: .authorizationRequired, endpoint: nil, message: "请在终端手动运行管理员启动命令：\(command)")
            appendLog("请在终端手动运行管理员启动命令：\(command)")
        case let .unavailable(message):
            userModeTunState = UserModeTunState(phase: .authorizationRequired, endpoint: nil, message: message)
            appendLog(message)
        }
    }

    public func stopUserModeTunMode() {
        do {
            try userModeTunController.stop()
            userModeTunState = UserModeTunState(phase: .stopped, endpoint: nil, message: "用户态 TUN 已停止")
            overviewState = OverviewState(connectionStatus: localProxyState.phase == .running ? .connected : .disconnected, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
            appendLog("用户态 TUN 已停止")
        } catch {
            userModeTunState = UserModeTunState(phase: .failed, endpoint: userModeTunState.endpoint, message: "用户态 TUN 停止失败")
            overviewState = OverviewState(connectionStatus: .failed, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
            appendLog("用户态 TUN 停止失败")
        }
    }

    public func setRouteMode(_ routeMode: RouteMode) {
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: overviewState.selectedNode, routeMode: routeMode, recentLogMessages: overviewState.recentLogMessages)
    }

    public func setDebugLoggingEnabled(_ enabled: Bool) {
        settingsState = SettingsState(vpnPermissionStatus: settingsState.vpnPermissionStatus, appGroupStatus: settingsState.appGroupStatus, debugLoggingEnabled: enabled)
    }

    public func setRoutingRuleText(_ text: String) {
        routingRuleText = text
    }

    @discardableResult
    public func publishRuntimeSnapshot() -> RuntimeSnapshotPublishResult {
        let logLevel: IrockLogLevel = settingsState.debugLoggingEnabled ? .debug : .user
        let routingRuleManifest: RuntimeRoutingRuleManifest
        do {
            routingRuleManifest = try RoutingRuleManifestBuilder.buildManifest(from: routingRuleText)
        } catch let error as RoutingRuleParseError {
            let message = UserFacingDiagnostics.message(for: .routingFailure(error))
            appendLog(message)
            return .storageFailed(message)
        } catch {
            let message = UserFacingDiagnostics.message(for: .snapshotPublishFailed)
            appendLog(message)
            return .storageFailed(message)
        }

        let result = runtimeSnapshotPublisher.publish(selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, logLevel: logLevel, routingRuleManifest: routingRuleManifest)

        switch result {
        case .published:
            appendLog("运行配置已发布")
        case .missingSelectedNode:
            appendLog("请选择节点后再启动")
        case .storageFailed:
            appendLog("运行配置发布失败")
        }

        return result
    }

    @discardableResult
    public func refreshRuntimeFeedback() -> RuntimeFeedbackRefreshResult {
        let status: RuntimeConnectionStatus
        do {
            status = try runtimeStatusStore.load() ?? .disconnected()
        } catch {
            return .statusLoadFailed(UserFacingDiagnostics.message(for: .statusLoadFailed))
        }

        runtimeConnectionStatus = status
        overviewState = OverviewState(
            connectionStatus: appConnectionStatus(from: status.phase),
            selectedNode: overviewState.selectedNode,
            routeMode: overviewState.routeMode,
            recentLogMessages: overviewState.recentLogMessages
        )

        let logs: [RuntimeLogEntry]
        do {
            logs = try runtimeLogStore.loadRecent()
        } catch {
            return .logLoadFailed(UserFacingDiagnostics.message(for: .logLoadFailed))
        }

        runtimeLogs = logs
        overviewState = OverviewState(
            connectionStatus: appConnectionStatus(from: status.phase),
            selectedNode: overviewState.selectedNode,
            routeMode: overviewState.routeMode,
            recentLogMessages: Array(logs.suffix(logLimit).map(\.message))
        )
        return .refreshed
    }

    private func appConnectionStatus(from phase: RuntimeConnectionPhase) -> ConnectionStatus {
        switch phase {
        case .disconnected, .disconnecting:
            return .disconnected
        case .preparing, .connecting, .reconnecting:
            return .connecting
        case .connected:
            return .connected
        case .failed:
            return .failed
        }
    }

    public func appendLog(_ message: String) {
        var messages = overviewState.recentLogMessages
        messages.append(message)
        if messages.count > logLimit {
            messages.removeFirst(messages.count - logLimit)
        }
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: messages)
    }
}
