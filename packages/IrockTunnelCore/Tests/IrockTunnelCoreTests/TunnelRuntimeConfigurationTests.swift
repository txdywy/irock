import XCTest
import IrockCore
import IrockRouting
@testable import IrockTunnelCore

final class TunnelRuntimeConfigurationTests: XCTestCase {
    func testConfigurationConsumesRuntimeSnapshotRouteModeAndLimits() {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .globalProxy,
            logLevel: .user
        )

        let configuration = TunnelRuntimeConfiguration(snapshot: snapshot, routingEngine: RoutingEngine(rules: [.final(.reject)]), batchLimit: 32, flowLimit: 128)

        XCTAssertEqual(configuration.routeMode, .globalProxy)
        XCTAssertEqual(configuration.batchLimit, 32)
        XCTAssertEqual(configuration.flowLimit, 128)
    }

    func testConfigurationExposesRoutingRuleManifest() {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct)]
        )
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )
        let configuration = TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: RoutingEngine(rules: [.final(.reject)]),
            batchLimit: 32,
            flowLimit: 128
        )

        XCTAssertEqual(configuration.routingRuleManifest, manifest)
    }

    func testConfigurationBuildsRoutingEngineFromSnapshotManifest() throws {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        )
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )
        let configuration = try TunnelRuntimeConfiguration(snapshot: snapshot, batchLimit: 32, flowLimit: 128)

        let decision = configuration.routingEngine.resolve(RoutingContext(host: "developer.apple.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }

    func testConfigurationBuiltFromEmptyManifestUsesRejectDefault() throws {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user
        )
        let configuration = try TunnelRuntimeConfiguration(snapshot: snapshot, batchLimit: 32, flowLimit: 128)

        let decision = configuration.routingEngine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .reject)
        XCTAssertNil(decision.matchedRule)
    }

    private func makeNode() -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo",
            protocolType: .trojan,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
    }
}
