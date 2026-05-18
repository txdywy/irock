import Foundation
import XCTest
@testable import IrockCore

final class IrockCoreTests: XCTestCase {
    func testProxyNodeStoresProtocolTransportEndpointAndCredentialReference() {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo VLESS",
            protocolType: .vless,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .grpc,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: nil),
            udpPolicy: .enabled
        )

        XCTAssertEqual(node.id.rawValue, "node-1")
        XCTAssertEqual(node.name, "Demo VLESS")
        XCTAssertEqual(node.protocolType, .vless)
        XCTAssertEqual(node.serverHost, "example.com")
        XCTAssertEqual(node.serverPort, 443)
        XCTAssertEqual(node.credentialReference.account, "node-1")
        XCTAssertEqual(node.transport, .grpc)
        XCTAssertEqual(node.tls.alpn, ["h2"])
        XCTAssertEqual(node.udpPolicy, .enabled)
    }

    func testRuntimeSnapshotFreezesSelectedNodeAndRouteMode() {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo SS",
            protocolType: .shadowsocks,
            serverHost: "127.0.0.1",
            serverPort: 8388,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )

        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: node,
            routeMode: .ruleBased,
            logLevel: .user
        )

        XCTAssertEqual(snapshot.selectedNode.id.rawValue, "node-1")
        XCTAssertEqual(snapshot.routeMode, .ruleBased)
        XCTAssertEqual(snapshot.logLevel, .user)
    }

    func testRuntimeSnapshotEncodingDoesNotContainRawCredentialMaterial() throws {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo SS",
            protocolType: .shadowsocks,
            serverHost: "127.0.0.1",
            serverPort: 8388,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
        let snapshot = RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: node, routeMode: .ruleBased, logLevel: .user)

        let data = try JSONEncoder().encode(snapshot)
        let encoded = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(encoded.contains("credentialReference"))
        XCTAssertFalse(encoded.contains("secret"))
        XCTAssertFalse(encoded.contains("password"))
        XCTAssertFalse(encoded.contains("token"))
    }

    func testProxyProtocolTypeCoversShadowrocketOutboundFamilies() {
        let protocolTypes: [ProxyProtocolType] = [
            .shadowsocks,
            .shadowsocksR,
            .vmess,
            .vless,
            .trojan,
            .hysteria2,
            .tuic,
            .socks,
            .httpProxy,
            .snell,
            .wireGuard,
            .ssh,
            .trustTunnel
        ]

        XCTAssertEqual(protocolTypes.map(\.rawValue), [
            "shadowsocks",
            "shadowsocksR",
            "vmess",
            "vless",
            "trojan",
            "hysteria2",
            "tuic",
            "socks",
            "httpProxy",
            "snell",
            "wireGuard",
            "ssh",
            "trustTunnel"
        ])
    }

    func testProxyNodeCodableRoundTripsNewShadowrocketProtocolCase() throws {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-socks"),
            name: "SOCKS Demo",
            protocolType: .socks,
            serverHost: "proxy.example.com",
            serverPort: 1080,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-socks"),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )

        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ProxyNode.self, from: data)

        XCTAssertEqual(decoded, node)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("socks"))
    }

    func testRuntimeSnapshotDefaultsToEmptyRoutingRuleManifest() {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user
        )

        XCTAssertEqual(snapshot.routingRuleManifest, .empty)
    }

    func testRuntimeSnapshotCodableRoundTripsRoutingRuleManifest() throws {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct),
                RuntimeRoutingRule(kind: .domainKeyword, value: "google", action: .proxy)
            ]
        )
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RuntimeSnapshot.self, from: data)

        XCTAssertEqual(decoded.routingRuleManifest, manifest)
    }

    func testRuntimeConnectionStatusCodableRoundTrips() throws {
        let status = RuntimeConnectionStatus(
            phase: .connected,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo Node",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_000),
            message: "Connected"
        )

        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(RuntimeConnectionStatus.self, from: data)

        XCTAssertEqual(decoded, status)
    }

    func testRuntimeConnectionStatusDisconnectedDefault() {
        let status = RuntimeConnectionStatus.disconnected(updatedAt: Date(timeIntervalSince1970: 1_715_000_001))

        XCTAssertEqual(status.phase, .disconnected)
        XCTAssertNil(status.selectedNodeID)
        XCTAssertNil(status.selectedNodeName)
        XCTAssertEqual(status.updatedAt, Date(timeIntervalSince1970: 1_715_000_001))
        XCTAssertNil(status.message)
    }

    func testRuntimeLogEntryCodableRoundTrips() throws {
        let entry = RuntimeLogEntry(
            id: "log-1",
            timestamp: Date(timeIntervalSince1970: 1_715_000_002),
            level: .user,
            message: "Tunnel connected",
            nodeID: NodeID(rawValue: "node-1"),
            phase: .connected
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(RuntimeLogEntry.self, from: data)

        XCTAssertEqual(decoded, entry)
    }

    private func makeNode() -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo",
            protocolType: .shadowsocks,
            serverHost: "example.com",
            serverPort: 8388,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
    }
}
