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
        XCTAssertEqual(try URIImport.classify("hy2://abc").protocolType, .hysteria2)
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

    func testParsesShadowsocks2022URIWithoutExposingSecret() throws {
        let draft = try URIImport.parseShadowsocksDraft("ss://MjAyMi1ibGFrZTMtYWVzLTEyOC1nY206dGVzdC1rZXlAZXhhbXBsZS5pbnZhbGlkOjQyODE3#Shadowsocks-2022-example")

        XCTAssertEqual(draft.name, "Shadowsocks-2022-example")
        XCTAssertEqual(draft.serverHost, "example.invalid")
        XCTAssertEqual(draft.serverPortText, "42817")
        XCTAssertTrue(draft.credentialAccount.hasPrefix("2022-blake3-aes-128-gcm:"))
        XCTAssertFalse(draft.credentialAccount.contains("example.invalid"))
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

    func testParsesVMessWebSocketShareLink() throws {
        let json = """
        {"v":"2","ps":"VMess WS","add":"vmess.example.com","port":"443","id":"00000000-0000-0000-0000-000000000001","net":"ws","type":"none","host":"edge.example.com","path":"/ray","tls":"tls","sni":"vmess.example.com"}
        """
        let encoded = Data(json.utf8).base64EncodedString()

        let draft = try URIImport.parseDraft("vmess://\(encoded)")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-vmess"), keychainService: "com.irock.nodes")

        XCTAssertEqual(draft.name, "VMess WS")
        XCTAssertEqual(node.protocolType, .vmess)
        XCTAssertEqual(node.serverHost, "vmess.example.com")
        XCTAssertEqual(node.serverPort, 443)
        XCTAssertEqual(node.transport, .webSocket)
        XCTAssertEqual(node.transportOptions.webSocket?.host, "edge.example.com")
        XCTAssertEqual(node.transportOptions.webSocket?.path, "/ray")
        XCTAssertEqual(node.tls.serverName, "vmess.example.com")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-vmess"), selectedNode: node, routeMode: .ruleBased, logLevel: .user)), as: UTF8.self).contains("00000000-0000-0000-0000-000000000001"))
    }

    func testParsesVMessFingerprintShareLink() throws {
        let json = """
        {"v":"2","ps":"VMess Pin","add":"vmess.example.com","port":"443","id":"00000000-0000-0000-0000-000000000001","net":"tcp","type":"none","tls":"tls","sni":"vmess.example.com","fp":"chrome"}
        """
        let encoded = Data(json.utf8).base64EncodedString()

        let draft = try URIImport.parseDraft("vmess://\(encoded)")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-vmess-pin"), keychainService: "com.irock.nodes")

        XCTAssertEqual(node.protocolType, .vmess)
        XCTAssertEqual(node.transport, .tcp)
        XCTAssertEqual(node.tls.fingerprint, "chrome")
    }

    func testParsesVMessNoneTLSAsDisabled() throws {
        let json = """
        {"v":"2","ps":"VMess None TLS","add":"vmess.example.com","port":"443","id":"00000000-0000-0000-0000-000000000001","net":"tcp","type":"none","tls":"none","sni":"vmess.example.com"}
        """
        let encoded = Data(json.utf8).base64EncodedString()

        let draft = try URIImport.parseDraft("vmess://\(encoded)")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-vmess-none-tls"), keychainService: "com.irock.nodes")

        XCTAssertFalse(node.tls.enabled)
    }

    func testRejectsVMessUnsupportedTCPHeaderType() {
        let json = """
        {"v":"2","ps":"VMess HTTP","add":"vmess.example.com","port":"443","id":"00000000-0000-0000-0000-000000000001","net":"tcp","type":"http","tls":"tls","sni":"vmess.example.com"}
        """
        let encoded = Data(json.utf8).base64EncodedString()

        XCTAssertThrowsError(try URIImport.parseDraft("vmess://\(encoded)")) { error in
            XCTAssertEqual(error as? URIImportError, .unsupportedOption("vmess tcp type"))
        }
    }

    func testParsesVLESSRealityShareLink() throws {
        let draft = try URIImport.parseDraft("vless://00000000-0000-0000-0000-000000000002@vless.example.com:443?security=reality&type=tcp&sni=www.example.com&fp=chrome&pbk=reality-public-key&sid=abc123&spx=%2F#VLESS%20Reality")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-vless"), keychainService: "com.irock.nodes")

        XCTAssertEqual(draft.name, "VLESS Reality")
        XCTAssertEqual(node.protocolType, .vless)
        XCTAssertEqual(node.transport, .tcp)
        XCTAssertTrue(node.tls.enabled)
        XCTAssertEqual(node.tls.serverName, "www.example.com")
        XCTAssertEqual(node.tls.fingerprint, "chrome")
        XCTAssertEqual(node.tls.reality?.publicKey, "reality-public-key")
        XCTAssertEqual(node.tls.reality?.shortID, "abc123")
        XCTAssertEqual(node.tls.reality?.spiderX, "/")
    }

    func testRejectsUnsupportedVLESSFlow() {
        XCTAssertThrowsError(try URIImport.parseDraft("vless://00000000-0000-0000-0000-000000000002@example.com:443?flow=xtls-rprx-vision")) { error in
            XCTAssertEqual(error as? URIImportError, .unsupportedOption("vless flow"))
        }
    }

    func testParsesTrojanGRPCShareLink() throws {
        let draft = try URIImport.parseDraft("trojan://secret-password@trojan.example.com:443?type=grpc&serviceName=%2FService%2FTun&sni=trojan.example.com&alpn=h2#Trojan%20gRPC")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-trojan"), keychainService: "com.irock.nodes")

        XCTAssertEqual(draft.name, "Trojan gRPC")
        XCTAssertEqual(node.protocolType, .trojan)
        XCTAssertEqual(node.transport, .grpc)
        XCTAssertEqual(node.transportOptions.grpc?.service, "/Service/Tun")
        XCTAssertEqual(node.tls.alpn, ["h2"])
    }

    func testParsesHysteria2RealmShareLinkWithoutLeakingRealmToken() throws {
        let realm = "realm://public-token@realm.hy2.io/demo-realm?stun=stun1.example.com:3478&stun=stun2.example.com:3478&lport=43210"
        let draft = try URIImport.parseDraft("hy2://hysteria-password@hy2.example.com:443?sni=cert.example.com&insecure=1&pinSHA256=pin-value&realm=\(realm.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)#HY2%20Realm")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-hy2"), keychainService: "com.irock.nodes")

        XCTAssertEqual(draft.name, "HY2 Realm")
        XCTAssertEqual(node.protocolType, .hysteria2)
        XCTAssertEqual(node.transport, .quic)
        XCTAssertEqual(node.tls.serverName, "cert.example.com")
        XCTAssertTrue(node.tls.allowInsecure)
        XCTAssertEqual(node.tls.fingerprint, "pin-value")
        XCTAssertEqual(node.hysteria2?.realm?.tokenReference.account, "node-hy2.hysteria2.realm-token")
        XCTAssertEqual(node.hysteria2?.realm?.rendezvousHost, "realm.hy2.io")
        XCTAssertEqual(node.hysteria2?.realm?.name, "demo-realm")
        XCTAssertEqual(node.hysteria2?.realm?.stunServers, ["stun1.example.com:3478", "stun2.example.com:3478"])
        XCTAssertEqual(node.hysteria2?.realm?.localPort, 43210)

        let encoded = String(decoding: try JSONEncoder().encode(RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-hy2"), selectedNode: node, routeMode: .ruleBased, logLevel: .user)), as: UTF8.self)
        XCTAssertFalse(encoded.contains("hysteria-password"))
        XCTAssertFalse(encoded.contains("public-token"))
    }

    func testPreservesNestedPercentEncodingInHysteria2RealmToken() throws {
        let realm = "realm://token%2Fwith%2Bencoded%3Dchars@realm.hy2.io/demo-realm"
        let draft = try URIImport.parseDraft("hy2://hysteria-password@hy2.example.com:443?realm=\(realm.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)#HY2%20Realm")

        XCTAssertEqual(draft.hysteria2Realm?.token, "token/with+encoded=chars")
    }

    func testParsesHysteria2RealmForwardingMarkerAsDirectHysteria2Node() throws {
        let draft = try URIImport.parseDraft("hysteria2://mypassword123@45.32.83.183:19991/?sni=los.hackx86.com&insecure=1&realm=1#Realm-HY2")

        XCTAssertEqual(draft.name, "Realm-HY2")
        XCTAssertEqual(draft.protocolType, .hysteria2)
        XCTAssertEqual(draft.serverHost, "45.32.83.183")
        XCTAssertEqual(draft.serverPortText, "19991")
        XCTAssertEqual(draft.credentialAccount, "mypassword123")
        XCTAssertEqual(draft.transport, .quic)
        XCTAssertEqual(draft.tlsServerName, "los.hackx86.com")
        XCTAssertTrue(draft.tlsAllowInsecure)
        XCTAssertNil(draft.hysteria2Realm)
    }

    func testParsesRealmSchemeForwardingURIAsDirectHysteria2Node() throws {
        let draft = try URIImport.parseDraft("realm://mypassword123@45.32.83.183:19991?sni=los.hackx86.com&insecure=1#Realm-HY2")

        XCTAssertEqual(draft.name, "Realm-HY2")
        XCTAssertEqual(draft.protocolType, .hysteria2)
        XCTAssertEqual(draft.serverHost, "45.32.83.183")
        XCTAssertEqual(draft.serverPortText, "19991")
        XCTAssertEqual(draft.credentialAccount, "mypassword123")
        XCTAssertEqual(draft.transport, .quic)
        XCTAssertEqual(draft.tlsServerName, "los.hackx86.com")
        XCTAssertTrue(draft.tlsAllowInsecure)
        XCTAssertNil(draft.hysteria2Realm)
    }

    func testParsesHysteria2PinnedCertificateShareLinkShape() throws {
        let draft = try URIImport.parseDraft("hysteria2://example-password@realm-host.example:19991/?insecure=1&pinSHA256=example-pin%2Bvalue%2Ffor%2Btests%3D&sni=realm-host.example#Realm_Hysteria2_19991")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-hy2-pin"), keychainService: "com.irock.nodes")

        XCTAssertEqual(draft.name, "Realm_Hysteria2_19991")
        XCTAssertEqual(node.protocolType, .hysteria2)
        XCTAssertEqual(node.serverHost, "realm-host.example")
        XCTAssertEqual(node.serverPort, 19991)
        XCTAssertEqual(node.transport, .quic)
        XCTAssertEqual(node.tls.serverName, "realm-host.example")
        XCTAssertTrue(node.tls.allowInsecure)
        XCTAssertEqual(node.tls.fingerprint, "example-pin+value/for+tests=")

        let snapshot = RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-hy2-pin"), selectedNode: node, routeMode: .ruleBased, logLevel: .user)
        let snapshotData = try JSONEncoder().encode(snapshot)
        let encoded = String(decoding: snapshotData, as: UTF8.self)
        let decoded = try JSONDecoder().decode(RuntimeSnapshot.self, from: snapshotData)
        XCTAssertEqual(decoded.selectedNode.tls.fingerprint, "example-pin+value/for+tests=")
        XCTAssertFalse(encoded.contains("example-password"))
    }

    func testExtractsWrappedHysteria2ShareLinkFromPastedText() throws {
        let pasted = """
           1 hysteria2://example-password@realm-host.example:19991/?insecure=1&pinSHA256
             =example-pin%2Bvalue%2Ffor%2Btests%3D&sni=realm-host.example#Realm_Hysteria2_19991

          链接包含的信息：
          * 协议: hysteria2://
          """

        let draft = try URIImport.parseDraft(pasted)

        XCTAssertEqual(draft.name, "Realm_Hysteria2_19991")
        XCTAssertEqual(draft.protocolType, .hysteria2)
        XCTAssertEqual(draft.serverHost, "realm-host.example")
        XCTAssertEqual(draft.serverPortText, "19991")
        XCTAssertEqual(draft.tlsFingerprint, "example-pin+value/for+tests=")
    }

    func testParsesTUICShareLink() throws {
        let draft = try URIImport.parseDraft("tuic://00000000-0000-0000-0000-000000000003:tuic-password@tuic.example.com:443?sni=tuic.example.com&alpn=h3#TUIC")
        let node = try draft.buildNode(id: NodeID(rawValue: "node-tuic"), keychainService: "com.irock.nodes")

        XCTAssertEqual(draft.name, "TUIC")
        XCTAssertEqual(node.protocolType, .tuic)
        XCTAssertEqual(node.transport, .quic)
        XCTAssertEqual(node.tls.alpn, ["h3"])
    }

    func testParsesPlainAndBase64SubscriptionDrafts() throws {
        let plain = """
        trojan://secret-password@trojan.example.com:443#Trojan
        hy2://hysteria-password@hy2.example.com:443#HY2
        """
        let base64 = Data(plain.utf8).base64EncodedString()

        let drafts = try URIImport.parseSubscriptionDrafts(base64)

        XCTAssertEqual(drafts.map(\.protocolType), [.trojan, .hysteria2])
        XCTAssertEqual(drafts.map(\.name), ["Trojan", "HY2"])
    }
}
