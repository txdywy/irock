import XCTest
import IrockCore
@testable import IrockAppFeature

final class NodeDraftTests: XCTestCase {
    func testDraftBuildsProxyNodeWhenRequiredFieldsExist() throws {
        let draft = NodeDraft(
            name: "Demo Trojan",
            protocolType: .trojan,
            serverHost: "example.com",
            serverPortText: "443",
            credentialAccount: "node-1",
            transport: .tcp,
            tlsEnabled: true,
            tlsServerName: "example.com",
            udpEnabled: false
        )

        let node = try draft.buildNode(id: NodeID(rawValue: "node-1"), keychainService: "com.irock.nodes")

        XCTAssertEqual(node.name, "Demo Trojan")
        XCTAssertEqual(node.serverPort, 443)
        XCTAssertEqual(node.credentialReference.account, "node-1")
        XCTAssertTrue(node.tls.enabled)
        XCTAssertEqual(node.udpPolicy, .disabled)
    }

    func testDraftRejectsInvalidPort() {
        let draft = NodeDraft(name: "Bad", protocolType: .trojan, serverHost: "example.com", serverPortText: "99999", credentialAccount: "node-1", transport: .tcp, tlsEnabled: false, tlsServerName: "", udpEnabled: false)

        XCTAssertThrowsError(try draft.buildNode(id: NodeID(rawValue: "node-1"), keychainService: "com.irock.nodes")) { error in
            XCTAssertEqual(error as? NodeDraftError, .invalidPort)
        }
    }
}
