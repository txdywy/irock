import Foundation
import IrockCore
import IrockDiagnostics
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
    @Published public private(set) var systemProxyGuidance: SystemProxyGuidance
    @Published public private(set) var packetTunnelGuidance: PacketTunnelGuidance

    private let logLimit: Int
    private let runtimeSnapshotPublisher: RuntimeSnapshotPublisher
    private let runtimeStatusStore: RuntimeStatusStore
    private let runtimeLogStore: RuntimeLogStore
    private let localProxyController: LocalProxyControlling
    private var importedCredentials: [NodeID: String]
    private var routingRuleText: String

    public init(
        nodes: [ProxyNode],
        logLimit: Int = 5,
        runtimeSnapshotStore: RuntimeSnapshotStore = InMemoryRuntimeSnapshotStore(),
        runtimeStatusStore: RuntimeStatusStore = InMemoryRuntimeStatusStore(),
        runtimeLogStore: RuntimeLogStore = InMemoryRuntimeLogStore(),
        localProxyController: LocalProxyControlling = DisabledLocalProxyController()
    ) {
        self.logLimit = max(0, logLimit)
        self.runtimeSnapshotPublisher = RuntimeSnapshotPublisher(store: runtimeSnapshotStore)
        self.runtimeStatusStore = runtimeStatusStore
        self.runtimeLogStore = runtimeLogStore
        self.localProxyController = localProxyController
        self.importedCredentials = [:]
        self.routingRuleText = ""
        self.runtimeConnectionStatus = nil
        self.runtimeLogs = []
        self.localProxyState = LocalProxyState(phase: .stopped, endpoint: nil, message: "本地代理未启动")
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
    public func importShadowsocksURI(_ text: String) throws -> ProxyNode {
        let draft = try URIImport.parseShadowsocksDraft(text)
        let node = try draft.buildNode(id: NodeID(rawValue: "imported-\(nodeListState.nodes.count + 1)"), keychainService: "com.irock.nodes")
        var nodes = nodeListState.nodes
        nodes.append(node)
        importedCredentials[node.id] = draft.credentialAccount
        nodeListState = NodeListState(nodes: nodes, selectedNodeID: node.id)
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: node, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
        appendLog("节点已导入：\(node.name)")
        return node
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
            do {
                let endpoint = try startLocalProxyMode()
                overviewState = OverviewState(connectionStatus: .connected, selectedNode: overviewState.selectedNode, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
                appendLog("连接已就绪：\(endpoint.displayAddress)")
                return .localProxyStarted(endpoint)
            } catch {
                return .localProxyFailed(localProxyState.message)
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
            appendLog("本地代理已停止")
        } catch {
            localProxyState = LocalProxyState(phase: .failed, endpoint: localProxyState.endpoint, message: "本地代理停止失败")
            appendLog("本地代理停止失败")
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
