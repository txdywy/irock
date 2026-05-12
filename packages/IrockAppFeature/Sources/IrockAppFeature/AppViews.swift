import IrockCore
import SwiftUI

public struct IrockRootView: View {
    @ObservedObject private var viewModel: AppViewModel
    @State private var selection: IrockAppSection? = .overview

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                overviewState: viewModel.overviewState,
                localProxyState: viewModel.localProxyState,
                userModeTunState: viewModel.userModeTunState
            )
        } detail: {
            detailView
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        HeaderStatusBadge(status: viewModel.overviewState.connectionStatus)
                        Button("刷新") {
                            _ = viewModel.refreshRuntimeFeedback()
                        }
                        Button(viewModel.overviewState.connectionStatus == .connected ? "停止" : "连接") {
                            if viewModel.overviewState.connectionStatus == .connected {
                                viewModel.stopConnection()
                            } else {
                                _ = viewModel.connect()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
        }
        .background(IrockDesign.background)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(
                state: viewModel.overviewState,
                localProxyState: viewModel.localProxyState,
                userModeTunState: viewModel.userModeTunState
            )
        case .nodes:
            NodeListView(viewModel: viewModel)
        case .logs:
            LogListView(messages: viewModel.overviewState.recentLogMessages)
        case .settings:
            SettingsView(
                state: viewModel.settingsState,
                systemProxyGuidance: viewModel.systemProxyGuidance,
                packetTunnelGuidance: viewModel.packetTunnelGuidance
            )
        }
    }
}

public struct OverviewView: View {
    public let state: OverviewState
    public let localProxyState: LocalProxyState
    public let userModeTunState: UserModeTunState

    public init(
        state: OverviewState,
        localProxyState: LocalProxyState = LocalProxyState(phase: .stopped, endpoint: nil, message: "本地代理未启动"),
        userModeTunState: UserModeTunState = UserModeTunState(phase: .stopped, endpoint: nil, message: "用户态 TUN 未启动")
    ) {
        self.state = state
        self.localProxyState = localProxyState
        self.userModeTunState = userModeTunState
    }

    public var body: some View {
        IrockScreen(title: "概览", subtitle: "连接状态、运行入口和最近活动") {
            VStack(spacing: IrockDesign.sectionSpacing) {
                ConnectionHeroCard(state: state, localProxyState: localProxyState, userModeTunState: userModeTunState)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    RuntimeStatusCard(
                        title: "本地代理",
                        value: localProxyState.phase.displayText,
                        detail: localProxyState.endpoint?.displayAddress ?? localProxyState.message,
                        tint: localProxyState.phase.tint,
                        symbolName: "network"
                    )
                    RuntimeStatusCard(
                        title: "用户态 TUN",
                        value: userModeTunState.phase.displayText,
                        detail: userModeTunState.endpoint?.displayAddress ?? userModeTunState.message,
                        tint: userModeTunState.phase.tint,
                        symbolName: "point.3.connected.trianglepath.dotted"
                    )
                    RuntimeStatusCard(
                        title: "路由模式",
                        value: state.routeMode.displayText,
                        detail: state.routeMode.detailText,
                        tint: IrockDesign.info,
                        symbolName: "arrow.triangle.branch"
                    )
                }

                IrockCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "最近活动", subtitle: state.recentLogMessages.isEmpty ? "暂无运行日志" : "最新 \(state.recentLogMessages.count) 条事件")
                        if state.recentLogMessages.isEmpty {
                            EmptyStateView(symbolName: "waveform.path.ecg.rectangle", title: "等待运行事件", message: "导入节点、连接代理或刷新运行状态后会显示活动记录。")
                        } else {
                            VStack(spacing: 8) {
                                ForEach(state.recentLogMessages, id: \.self) { message in
                                    LogFeedRow(message: message)
                                }
                            }
                        }
                    }
                }
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
        IrockScreen(title: "节点", subtitle: "导入、选择并启动本地代理或用户态 TUN") {
            VStack(spacing: IrockDesign.sectionSpacing) {
                NodeActionPanel(viewModel: viewModel, uriText: $uriText)

                IrockCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "节点列表", subtitle: viewModel.nodeListState.nodes.isEmpty ? "尚未导入节点" : "\(viewModel.nodeListState.nodes.count) 个可用节点")
                        if viewModel.nodeListState.nodes.isEmpty {
                            EmptyStateView(symbolName: "tray", title: "还没有节点", message: "粘贴 Shadowsocks URI 并导入后，节点会以高密度列表显示在这里。")
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(viewModel.nodeListState.nodes, id: \.id) { node in
                                    NodeRowView(
                                        node: node,
                                        isSelected: node.id == viewModel.nodeListState.selectedNodeID,
                                        isConnected: node.id == viewModel.overviewState.selectedNode?.id && viewModel.overviewState.connectionStatus == .connected
                                    ) {
                                        viewModel.selectNode(id: node.id)
                                    } connect: {
                                        viewModel.selectNode(id: node.id)
                                        _ = viewModel.connect()
                                    }
                                }
                            }
                        }
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
        IrockScreen(title: "日志", subtitle: "运行时事件与用户可读诊断") {
            IrockCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "活动 Feed", subtitle: messages.isEmpty ? "暂无日志" : "保留最近 \(messages.count) 条")
                    if messages.isEmpty {
                        EmptyStateView(symbolName: "doc.text.magnifyingglass", title: "暂无日志", message: "连接、导入、发布配置和 TUN 操作会出现在这里。")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(messages, id: \.self) { message in
                                LogFeedRow(message: message)
                            }
                        }
                    }
                }
            }
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
        IrockScreen(title: "设置", subtitle: "运行能力、签名限制和系统代理指引") {
            VStack(spacing: IrockDesign.sectionSpacing) {
                IrockCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "运行能力", subtitle: "当前构建与本机权限状态")
                        CapabilityRow(title: "VPN 权限", value: state.vpnPermissionStatus, symbolName: "shield")
                        CapabilityRow(title: "App Group", value: state.appGroupStatus, symbolName: "folder.badge.gearshape")
                        CapabilityRow(title: "Debug 日志", value: state.debugLoggingEnabled ? "开启" : "关闭", symbolName: "ladybug")
                    }
                }

                IrockCard(tint: IrockDesign.warning) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "无签名包限制", subtitle: "系统级能力需要显式授权")
                        GuidanceText(packetTunnelGuidance.message)
                        GuidanceText(packetTunnelGuidance.userModeTunMessage)
                    }
                }

                IrockCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "系统代理命令", subtitle: systemProxyGuidance.message)
                        CommandBlockView(title: "启用 SOCKS", command: systemProxyGuidance.enableSOCKSCommand)
                        CommandBlockView(title: "启用 HTTP", command: systemProxyGuidance.enableHTTPCommand)
                        CommandBlockView(title: "关闭代理", command: systemProxyGuidance.disableCommand)
                    }
                }
            }
        }
    }
}

private enum IrockAppSection: String, CaseIterable, Hashable, Identifiable {
    case overview
    case nodes
    case logs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .nodes: "节点"
        case .logs: "日志"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .nodes: "server.rack"
        case .logs: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
}

private struct SidebarView: View {
    @Binding var selection: IrockAppSection?
    let overviewState: OverviewState
    let localProxyState: LocalProxyState
    let userModeTunState: UserModeTunState

    var body: some View {
        List(IrockAppSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.symbolName)
                .tag(section)
        }
        .navigationTitle("irock")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                SidebarStatusLine(title: overviewState.connectionStatus.displayText, tint: overviewState.connectionStatus.tint)
                if let endpoint = localProxyState.endpoint {
                    SidebarEndpointLine(title: "SOCKS", value: endpoint.socksAddress)
                }
                if let endpoint = userModeTunState.endpoint {
                    SidebarEndpointLine(title: "TUN", value: endpoint.interfaceName)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
        }
    }
}

private struct IrockScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .padding(26)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(IrockDesign.background)
    }
}

private struct ConnectionHeroCard: View {
    let state: OverviewState
    let localProxyState: LocalProxyState
    let userModeTunState: UserModeTunState

    var body: some View {
        IrockCard(tint: state.connectionStatus.tint) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusPill(title: state.connectionStatus.displayText, tint: state.connectionStatus.tint, symbolName: state.connectionStatus.symbolName)
                        Text(state.selectedNode?.name ?? "未选择节点")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(state.selectedNode?.endpointDisplayText ?? "导入并选择节点后即可启动本地代理或用户态 TUN")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(state.routeMode.displayText)
                            .font(.headline)
                        Text("路由策略")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    EndpointPill(title: "SOCKS", value: localProxyState.endpoint?.socksAddress ?? "未启动", tint: localProxyState.phase.tint)
                    EndpointPill(title: "HTTP", value: localProxyState.endpoint?.httpAddress ?? "未启动", tint: localProxyState.phase.tint)
                    EndpointPill(title: "TUN", value: userModeTunState.endpoint?.displayAddress ?? "未启动", tint: userModeTunState.phase.tint)
                }
            }
        }
    }
}

private struct RuntimeStatusCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let symbolName: String

    var body: some View {
        IrockCard(tint: tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbolName)
                        .foregroundStyle(tint)
                    Spacer()
                    StatusDot(tint: tint)
                }
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NodeActionPanel: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var uriText: String

    var body: some View {
        IrockCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "快速操作", subtitle: "导入配置后选择节点并启动运行模式")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        importField
                        importButton
                    }
                    VStack(spacing: 10) {
                        importField
                        importButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    primaryActionRow
                    VStack(alignment: .leading, spacing: 10) {
                        Button("连接本地代理") { _ = viewModel.connect() }
                            .buttonStyle(.borderedProminent)
                        Button("停止代理") { viewModel.stopLocalProxyMode() }
                        Button("启动用户态 TUN") {
                            do { _ = try viewModel.startUserModeTunMode() } catch {}
                        }
                        Button("停止 TUN") { viewModel.stopUserModeTunMode() }
                        Menu("高级") {
                            Button("发布运行配置") { _ = viewModel.publishRuntimeSnapshot() }
                            Button("刷新运行状态") { _ = viewModel.refreshRuntimeFeedback() }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        statusPills
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        statusPills
                    }
                }
            }
        }
    }

    private var importField: some View {
        TextField("粘贴 ss:// 节点链接", text: $uriText)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospaced())
    }

    private var importButton: some View {
        Button("导入") {
            do {
                _ = try viewModel.importShadowsocksURI(uriText)
                uriText = ""
            } catch {
                viewModel.appendLog("节点导入失败")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(uriText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var primaryActionRow: some View {
        HStack(spacing: 10) {
            Button("连接本地代理") { _ = viewModel.connect() }
                .buttonStyle(.borderedProminent)
            Button("停止代理") { viewModel.stopLocalProxyMode() }
            tunnelControls
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private var tunnelControls: some View {
        Button("启动用户态 TUN") {
            do { _ = try viewModel.startUserModeTunMode() } catch {}
        }
        Button("停止 TUN") { viewModel.stopUserModeTunMode() }
        Menu("高级") {
            Button("发布运行配置") { _ = viewModel.publishRuntimeSnapshot() }
            Button("刷新运行状态") { _ = viewModel.refreshRuntimeFeedback() }
        }
    }

    @ViewBuilder
    private var statusPills: some View {
        StatusPill(title: viewModel.localProxyState.message, tint: viewModel.localProxyState.phase.tint, symbolName: "network")
        StatusPill(title: viewModel.userModeTunState.message, tint: viewModel.userModeTunState.phase.tint, symbolName: "point.3.connected.trianglepath.dotted")
    }
}

private struct NodeRowView: View {
    let node: ProxyNode
    let isSelected: Bool
    let isConnected: Bool
    let select: () -> Void
    let connect: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? IrockDesign.accent : .clear)
                    .frame(width: 4, height: 40)
                ProtocolBadge(text: node.protocolType.shortDisplayText)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(node.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if isConnected {
                            StatusPill(title: "已连接", tint: IrockDesign.success, symbolName: "checkmark.circle.fill")
                        } else if isSelected {
                            StatusPill(title: "已选中", tint: IrockDesign.info, symbolName: "checkmark")
                        }
                    }
                    Text(node.endpointDisplayText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    MetadataPill(node.transport.displayText)
                    MetadataPill(node.tls.displayText)
                    MetadataPill(node.udpPolicy.displayText)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? IrockDesign.accent.opacity(0.14) : IrockDesign.surfaceElevated.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? IrockDesign.accent.opacity(0.46) : IrockDesign.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2, perform: connect)
    }
}

private struct IrockCard<Content: View>: View {
    var tint: Color = IrockDesign.border
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.12), radius: 24, y: 12)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(IrockDesign.info)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct LogFeedRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(tint: message.logTint)
                .padding(.top, 5)
            Text(message)
                .font(.callout.monospaced())
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(IrockDesign.surfaceElevated.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(IrockDesign.border, lineWidth: 1)
        )
    }
}

private struct CapabilityRow: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .frame(width: 24)
                .foregroundStyle(IrockDesign.info)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct CommandBlockView: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(command)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(IrockDesign.surfaceElevated.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(IrockDesign.border, lineWidth: 1)
                )
        }
    }
}

private struct GuidanceText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private struct HeaderStatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        StatusPill(title: status.displayText, tint: status.tint, symbolName: status.symbolName)
    }
}

private struct StatusPill: View {
    let title: String
    let tint: Color
    let symbolName: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().stroke(tint.opacity(0.28), lineWidth: 1))
    }
}

private struct EndpointPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.22), lineWidth: 1))
    }
}

private struct ProtocolBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold).monospaced())
            .foregroundStyle(.black)
            .frame(width: 42, height: 30)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(IrockDesign.accent))
    }
}

private struct MetadataPill: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(IrockDesign.surfaceElevated.opacity(0.85)))
            .overlay(Capsule().stroke(IrockDesign.border, lineWidth: 1))
    }
}

private struct StatusDot: View {
    let tint: Color

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 9, height: 9)
            .shadow(color: tint.opacity(0.55), radius: 8)
    }
}

private struct SidebarStatusLine: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(tint: tint)
            Text(title)
                .font(.caption.weight(.semibold))
        }
    }
}

private struct SidebarEndpointLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
    }
}

private enum IrockDesign {
    static let background = LinearGradient(
        colors: [Color(red: 0.03, green: 0.04, blue: 0.06), Color(red: 0.06, green: 0.08, blue: 0.11)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let surfaceElevated = Color(red: 0.09, green: 0.12, blue: 0.16)
    static let border = Color.white.opacity(0.1)
    static let accent = Color(red: 0.46, green: 0.97, blue: 0.63)
    static let success = Color(red: 0.46, green: 0.97, blue: 0.63)
    static let warning = Color(red: 1.0, green: 0.78, blue: 0.34)
    static let error = Color(red: 1.0, green: 0.36, blue: 0.45)
    static let info = Color(red: 0.36, green: 0.78, blue: 1.0)
    static let muted = Color.white.opacity(0.46)
    static let sectionSpacing: CGFloat = 16
}

private extension ConnectionStatus {
    var tint: Color {
        switch self {
        case .disconnected, .disconnecting:
            return IrockDesign.muted
        case .preparing, .connecting, .reconnecting:
            return IrockDesign.warning
        case .connected:
            return IrockDesign.success
        case .failed:
            return IrockDesign.error
        }
    }

    var symbolName: String {
        switch self {
        case .disconnected:
            return "circle"
        case .preparing, .connecting, .reconnecting:
            return "bolt.horizontal.circle"
        case .connected:
            return "checkmark.circle.fill"
        case .disconnecting:
            return "pause.circle"
        case .failed:
            return "xmark.octagon.fill"
        }
    }
}

private extension LocalProxyPhase {
    var displayText: String {
        switch self {
        case .stopped: "未启动"
        case .running: "运行中"
        case .failed: "失败"
        }
    }

    var tint: Color {
        switch self {
        case .stopped: IrockDesign.muted
        case .running: IrockDesign.info
        case .failed: IrockDesign.error
        }
    }
}

private extension UserModeTunPhase {
    var displayText: String {
        switch self {
        case .stopped: "未启动"
        case .running: "运行中"
        case .failed: "失败"
        }
    }

    var tint: Color {
        switch self {
        case .stopped: IrockDesign.muted
        case .running: IrockDesign.success
        case .failed: IrockDesign.error
        }
    }
}

private extension RouteMode {
    var displayText: String {
        switch self {
        case .globalProxy: "全局代理"
        case .ruleBased: "规则模式"
        case .direct: "直连"
        }
    }

    var detailText: String {
        switch self {
        case .globalProxy: "全部流量进入代理"
        case .ruleBased: "按运行规则智能分流"
        case .direct: "绕过代理直接连接"
        }
    }
}

private extension ProxyNode {
    var endpointDisplayText: String {
        "\(serverHost):\(serverPort)"
    }
}

private extension ProxyProtocolType {
    var shortDisplayText: String {
        switch self {
        case .shadowsocks: "SS"
        case .vmess: "VM"
        case .vless: "VL"
        case .trojan: "TR"
        case .hysteria2: "HY2"
        case .tuic: "TUIC"
        }
    }
}

private extension TransportType {
    var displayText: String {
        switch self {
        case .tcp: "TCP"
        case .webSocket: "WS"
        case .http2: "H2"
        case .grpc: "gRPC"
        case .quic: "QUIC"
        }
    }
}

private extension TLSOptions {
    var displayText: String {
        if reality != nil { return "REALITY" }
        return enabled ? "TLS" : "PLAIN"
    }
}

private extension UDPPolicy {
    var displayText: String {
        switch self {
        case .disabled: "UDP Off"
        case .enabled: "UDP On"
        }
    }
}

private extension String {
    var logTint: Color {
        if contains("失败") || contains("错误") || contains("缺少") {
            return IrockDesign.error
        }
        if contains("已启动") || contains("已发布") || contains("已导入") || contains("就绪") {
            return IrockDesign.success
        }
        if contains("需要") || contains("请选择") {
            return IrockDesign.warning
        }
        return IrockDesign.info
    }
}
