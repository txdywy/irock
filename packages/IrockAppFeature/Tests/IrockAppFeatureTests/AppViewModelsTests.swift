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
        model.setRoutingRuleText("DOMAIN,example.com,DROP")

        let result = model.publishRuntimeSnapshot()

        guard case .storageFailed = result else {
            return XCTFail("Expected storageFailed result")
        }
        XCTAssertNil(try store.load())
        XCTAssertTrue(model.overviewState.recentLogMessages.contains { $0.contains("Routing rules invalid") })
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
