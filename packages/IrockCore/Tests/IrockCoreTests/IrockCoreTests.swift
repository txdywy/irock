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
}
