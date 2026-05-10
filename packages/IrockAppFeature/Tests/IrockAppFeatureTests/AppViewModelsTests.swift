import XCTest
import IrockCore
@testable import IrockAppFeature

final class AppViewModelsTests: XCTestCase {
    @MainActor
    func testAppViewModelSelectsNode() {
        let node = ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled)
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
}
