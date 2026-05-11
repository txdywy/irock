import Foundation
import XCTest
import IrockCore
@testable import IrockAppFeature

final class URIImportTests: XCTestCase {
    func testClassifiesSupportedSchemes() throws {
        XCTAssertEqual(try URIImport.classify("ss://abc").protocolType, .shadowsocks)
        XCTAssertEqual(try URIImport.classify("vmess://abc").protocolType, .vmess)
        XCTAssertEqual(try URIImport.classify("vless://abc").protocolType, .vless)
        XCTAssertEqual(try URIImport.classify("trojan://abc").protocolType, .trojan)
        XCTAssertEqual(try URIImport.classify("hysteria2://abc").protocolType, .hysteria2)
        XCTAssertEqual(try URIImport.classify("tuic://abc").protocolType, .tuic)
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try URIImport.classify("https://example.com")) { error in
            XCTAssertEqual(error as? URIImportError, .unsupportedScheme("https"))
        }
    }

    func testParsesFullyBase64EncodedShadowsocksURI() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzc0BleGFtcGxlLmNvbTo4Mzg4#Demo%20SS")

        XCTAssertEqual(draft.name, "Demo SS")
        XCTAssertEqual(draft.protocolType, .shadowsocks)
        XCTAssertEqual(draft.serverHost, "example.com")
        XCTAssertEqual(draft.serverPortText, "8388")
        XCTAssertEqual(draft.credentialAccount, "aes-256-gcm:pass")
        XCTAssertEqual(draft.transport, .tcp)
        XCTAssertFalse(draft.tlsEnabled)
        XCTAssertEqual(draft.tlsServerName, "")
        XCTAssertFalse(draft.udpEnabled)
    }

    func testParsesUserInfoBase64ShadowsocksURI() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo%20SS")

        XCTAssertEqual(draft.name, "Demo SS")
        XCTAssertEqual(draft.serverHost, "example.com")
        XCTAssertEqual(draft.serverPortText, "8388")
        XCTAssertEqual(draft.credentialAccount, "aes-256-gcm:pass")
    }

    func testUsesHostPortAsNameWhenFragmentIsMissing() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388")

        XCTAssertEqual(draft.name, "example.com:8388")
    }

    func testParsesURLSafeBase64WithoutPadding() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwQHNz@example.com:443#URLSafe")

        XCTAssertEqual(draft.name, "URLSafe")
        XCTAssertEqual(draft.credentialAccount, "chacha20-ietf-poly1305:p@ss")
        XCTAssertEqual(draft.serverHost, "example.com")
        XCTAssertEqual(draft.serverPortText, "443")
    }

    func testParseShadowsocksRejectsNonSSScheme() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("trojan://example.com")) { error in
            XCTAssertEqual(error as? URIImportError, .unsupportedScheme("trojan"))
        }
    }

    func testParseShadowsocksRejectsInvalidBase64() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("ss://not base64@example.com:8388")) { error in
            XCTAssertEqual(error as? URIImportError, .invalidBase64)
        }
    }

    func testParseShadowsocksRejectsMissingUserInfo() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("ss://example.com:8388")) { error in
            XCTAssertEqual(error as? URIImportError, .missingUserInfo)
        }
    }

    func testParseShadowsocksRejectsMissingHost() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@:8388")) { error in
            XCTAssertEqual(error as? URIImportError, .missingHost)
        }
    }

    func testParseShadowsocksRejectsMissingPort() {
        XCTAssertThrowsError(try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@example.com")) { error in
            XCTAssertEqual(error as? URIImportError, .missingPort)
        }
    }

    func testImportedDraftBuildsShadowsocksNode() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-1"), keychainService: "com.irock.nodes")

        XCTAssertEqual(node.protocolType, .shadowsocks)
        XCTAssertEqual(node.name, "Demo")
        XCTAssertEqual(node.serverHost, "example.com")
        XCTAssertEqual(node.serverPort, 8388)
        XCTAssertEqual(node.credentialReference.account, "node-1")

        let snapshot = RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: node, routeMode: .ruleBased, logLevel: .user)
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("aes-256-gcm:pass"))
    }
}
