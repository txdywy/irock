import XCTest
import IrockCore
import IrockRouting
@testable import IrockTunnelCore

final class TunnelRuntimeConfigurationTests: XCTestCase {
    func testConfigurationConsumesRuntimeSnapshotRouteModeAndLimits() {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: ProxyNode(id: NodeID(rawValue: "node-1"), name: "Demo", protocolType: .trojan, serverHost: "example.com", serverPort: 443, credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"), transport: .tcp, tls: .disabled, udpPolicy: .disabled),
            routeMode: .globalProxy,
            logLevel: .user
        )

        let configuration = TunnelRuntimeConfiguration(snapshot: snapshot, routingEngine: RoutingEngine(rules: [.final(.reject)]), batchLimit: 32, flowLimit: 128)

        XCTAssertEqual(configuration.routeMode, .globalProxy)
        XCTAssertEqual(configuration.batchLimit, 32)
        XCTAssertEqual(configuration.flowLimit, 128)
    }
}
