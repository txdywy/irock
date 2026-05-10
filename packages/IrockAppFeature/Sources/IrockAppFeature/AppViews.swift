import SwiftUI

public struct IrockRootView: View {
    @ObservedObject private var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            OverviewView(state: viewModel.overviewState)
                .tabItem { Text("概览") }
            NodeListView(state: viewModel.nodeListState)
                .tabItem { Text("节点") }
            LogListView(messages: viewModel.overviewState.recentLogMessages)
                .tabItem { Text("日志") }
            SettingsView(state: viewModel.settingsState)
                .tabItem { Text("设置") }
        }
    }
}

public struct OverviewView: View {
    public let state: OverviewState

    public init(state: OverviewState) {
        self.state = state
    }

    public var body: some View {
        List {
            Text(state.connectionStatus.displayText)
            Text(state.selectedNode?.name ?? "未选择节点")
            Text(state.routeMode.rawValue)
        }
    }
}

public struct NodeListView: View {
    public let state: NodeListState

    public init(state: NodeListState) {
        self.state = state
    }

    public var body: some View {
        List(state.nodes, id: \.id) { node in
            Text(node.name)
        }
    }
}

public struct LogListView: View {
    public let messages: [String]

    public init(messages: [String]) {
        self.messages = messages
    }

    public var body: some View {
        List(messages, id: \.self) { message in
            Text(message)
        }
    }
}

public struct SettingsView: View {
    public let state: SettingsState

    public init(state: SettingsState) {
        self.state = state
    }

    public var body: some View {
        List {
            Text("VPN 权限：\(state.vpnPermissionStatus)")
            Text("App Group：\(state.appGroupStatus)")
            Text("Debug 日志：\(state.debugLoggingEnabled ? "开启" : "关闭")")
        }
    }
}
