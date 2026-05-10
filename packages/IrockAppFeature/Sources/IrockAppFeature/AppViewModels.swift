import Foundation
import IrockCore

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var overviewState: OverviewState
    @Published public private(set) var nodeListState: NodeListState
    @Published public private(set) var settingsState: SettingsState

    private let logLimit: Int

    public init(nodes: [ProxyNode], logLimit: Int = 5) {
        self.logLimit = max(0, logLimit)
        self.nodeListState = NodeListState(nodes: nodes, selectedNodeID: nil)
        self.overviewState = OverviewState(connectionStatus: .disconnected, selectedNode: nil, routeMode: .ruleBased, recentLogMessages: [])
        self.settingsState = SettingsState(vpnPermissionStatus: "未配置", appGroupStatus: "未验证", debugLoggingEnabled: false)
    }

    public func selectNode(id: NodeID) {
        let selected = nodeListState.nodes.first { $0.id == id }
        nodeListState = NodeListState(nodes: nodeListState.nodes, selectedNodeID: selected?.id)
        overviewState = OverviewState(connectionStatus: overviewState.connectionStatus, selectedNode: selected, routeMode: overviewState.routeMode, recentLogMessages: overviewState.recentLogMessages)
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
