import SwiftUI

public struct IrockRootView: View {
    @ObservedObject private var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            OverviewView(state: viewModel.overviewState, localProxyState: viewModel.localProxyState)
                .tabItem { Text("概览") }
            NodeListView(viewModel: viewModel)
                .tabItem { Text("节点") }
            LogListView(messages: viewModel.overviewState.recentLogMessages)
                .tabItem { Text("日志") }
            SettingsView(state: viewModel.settingsState, systemProxyGuidance: viewModel.systemProxyGuidance, packetTunnelGuidance: viewModel.packetTunnelGuidance)
                .tabItem { Text("设置") }
        }
    }
}

public struct OverviewView: View {
    public let state: OverviewState
    public let localProxyState: LocalProxyState

    public init(state: OverviewState, localProxyState: LocalProxyState = LocalProxyState(phase: .stopped, endpoint: nil, message: "本地代理未启动")) {
        self.state = state
        self.localProxyState = localProxyState
    }

    public var body: some View {
        List {
            Text(state.connectionStatus.displayText)
            Text(state.selectedNode?.name ?? "未选择节点")
            Text(state.routeMode.rawValue)
            Text(localProxyState.message)
            if let endpoint = localProxyState.endpoint {
                Text("SOCKS：\(endpoint.socksAddress)")
                Text("HTTP：\(endpoint.httpAddress)")
            }
        }
    }
}

public struct NodeListView: View {
    @ObservedObject private var viewModel: AppViewModel
    @State private var uriText = ""

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            Section("导入节点") {
                TextField("粘贴 ss:// 节点链接", text: $uriText)
                Button("导入 Shadowsocks 节点") {
                    do {
                        _ = try viewModel.importShadowsocksURI(uriText)
                        uriText = ""
                    } catch {
                        viewModel.appendLog("节点导入失败")
                    }
                }
                Button("发布运行配置") {
                    _ = viewModel.publishRuntimeSnapshot()
                }
                Button("连接（本地代理）") {
                    _ = viewModel.connect()
                }
                Button("停止本地代理") {
                    viewModel.stopLocalProxyMode()
                }
                Button("刷新运行状态") {
                    _ = viewModel.refreshRuntimeFeedback()
                }
                Text(viewModel.localProxyState.message)
                if let endpoint = viewModel.localProxyState.endpoint {
                    Text("SOCKS：\(endpoint.socksAddress)")
                    Text("HTTP：\(endpoint.httpAddress)")
                }
            }
            Section("节点") {
                ForEach(viewModel.nodeListState.nodes, id: \.id) { node in
                    Button(node.name) {
                        viewModel.selectNode(id: node.id)
                    }
                }
            }
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
    public let systemProxyGuidance: SystemProxyGuidance
    public let packetTunnelGuidance: PacketTunnelGuidance

    public init(
        state: SettingsState,
        systemProxyGuidance: SystemProxyGuidance = SystemProxyGuidance(),
        packetTunnelGuidance: PacketTunnelGuidance = PacketTunnelGuidance()
    ) {
        self.state = state
        self.systemProxyGuidance = systemProxyGuidance
        self.packetTunnelGuidance = packetTunnelGuidance
    }

    public var body: some View {
        List {
            Section("运行能力") {
                Text("VPN 权限：\(state.vpnPermissionStatus)")
                Text("App Group：\(state.appGroupStatus)")
                Text("Debug 日志：\(state.debugLoggingEnabled ? "开启" : "关闭")")
                Text(packetTunnelGuidance.message)
                Text(packetTunnelGuidance.userModeTunMessage)
            }
            Section("系统代理命令") {
                Text(systemProxyGuidance.message)
                Text(systemProxyGuidance.enableSOCKSCommand)
                Text(systemProxyGuidance.enableHTTPCommand)
                Text(systemProxyGuidance.disableCommand)
            }
        }
    }
}
