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
