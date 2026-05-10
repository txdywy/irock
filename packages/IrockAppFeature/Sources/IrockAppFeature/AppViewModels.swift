import Foundation
import IrockCore
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

    private let logLimit: Int
    private let runtimeSnapshotPublisher: RuntimeSnapshotPublisher
    private let runtimeStatusStore: RuntimeStatusStore
    private let runtimeLogStore: RuntimeLogStore
    private var routingRuleText: String

    public init(
        nodes: [ProxyNode],
        logLimit: Int = 5,
        runtimeSnapshotStore: RuntimeSnapshotStore = InMemoryRuntimeSnapshotStore(),
        runtimeStatusStore: RuntimeStatusStore = InMemoryRuntimeStatusStore(),
        runtimeLogStore: RuntimeLogStore = InMemoryRuntimeLogStore()
    ) {
        self.logLimit = max(0, logLimit)
        self.runtimeSnapshotPublisher = RuntimeSnapshotPublisher(store: runtimeSnapshotStore)
        self.runtimeStatusStore = runtimeStatusStore
        self.runtimeLogStore = runtimeLogStore
        self.routingRuleText = ""
        self.runtimeConnectionStatus = nil
        self.runtimeLogs = []
        self.nodeListState = NodeListState(nodes: nodes, selectedNodeID: nil)
        self.overviewState = OverviewState(connectionStatus: .disconnected, selectedNode: nil, routeMode: .ruleBased, recentLogMessages: [])
        self.settingsState = SettingsState(vpnPermissionStatus: "未配置", appGroupStatus: "未验证", debugLoggingEnabled: false)
    }

    public func selectNode(id: NodeID) {
        let selected = nodeListState.nodes.first { $0.id == id }
        nodeListState = NodeListState(nodes: nodeListState.nodes, selectedNodeID: selected?.id)
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: selected, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
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
        } catch {
            appendLog("Routing rules invalid: \(error)")
            return .storageFailed(String(describing: error))
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
            return .statusLoadFailed(String(describing: error))
        }

        let logs: [RuntimeLogEntry]
        do {
            logs = try runtimeLogStore.loadRecent()
        } catch {
            return .logLoadFailed(String(describing: error))
        }

        runtimeConnectionStatus = status
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
