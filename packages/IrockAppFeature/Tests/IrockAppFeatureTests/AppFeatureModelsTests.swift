import XCTest
import IrockCore
@testable import IrockAppFeature

final class AppFeatureModelsTests: XCTestCase {
    func testOverviewStateStoresConnectionStatusAndRouteMode() {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo Node",
            protocolType: .trojan,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: .disabled
        )

        let state = OverviewState(connectionStatus: .connected, selectedNode: node, routeMode: .ruleBased, recentLogMessages: ["Connected"])

        XCTAssertEqual(state.connectionStatus, .connected)
        XCTAssertEqual(state.selectedNode?.name, "Demo Node")
        XCTAssertEqual(state.routeMode, .ruleBased)
        XCTAssertEqual(state.recentLogMessages, ["Connected"])
    }

    func testConnectionStatusDisplayText() {
        XCTAssertEqual(ConnectionStatus.disconnected.displayText, "未连接")
        XCTAssertEqual(ConnectionStatus.connecting.displayText, "连接中")
        XCTAssertEqual(ConnectionStatus.connected.displayText, "已连接")
        XCTAssertEqual(ConnectionStatus.failed.displayText, "连接失败")
    }
}
