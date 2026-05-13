import XCTest
import IrockCore
import IrockStorage
@testable import IrockAppFeature

final class AppViewModelsTests: XCTestCase {
    @MainActor
    func testAppViewModelSelectsNode() {
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node])

        model.selectNode(id: NodeID(rawValue: "node-1"))

        XCTAssertEqual(model.nodeListState.selectedNodeID?.rawValue, "node-1")
        XCTAssertEqual(model.overviewState.selectedNode?.name, "Demo")
    }

    @MainActor
    func testAppViewModelImportsAndSelectsShadowsocksURI() throws {
        let model = AppViewModel(nodes: [])

        let node = try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        XCTAssertEqual(node.name, "Demo")
        XCTAssertEqual(node.protocolType, .shadowsocks)
        XCTAssertEqual(node.serverHost, "example.com")
        XCTAssertEqual(model.nodeListState.nodes, [node])
        XCTAssertEqual(model.nodeListState.selectedNodeID, node.id)
        XCTAssertEqual(model.overviewState.selectedNode, node)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("节点已导入：Demo"))
    }

    @MainActor
    func testAppViewModelImportsGenericProtocolURI() throws {
        let model = AppViewModel(nodes: [])

        let node = try model.importURI("trojan://secret-password@trojan.example.com:443?type=grpc&serviceName=%2FService%2FTun#Trojan")

        XCTAssertEqual(node.name, "Trojan")
        XCTAssertEqual(node.protocolType, .trojan)
        XCTAssertEqual(node.transport, .grpc)
        XCTAssertEqual(node.transportOptions.grpc?.service, "/Service/Tun")
        XCTAssertEqual(model.nodeListState.nodes, [node])
        XCTAssertEqual(model.nodeListState.selectedNodeID, node.id)
    }

    @MainActor
    func testAppViewModelStartsLocalProxyForImportedNode() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let controller = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: controller)
        let node = try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        let result = try model.startLocalProxyMode()

        XCTAssertEqual(result, endpoint)
        XCTAssertEqual(controller.startedNode, node)
        XCTAssertEqual(controller.startedCredential, "aes-256-gcm:pass")
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.localProxyState.endpoint, endpoint)
        XCTAssertEqual(model.localProxyState.endpoint?.socksAddress, "127.0.0.1:10808")
        XCTAssertEqual(model.localProxyState.endpoint?.httpAddress, "127.0.0.1:10809")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("本地代理已启动：SOCKS 127.0.0.1:10808，HTTP 127.0.0.1:10809"))
    }

    @MainActor
    func testAppViewModelConnectPublishesSnapshotAndStartsLocalProxyFallback() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let controller = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], runtimeSnapshotStore: store, localProxyController: controller)
        let node = try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(try store.load()?.selectedNode.id, node.id)
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("连接已就绪：SOCKS 127.0.0.1:10808，HTTP 127.0.0.1:10809"))
    }

    @MainActor
    func testAppViewModelConnectStartsUserModeTunForImportedHysteria2Node() throws {
        let localProxy = RecordingLocalProxyController(endpoint: LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809))
        let tunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let tun = RecordingUserModeTunController(endpoint: tunEndpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy, userModeTunController: tun)
        let node = try model.importURI("hysteria2://hysteria-password@hy2.example.com:19991/?insecure=1&pinSHA256=pin-value&sni=hy2.example.com#HY2")

        let result = model.connect()

        XCTAssertEqual(result, .userModeTunStarted(tunEndpoint))
        XCTAssertNil(localProxy.startedNode)
        XCTAssertEqual(tun.startedNode, node)
        XCTAssertEqual(tun.startedCredential, "hysteria-password")
        XCTAssertEqual(model.userModeTunState.phase, .running)
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("连接已就绪：utun9 10.255.0.2/1500"))
    }

    @MainActor
    func testAppViewModelStopConnectionStopsLocalProxyAndUpdatesConnectionStatus() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let controller = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        _ = model.connect()

        model.stopConnection()

        XCTAssertEqual(model.overviewState.connectionStatus, .disconnected)
        XCTAssertEqual(model.localProxyState.phase, .stopped)
        XCTAssertEqual(model.localProxyState.endpoint, nil)
        XCTAssertTrue(controller.didStop)
    }

    @MainActor
    func testAppViewModelStopConnectionPreservesFailureWhenLocalProxyStopFails() throws {
        let localProxyController = StopThrowingLocalProxyController(endpoint: LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809))
        let tunController = RecordingUserModeTunController(endpoint: UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500))
        let model = AppViewModel(nodes: [], localProxyController: localProxyController, userModeTunController: tunController)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        _ = model.connect()
        _ = try model.startUserModeTunMode()

        model.stopConnection()

        XCTAssertEqual(model.localProxyState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
        XCTAssertEqual(model.overviewState.connectionStatus, .failed)
        XCTAssertTrue(tunController.didStop)
    }

    @MainActor
    func testAppViewModelConnectExposesLocalProxyStartupFailure() throws {
        let controller = ThrowingLocalProxyController()
        let model = AppViewModel(nodes: [], localProxyController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyFailed("本地代理启动失败"))
        XCTAssertEqual(model.localProxyState.phase, .failed)
        XCTAssertEqual(model.localProxyState.message, "本地代理启动失败")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("本地代理启动失败"))
    }

    @MainActor
    func testAppViewModelConnectAllowsApprovedShadowsocks2022Methods() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let controller = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: controller)
        try model.importShadowsocksURI("ss://MjAyMi1ibGFrZTMtYWVzLTEyOC1nY206QUFFQ0F3UUZCZ2NJQ1FvTERBME9Edz09QGV4YW1wbGUuaW52YWxpZDo0MjgxNw==#Shadowsocks-2022-example")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(controller.startedNode?.name, "Shadowsocks-2022-example")
        XCTAssertEqual(controller.startedCredential, "2022-blake3-aes-128-gcm:AAECAwQFBgcICQoLDA0ODw==")
        XCTAssertEqual(model.localProxyState.phase, .running)
    }

    @MainActor
    func testAppViewModelConnectRejectsUnknownShadowsocks2022MethodBeforeStartingProxy() throws {
        let controller = RecordingLocalProxyController(endpoint: LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809))
        let model = AppViewModel(nodes: [], localProxyController: controller)
        try model.importShadowsocksURI("ss://MjAyMi1ibGFrZTMtYWVzLTE5Mi1nY206QUFFQ0F3UUZCZ2NJQ1FvTERBME9Edz09QGV4YW1wbGUuaW52YWxpZDo0MjgxNw==#Unknown-2022-example")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyFailed("当前 Shadowsocks 加密方法暂不支持本地代理"))
        XCTAssertNil(controller.startedNode)
        XCTAssertEqual(model.localProxyState.phase, .failed)
    }

    @MainActor
    func testAppViewModelExposesUnsignedMacGuidance() {
        let model = AppViewModel(nodes: [])

        XCTAssertTrue(model.systemProxyGuidance.enableSOCKSCommand.contains("networksetup"))
        XCTAssertTrue(model.systemProxyGuidance.enableHTTPCommand.contains("127.0.0.1 10809"))
        XCTAssertTrue(model.systemProxyGuidance.disableCommand.contains("-setsocksfirewallproxystate"))
        XCTAssertTrue(model.packetTunnelGuidance.message.contains("Apple Developer"))
        XCTAssertTrue(model.packetTunnelGuidance.userModeTunMessage.contains("root"))
    }

    @MainActor
    func testAppViewModelStartsUserModeTunForImportedNode() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let endpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let controller = RecordingUserModeTunController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], runtimeSnapshotStore: store, userModeTunController: controller)
        let node = try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        let result = try model.startUserModeTunMode()

        XCTAssertEqual(result, endpoint)
        XCTAssertEqual(controller.startedNode, node)
        XCTAssertEqual(controller.startedCredential, "aes-256-gcm:pass")
        XCTAssertEqual(try store.load()?.selectedNode.id, node.id)
        XCTAssertEqual(model.userModeTunState.phase, .running)
        XCTAssertEqual(model.userModeTunState.endpoint, endpoint)
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 已启动：utun9 10.255.0.2/1500"))
    }

    @MainActor
    func testAppViewModelExposesUserModeTunAuthorizationFailure() throws {
        let controller = ThrowingUserModeTunController(error: UserModeTunError.authorizationRequired)
        let model = AppViewModel(nodes: [], userModeTunController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        XCTAssertThrowsError(try model.startUserModeTunMode())

        XCTAssertEqual(model.userModeTunState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 需要管理员权限")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 需要管理员权限"))
    }

    @MainActor
    func testAppViewModelRejectsUserModeTunWithoutSelectedNode() {
        let controller = RecordingUserModeTunController(endpoint: UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500))
        let model = AppViewModel(nodes: [], userModeTunController: controller)

        XCTAssertThrowsError(try model.startUserModeTunMode())

        XCTAssertNil(controller.startedNode)
        XCTAssertEqual(model.userModeTunState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.message, "请选择节点后再启动用户态 TUN")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("请选择节点后再启动用户态 TUN"))
    }

    @MainActor
    func testAppViewModelRejectsUserModeTunWithoutImportedCredential() {
        let node = makeNode(id: "node-1", name: "Manual")
        let controller = RecordingUserModeTunController(endpoint: UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500))
        let model = AppViewModel(nodes: [node], userModeTunController: controller)
        model.selectNode(id: node.id)

        XCTAssertThrowsError(try model.startUserModeTunMode())

        XCTAssertNil(controller.startedNode)
        XCTAssertEqual(model.userModeTunState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 缺少节点凭据")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 缺少节点凭据"))
    }

    @MainActor
    func testAppViewModelMapsGenericUserModeTunFailure() throws {
        let controller = ThrowingUserModeTunController(error: UserModeTunError.unavailable)
        let model = AppViewModel(nodes: [], userModeTunController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        XCTAssertThrowsError(try model.startUserModeTunMode()) { error in
            XCTAssertEqual(error as? UserModeTunError, .unavailable)
        }

        XCTAssertEqual(model.userModeTunState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 启动失败")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 启动失败"))
    }

    @MainActor
    func testAppViewModelStopsUserModeTun() throws {
        let endpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let controller = RecordingUserModeTunController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], userModeTunController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        _ = try model.startUserModeTunMode()

        model.stopUserModeTunMode()

        XCTAssertTrue(controller.didStop)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
        XCTAssertNil(model.userModeTunState.endpoint)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 已停止")
        XCTAssertEqual(model.overviewState.connectionStatus, .disconnected)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 已停止"))
    }

    @MainActor
    func testAppViewModelPreservesUserModeTunEndpointWhenStopFails() throws {
        let endpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let controller = StopThrowingUserModeTunController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], userModeTunController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        _ = try model.startUserModeTunMode()

        model.stopUserModeTunMode()

        XCTAssertEqual(model.userModeTunState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.endpoint, endpoint)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 停止失败")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 停止失败"))
    }

    @MainActor
    func testAppViewModelAppendsBoundedLogs() {
        let model = AppViewModel(nodes: [], logLimit: 2)

        model.appendLog("first")
        model.appendLog("second")
        model.appendLog("third")

        XCTAssertEqual(model.overviewState.recentLogMessages, ["second", "third"])
    }

    @MainActor
    func testAppViewModelUpdatesRouteModeBeforePublishing() throws {
        let node = makeNode(id: "node-1", name: "Demo")
        let store = InMemoryRuntimeSnapshotStore()
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)

        model.selectNode(id: node.id)
        model.setRouteMode(.direct)
        let result = model.publishRuntimeSnapshot()

        guard case .published = result else {
            return XCTFail("Expected published result")
        }
        XCTAssertEqual(model.overviewState.routeMode, .direct)
        XCTAssertEqual(try store.load()?.routeMode, .direct)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("运行配置已发布"))
    }

    @MainActor
    func testAppViewModelPublishesDebugSnapshotWhenDebugLoggingEnabled() throws {
        let node = makeNode(id: "node-1", name: "Demo")
        let store = InMemoryRuntimeSnapshotStore()
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)

        model.selectNode(id: node.id)
        model.setDebugLoggingEnabled(true)
        _ = model.publishRuntimeSnapshot()

        XCTAssertTrue(model.settingsState.debugLoggingEnabled)
        XCTAssertEqual(try store.load()?.logLevel, .debug)
    }

    @MainActor
    func testAppViewModelLogsMissingNodeWhenPublishingWithoutSelection() {
        let model = AppViewModel(nodes: [])

        let result = model.publishRuntimeSnapshot()

        XCTAssertEqual(result, .missingSelectedNode)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("请选择节点后再启动"))
    }

    @MainActor
    func testAppViewModelPublishesRoutingRuleManifestFromLocalText() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)
        model.selectNode(id: node.id)
        model.setRoutingRuleText("DOMAIN-SUFFIX,apple.com,DIRECT\nFINAL,PROXY")

        _ = model.publishRuntimeSnapshot()

        XCTAssertEqual(try store.load()?.routingRuleManifest, RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        ))
    }

    @MainActor
    func testAppViewModelPublishesEmptyManifestForCommentOnlyRules() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)
        model.selectNode(id: node.id)
        model.setRoutingRuleText("# no local rules")

        _ = model.publishRuntimeSnapshot()

        XCTAssertEqual(try store.load()?.routingRuleManifest, .empty)
    }

    @MainActor
    func testAppViewModelDoesNotPublishWhenRoutingRulesAreInvalid() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)
        model.selectNode(id: node.id)
        model.setRoutingRuleText("DOMAIN,example.com,SECRET_TOKEN")

        let result = model.publishRuntimeSnapshot()

        guard case let .storageFailed(message) = result else {
            return XCTFail("Expected storageFailed result")
        }
        XCTAssertEqual(message, "Routing rules invalid at line 1: unsupported action")
        XCTAssertFalse(message.contains("SECRET_TOKEN"))
        XCTAssertNil(try store.load())
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("Routing rules invalid at line 1: unsupported action"))
    }

    @MainActor
    func testAppViewModelRefreshesRuntimeFeedback() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let status = RuntimeConnectionStatus(
            phase: .connected,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_030),
            message: "Connected"
        )
        let log = RuntimeLogEntry(
            id: "log-1",
            timestamp: Date(timeIntervalSince1970: 1_715_000_031),
            level: .user,
            message: "Tunnel runtime connected",
            nodeID: NodeID(rawValue: "node-1"),
            phase: .connected
        )
        try statusStore.save(status)
        try logStore.append(log)
        let model = AppViewModel(nodes: [], runtimeStatusStore: statusStore, runtimeLogStore: logStore)

        let result = model.refreshRuntimeFeedback()

        XCTAssertEqual(result, .refreshed)
        XCTAssertEqual(model.runtimeConnectionStatus, status)
        XCTAssertEqual(model.runtimeLogs, [log])
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
        XCTAssertEqual(model.overviewState.recentLogMessages, ["Tunnel runtime connected"])
    }

    @MainActor
    func testAppViewModelRefreshUsesDisconnectedWhenStatusIsMissing() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let model = AppViewModel(nodes: [], runtimeStatusStore: statusStore, runtimeLogStore: logStore)

        let result = model.refreshRuntimeFeedback()

        XCTAssertEqual(result, .refreshed)
        XCTAssertEqual(model.runtimeConnectionStatus?.phase, .disconnected)
        XCTAssertEqual(model.overviewState.connectionStatus, .disconnected)
    }

    @MainActor
    func testAppViewModelRefreshAppliesStatusWhenLogLoadFails() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let status = RuntimeConnectionStatus(
            phase: .connected,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_032),
            message: "Connected"
        )
        try statusStore.save(status)
        let model = AppViewModel(nodes: [], runtimeStatusStore: statusStore, runtimeLogStore: ThrowingRuntimeLogStore())

        let result = model.refreshRuntimeFeedback()

        guard case .logLoadFailed(let message) = result else {
            return XCTFail("Expected logLoadFailed result")
        }
        XCTAssertEqual(message, "Runtime logs unavailable")
        XCTAssertEqual(model.runtimeConnectionStatus, status)
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
    }

    @MainActor
    func testAppViewModelRefreshReturnsStableStatusFailureMessage() {
        let model = AppViewModel(nodes: [], runtimeStatusStore: ThrowingRuntimeStatusStore())

        let result = model.refreshRuntimeFeedback()

        guard case .statusLoadFailed(let message) = result else {
            return XCTFail("Expected statusLoadFailed result")
        }
        XCTAssertEqual(message, "Runtime status unavailable")
    }

    private final class RecordingLocalProxyController: LocalProxyControlling {
        let endpoint: LocalProxyEndpoint
        private(set) var startedNode: ProxyNode?
        private(set) var startedCredential: String?
        private(set) var didStop = false

        init(endpoint: LocalProxyEndpoint) {
            self.endpoint = endpoint
        }

        func start(node: ProxyNode, credential: String) throws -> LocalProxyEndpoint {
            startedNode = node
            startedCredential = credential
            return endpoint
        }

        func stop() throws {
            didStop = true
        }
    }

    private final class RecordingUserModeTunController: UserModeTunControlling {
        let endpoint: UserModeTunEndpoint
        private(set) var startedNode: ProxyNode?
        private(set) var startedCredential: String?
        private(set) var didStop = false

        init(endpoint: UserModeTunEndpoint) {
            self.endpoint = endpoint
        }

        func start(node: ProxyNode, credential: String) throws -> UserModeTunEndpoint {
            startedNode = node
            startedCredential = credential
            return endpoint
        }

        func stop() throws {
            didStop = true
        }
    }

    private final class ThrowingLocalProxyController: LocalProxyControlling {
        func start(node: ProxyNode, credential: String) throws -> LocalProxyEndpoint {
            throw LocalProxyError.unavailable
        }

        func stop() throws {}
    }

    private final class StopThrowingLocalProxyController: LocalProxyControlling {
        let endpoint: LocalProxyEndpoint

        init(endpoint: LocalProxyEndpoint) {
            self.endpoint = endpoint
        }

        func start(node: ProxyNode, credential: String) throws -> LocalProxyEndpoint {
            endpoint
        }

        func stop() throws {
            throw LocalProxyError.unavailable
        }
    }

    private final class ThrowingUserModeTunController: UserModeTunControlling {
        let error: UserModeTunError

        init(error: UserModeTunError) {
            self.error = error
        }

        func start(node: ProxyNode, credential: String) throws -> UserModeTunEndpoint {
            throw error
        }

        func stop() throws {}
    }

    private final class StopThrowingUserModeTunController: UserModeTunControlling {
        let endpoint: UserModeTunEndpoint

        init(endpoint: UserModeTunEndpoint) {
            self.endpoint = endpoint
        }

        func start(node: ProxyNode, credential: String) throws -> UserModeTunEndpoint {
            endpoint
        }

        func stop() throws {
            throw UserModeTunError.unavailable
        }
    }

    private struct ThrowingRuntimeLogStore: RuntimeLogStore {
        func append(_ entry: RuntimeLogEntry) throws {}

        func loadRecent() throws -> [RuntimeLogEntry] {
            throw TestError.loadFailed
        }

        func clear() throws {}
    }

    private struct ThrowingRuntimeStatusStore: RuntimeStatusStore {
        func save(_ status: RuntimeConnectionStatus) throws {}

        func load() throws -> RuntimeConnectionStatus? {
            throw TestError.loadFailed
        }
    }

    private enum TestError: Error {
        case loadFailed
    }

    private func makeNode(id: String, name: String) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: id),
            name: name,
            protocolType: .trojan,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: id),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
    }
}
