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
    func testAppViewModelExposesUnsignedMacGuidance() {
        let model = AppViewModel(nodes: [])

        XCTAssertTrue(model.systemProxyGuidance.enableSOCKSCommand.contains("networksetup"))
        XCTAssertTrue(model.systemProxyGuidance.enableHTTPCommand.contains("127.0.0.1 10809"))
        XCTAssertTrue(model.systemProxyGuidance.disableCommand.contains("-setsocksfirewallproxystate"))
        XCTAssertTrue(model.packetTunnelGuidance.message.contains("Apple Developer"))
        XCTAssertTrue(model.packetTunnelGuidance.userModeTunMessage.contains("root"))
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

        init(endpoint: LocalProxyEndpoint) {
            self.endpoint = endpoint
        }

        func start(node: ProxyNode, credential: String) throws -> LocalProxyEndpoint {
            startedNode = node
            startedCredential = credential
            return endpoint
        }

        func stop() throws {}
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
