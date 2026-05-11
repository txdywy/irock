import Foundation
import XCTest
import IrockCore
import IrockTransport
@testable import IrockProtocols

final class IrockProtocolsTests: XCTestCase {
    func testProxyDestinationEquatableCases() {
        XCTAssertEqual(ProxyDestination.host("apple.com", port: 443), .host("apple.com", port: 443))
        XCTAssertEqual(ProxyDestination.ipv4("93.184.216.34", port: 443), .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(ProxyDestination.ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443), .ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443))
        XCTAssertNotEqual(ProxyDestination.host("apple.com", port: 443), .host("apple.com", port: 80))
    }

    func testProxyRequestStoresNodeDestinationAndMetadata() {
        let node = makeNode(protocolType: .trojan, transport: .tcp)
        let request = ProxyRequest(
            node: node,
            destination: .host("apple.com", port: 443),
            metadata: ["source": "unit-test"]
        )

        XCTAssertEqual(request.node.protocolType, .trojan)
        XCTAssertEqual(request.destination, .host("apple.com", port: 443))
        XCTAssertEqual(request.metadata, ["source": "unit-test"])
    }

    func testProxyRequestDefaultsMetadataToEmpty() {
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp), destination: .ipv4("1.1.1.1", port: 53))

        XCTAssertEqual(request.metadata, [:])
    }

    func testShadowsocksStreamRequestBuildsAES256GCMHostOpenBytes() throws {
        let request = try ShadowsocksStreamRequest(
            credential: "aes-256-gcm:pass",
            destination: .host("apple.com", port: 443),
            salt: Data(repeating: 1, count: 32)
        )

        XCTAssertEqual(request.cipher, "aes-256-gcm")
        XCTAssertEqual(request.addressFrameHex, "03096170706c652e636f6d01bb")
        XCTAssertEqual(request.openBytesHex, "0101010101010101010101010101010101010101010101010101010101010101620abbadfec9a6d19bc1964dc25cdc714a40d7df10cbff62357470f76caa6c7eb90f8d9a21aab8e2bff8ab3c1b4997")
        XCTAssertEqual(request.openBytes.count, 79)
        XCTAssertEqual(request.metadata["shadowsocksCipher"], "aes-256-gcm")
        XCTAssertEqual(request.metadata["shadowsocksAddressFrameHex"], request.addressFrameHex)
        XCTAssertEqual(request.metadata["shadowsocksStreamOpenHex"], request.openBytesHex)
    }

    func testShadowsocksStreamRequestEncodesIPv4DestinationFrame() throws {
        let request = try ShadowsocksStreamRequest(
            credential: "aes-256-gcm:pass",
            destination: .ipv4("93.184.216.34", port: 443),
            salt: Data(repeating: 2, count: 32)
        )

        XCTAssertEqual(request.addressFrameHex, "015db8d82201bb")
    }

    func testShadowsocksStreamRequestEncodesIPv6DestinationFrame() throws {
        let request = try ShadowsocksStreamRequest(
            credential: "aes-256-gcm:pass",
            destination: .ipv6("2606:2800:0220:0001:0248:1893:25c8:1946", port: 443),
            salt: Data(repeating: 3, count: 32)
        )

        XCTAssertEqual(request.addressFrameHex, "0426062800022000010248189325c8194601bb")
    }

    func testShadowsocksStreamRequestRejectsUnsupportedMethod() {
        XCTAssertThrowsError(try ShadowsocksStreamRequest(
            credential: "chacha20-ietf-poly1305:pass",
            destination: .host("apple.com", port: 443),
            salt: Data(repeating: 1, count: 32)
        )) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("unsupported shadowsocks method"))
        }
    }

    func testShadowsocksStreamRequestRejectsInvalidCredential() {
        XCTAssertThrowsError(try ShadowsocksStreamRequest(
            credential: "aes-256-gcm",
            destination: .host("apple.com", port: 443),
            salt: Data(repeating: 1, count: 32)
        )) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid shadowsocks credential"))
        }
    }

    func testShadowsocksStreamRequestRejectsInvalidSalt() {
        XCTAssertThrowsError(try ShadowsocksStreamRequest(
            credential: "aes-256-gcm:pass",
            destination: .host("apple.com", port: 443),
            salt: Data(repeating: 1, count: 31)
        )) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid shadowsocks salt"))
        }
    }

    func testVMessOpenRequestBuildsStableMetadataAndPayload() throws {
        let request = try VMessOpenRequest(
            userID: "00000000-0000-0000-0000-000000000001",
            destination: .host("apple.com", port: 443)
        )

        XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
        XCTAssertEqual(request.security, "auto")
        XCTAssertEqual(request.alterID, 0)
        XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "vmess-foundation:host:apple.com:443:auto:0")
        XCTAssertEqual(request.metadata["vmessUserIDPresent"], "true")
        XCTAssertEqual(request.metadata["vmessDestination"], "host:apple.com:443")
        XCTAssertEqual(request.metadata["vmessSecurity"], "auto")
        XCTAssertEqual(request.metadata["vmessAlterID"], "0")
        XCTAssertNil(request.metadata["vmessUserID"])
        XCTAssertFalse(request.openBytes.contains(Data("00000000-0000-0000-0000-000000000001".utf8)))
    }

    func testVMessOpenRequestRejectsInvalidUserID() {
        XCTAssertThrowsError(try VMessOpenRequest(userID: "not-a-uuid", destination: .host("apple.com", port: 443))) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid vmess user id"))
        }
    }

    func testVLESSOpenRequestBuildsCredentialSafeMetadataAndPayload() throws {
        let request = try VLESSOpenRequest(
            userID: "00000000-0000-0000-0000-000000000002",
            destination: .host("apple.com", port: 443)
        )

        XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
        XCTAssertEqual(request.security, "none")
        XCTAssertEqual(request.flow, "")
        XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "vless-foundation:host:apple.com:443:none:")
        XCTAssertEqual(request.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(request.metadata["vlessUserID"])
        XCTAssertEqual(request.metadata["vlessDestination"], "host:apple.com:443")
        XCTAssertEqual(request.metadata["vlessSecurity"], "none")
        XCTAssertEqual(request.metadata["vlessFlow"], "")
        XCTAssertFalse(request.openBytes.contains(Data("00000000-0000-0000-0000-000000000002".utf8)))
    }

    func testVLESSOpenRequestRejectsInvalidUserID() {
        XCTAssertThrowsError(try VLESSOpenRequest(userID: "not-a-uuid", destination: .host("apple.com", port: 443))) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid vless user id"))
        }
    }

    func testTrojanOpenRequestBuildsCredentialSafeMetadataAndPayload() throws {
        let request = try TrojanOpenRequest(
            password: "secret-password",
            destination: .host("apple.com", port: 443),
            serverName: "trojan.example.com"
        )

        XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
        XCTAssertEqual(request.serverName, "trojan.example.com")
        XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "trojan-foundation:host:apple.com:443:trojan.example.com")
        XCTAssertEqual(request.metadata["trojanPasswordPresent"], "true")
        XCTAssertNil(request.metadata["trojanPassword"])
        XCTAssertEqual(request.metadata["trojanDestination"], "host:apple.com:443")
        XCTAssertEqual(request.metadata["trojanServerName"], "trojan.example.com")
        XCTAssertFalse(request.openBytes.contains(Data("secret-password".utf8)))
    }

    func testTrojanOpenRequestRejectsEmptyPassword() {
        XCTAssertThrowsError(try TrojanOpenRequest(password: "   ", destination: .host("apple.com", port: 443))) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("missing trojan password"))
        }
    }

    func testEstablishedProxyConnectionStoresNodeIDAndDestination() {
        let connection = EstablishedProxyConnection(
            nodeID: NodeID(rawValue: "node-1"),
            destination: .host("apple.com", port: 443)
        )

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
    }

    func testUnsupportedProxyAdapterFailsWithRequestedProtocol() async {
        let node = makeNode(protocolType: .tuic, transport: .quic)
        let adapter = UnsupportedProxyAdapter(protocolType: .tuic)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.tuic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNoopProxyAdapterRemainsUnsupportedAlias() async {
        let node = makeNode(protocolType: .hysteria2, transport: .quic)
        let adapter = NoopProxyAdapter()
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.hysteria2))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProxyProtocolErrorDescriptionsAreStableAndCredentialSafe() {
        let errors: [(ProxyProtocolError, String)] = [
            (.invalidConfiguration("missing server host"), "Invalid configuration"),
            (.dnsFailed("example.com"), "DNS failed"),
            (.tcpConnectFailed("connection refused"), "TCP connect failed"),
            (.tlsHandshakeFailed("certificate rejected"), "TLS handshake failed"),
            (.authenticationFailed("method rejected"), "Authentication failed"),
            (.unsupportedTransport(.quic), "Unsupported transport: quic"),
            (.unsupportedProtocol(.tuic), "Unsupported protocol: tuic"),
            (.protocolHandshakeFailed("bad response"), "Protocol handshake failed"),
            (.quicHandshakeFailed("timeout"), "QUIC handshake failed"),
            (.udpUnsupported, "UDP unsupported"),
            (.remoteClosed, "Remote closed"),
            (.timeout, "Timeout")
        ]

        for (error, description) in errors {
            XCTAssertEqual(error.description, description)
            XCTAssertFalse(error.description.contains("secret"))
            XCTAssertFalse(error.description.contains("password"))
            XCTAssertFalse(error.description.contains("token"))
        }
    }

    func testProxyProtocolErrorDescriptionsRedactSensitiveAssociatedStrings() {
        let errors: [ProxyProtocolError] = [
            .invalidConfiguration("uri=ss://password=secret-token@example.com"),
            .dnsFailed("password=secret-token"),
            .tcpConnectFailed("token=secret-token"),
            .tlsHandshakeFailed("password=secret-token"),
            .authenticationFailed("password=secret-token"),
            .protocolHandshakeFailed("password=secret-token"),
            .quicHandshakeFailed("password=secret-token")
        ]

        for error in errors {
            XCTAssertFalse(error.description.contains("password"))
            XCTAssertFalse(error.description.contains("secret"))
            XCTAssertFalse(error.description.contains("token"))
        }
    }

    func testProxyAdapterRegistryReturnsRegisteredAdapter() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let registry = ProxyAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .trojan)
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        let connection = try await selected.connect(request: request)

        XCTAssertEqual(selected.supportedProtocol, .trojan)
        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
    }

    func testProxyAdapterRegistryFallsBackToUnsupportedAdapter() async {
        let registry = ProxyAdapterRegistry(adapters: [])
        let selected = registry.adapter(for: .vless)
        let request = ProxyRequest(node: makeNode(protocolType: .vless, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await selected.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vless))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProxyAdapterRegistryUsesLastRegisteredAdapterForDuplicates() async throws {
        let first = RecordingProxyAdapter(protocolType: .vmess, connectionNodeID: NodeID(rawValue: "first"))
        let second = RecordingProxyAdapter(protocolType: .vmess, connectionNodeID: NodeID(rawValue: "second"))
        let registry = ProxyAdapterRegistry(adapters: [first, second])
        let selected = registry.adapter(for: .vmess)
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        let connection = try await selected.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "second"))
    }

    func testTransportBackedProxyAdapterOpensNodeTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .grpc)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .trojan, transport: .grpc)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .grpc)
        XCTAssertEqual(transport.requests.first?.tls?.enabled, true)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "trojan")
        XCTAssertEqual(transport.requests.first?.metadata["destination"], "host:apple.com:443")
    }

    func testTransportBackedProxyAdapterRejectsProtocolMismatchBeforeOpeningTransport() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vmess))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVMessProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .vmess, transport: .tcp, credentialAccount: "00000000-0000-0000-0000-000000000001")
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "vmess")
        XCTAssertEqual(transport.requests.first?.metadata["vmessUserIDPresent"], "true")
        XCTAssertNil(transport.requests.first?.metadata["vmessUserID"])
        XCTAssertEqual(transport.requests.first?.metadata["vmessDestination"], "host:apple.com:443")
        XCTAssertEqual(String(data: transport.requests.first?.initialPayload ?? Data(), encoding: .utf8), "vmess-foundation:host:apple.com:443:auto:0")
        XCTAssertFalse((transport.requests.first?.initialPayload ?? Data()).contains(Data("00000000-0000-0000-0000-000000000001".utf8)))
    }

    func testVMessProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVMessProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
        let cases: [(ProxyNode, ProxyProtocolError)] = [
            (makeNode(protocolType: .vmess, transport: .tcp, serverHost: "   ", credentialAccount: "00000000-0000-0000-0000-000000000001"), .invalidConfiguration("missing vmess server host")),
            (makeNode(protocolType: .vmess, transport: .tcp, serverPort: 0, credentialAccount: "00000000-0000-0000-0000-000000000001"), .invalidConfiguration("invalid vmess server port")),
            (makeNode(protocolType: .vmess, transport: .tcp, credentialAccount: "not-a-uuid"), .invalidConfiguration("invalid vmess user id")),
            (makeNode(protocolType: .vmess, transport: .quic, credentialAccount: "00000000-0000-0000-0000-000000000001"), .unsupportedTransport(.quic))
        ]

        for (node, expectedError) in cases {
            let transport = RecordingTransportAdapter(transport: .tcp)
            let adapter = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
            do {
                _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
                XCTFail("Expected VMess validation failure")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(transport.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testVLESSProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .vless, transport: .tcp, credentialAccount: "00000000-0000-0000-0000-000000000002")
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "vless")
        XCTAssertEqual(transport.requests.first?.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(transport.requests.first?.metadata["vlessUserID"])
        XCTAssertEqual(transport.requests.first?.metadata["vlessDestination"], "host:apple.com:443")
        XCTAssertEqual(String(data: transport.requests.first?.initialPayload ?? Data(), encoding: .utf8), "vless-foundation:host:apple.com:443:none:")
        XCTAssertFalse((transport.requests.first?.initialPayload ?? Data()).contains(Data("00000000-0000-0000-0000-000000000002".utf8)))
    }

    func testVLESSProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVLESSProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
        let cases: [(ProxyNode, ProxyProtocolError)] = [
            (makeNode(protocolType: .vless, transport: .tcp, serverHost: "   ", credentialAccount: "00000000-0000-0000-0000-000000000002"), .invalidConfiguration("missing vless server host")),
            (makeNode(protocolType: .vless, transport: .tcp, serverPort: 0, credentialAccount: "00000000-0000-0000-0000-000000000002"), .invalidConfiguration("invalid vless server port")),
            (makeNode(protocolType: .vless, transport: .tcp, credentialAccount: "not-a-uuid"), .invalidConfiguration("invalid vless user id")),
            (makeNode(protocolType: .vless, transport: .quic, credentialAccount: "00000000-0000-0000-0000-000000000002"), .unsupportedTransport(.quic))
        ]

        for (node, expectedError) in cases {
            let transport = RecordingTransportAdapter(transport: .tcp)
            let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
            do {
                _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
                XCTFail("Expected VLESS validation failure")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(transport.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testTrojanProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TrojanProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let tls = TLSOptions(enabled: true, serverName: "trojan.example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let node = makeNode(protocolType: .trojan, transport: .tcp, tls: tls, credentialAccount: "secret-password")
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.tls, tls)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "trojan")
        XCTAssertEqual(transport.requests.first?.metadata["trojanPasswordPresent"], "true")
        XCTAssertNil(transport.requests.first?.metadata["trojanPassword"])
        XCTAssertEqual(transport.requests.first?.metadata["trojanDestination"], "host:apple.com:443")
        XCTAssertEqual(transport.requests.first?.metadata["trojanServerName"], "trojan.example.com")
        XCTAssertEqual(String(data: transport.requests.first?.initialPayload ?? Data(), encoding: .utf8), "trojan-foundation:host:apple.com:443:trojan.example.com")
        XCTAssertFalse((transport.requests.first?.initialPayload ?? Data()).contains(Data("secret-password".utf8)))
    }

    func testTrojanProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TrojanProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vmess))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTrojanProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
        let cases: [(ProxyNode, ProxyProtocolError)] = [
            (makeNode(protocolType: .trojan, transport: .tcp, serverHost: "   ", credentialAccount: "secret-password"), .invalidConfiguration("missing trojan server host")),
            (makeNode(protocolType: .trojan, transport: .tcp, serverPort: 0, credentialAccount: "secret-password"), .invalidConfiguration("invalid trojan server port")),
            (makeNode(protocolType: .trojan, transport: .tcp, credentialAccount: "   "), .invalidConfiguration("missing trojan password")),
            (makeNode(protocolType: .trojan, transport: .quic, credentialAccount: "secret-password"), .unsupportedTransport(.quic))
        ]

        for (node, expectedError) in cases {
            let transport = RecordingTransportAdapter(transport: .tcp)
            let adapter = TrojanProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
            do {
                _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
                XCTFail("Expected Trojan validation failure")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(transport.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testProtocolFoundationAdaptersOpenWebSocketTransport() async throws {
        try await assertProtocolFoundationAdaptersOpen(transport: .webSocket)
    }

    func testProtocolFoundationAdaptersOpenHTTP2Transport() async throws {
        try await assertProtocolFoundationAdaptersOpen(transport: .http2)
    }

    func testProtocolFoundationAdaptersOpenGRPCTransport() async throws {
        try await assertProtocolFoundationAdaptersOpen(transport: .grpc)
    }

    private func assertProtocolFoundationAdaptersOpen(transport transportType: TransportType) async throws {
        let cases: [(ProxyProtocolType, String)] = [
            (.vmess, "00000000-0000-0000-0000-000000000001"),
            (.vless, "00000000-0000-0000-0000-000000000002"),
            (.trojan, "secret-password")
        ]

        for (protocolType, credentialAccount) in cases {
            let transport = RecordingTransportAdapter(transport: transportType)
            let registry = TransportAdapterRegistry(adapters: [transport])
            let adapter: any ProxyAdapter
            switch protocolType {
            case .vmess:
                adapter = VMessProxyAdapter(transportRegistry: registry)
            case .vless:
                adapter = VLESSProxyAdapter(transportRegistry: registry)
            case .trojan:
                adapter = TrojanProxyAdapter(transportRegistry: registry)
            default:
                XCTFail("Unexpected protocol type")
                return
            }
            let node = makeNode(protocolType: protocolType, transport: transportType, credentialAccount: credentialAccount)

            _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))

            XCTAssertEqual(transport.requests.count, 1)
            XCTAssertEqual(transport.requests.first?.transport, transportType)
            XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], protocolType.rawValue)
        }
    }

    func testTransportBackedProxyAdapterOmitsDisabledTLS() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp, tls: .disabled), destination: .ipv4("93.184.216.34", port: 443))

        _ = try await adapter.connect(request: request)

        XCTAssertNil(transport.requests.first?.tls)
        XCTAssertEqual(transport.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
    }

    func testShadowsocksProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsEmptyServerHostBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, serverHost: "   "), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("missing shadowsocks server host"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsInvalidServerPortBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, serverPort: 0), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("invalid shadowsocks server port"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsEmptyCredentialAccountBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, credentialAccount: "   "), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("missing shadowsocks credential account"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsNonTCPTransportBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .grpc)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .grpc), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterReportsSupportedProtocol() {
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: []))

        XCTAssertEqual(adapter.supportedProtocol, .shadowsocks)
    }

    func testShadowsocksProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [transport]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(transport.requests.first?.metadata["shadowsocksCipher"], "aes-256-gcm")
        XCTAssertEqual(transport.requests.first?.metadata["shadowsocksAddressFrameHex"], "03096170706c652e636f6d01bb")
        XCTAssertEqual(transport.requests.first?.metadata["shadowsocksStreamOpenHex"]?.count, 158)
        XCTAssertEqual(transport.requests.first?.initialPayload?.count, 79)
    }

    func testTransportBackedProxyAdapterMapsTransportErrorsToProtocolErrors() async {
        let cases: [(TransportError, ProxyProtocolError)] = [
            (.invalidConfiguration("secret invalid"), .invalidConfiguration("transport invalid")),
            (.dnsFailed("secret host"), .dnsFailed("transport dns failed")),
            (.tcpConnectFailed("password refused"), .tcpConnectFailed("transport tcp connect failed")),
            (.tlsHandshakeFailed("token rejected"), .tlsHandshakeFailed("transport tls handshake failed")),
            (.unsupportedTransport(.quic), .unsupportedTransport(.quic)),
            (.quicHandshakeFailed("secret timeout"), .quicHandshakeFailed("transport quic handshake failed")),
            (.remoteClosed, .remoteClosed),
            (.timeout, .timeout)
        ]

        for (transportError, expectedProtocolError) in cases {
            let adapter = TransportBackedProxyAdapter(
                protocolType: .trojan,
                transportRegistry: TransportAdapterRegistry(adapters: [FailingTransportAdapter(transport: .tcp, error: transportError)])
            )
            let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

            do {
                _ = try await adapter.connect(request: request)
                XCTFail("Expected protocol error")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedProtocolError)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testShadowsocksProxyAdapterPropagatesMappedTransportFailure() async {
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [FailingTransportAdapter(transport: .tcp, error: .tcpConnectFailed("password refused"))]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected mapped transport failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tcpConnectFailed("transport tcp connect failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRoutesEnabledTLSThroughSelectorTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [selector]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp, tls: tls)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.host, "example.com")
        XCTAssertEqual(tlsChild.requests.first?.port, 443)
        XCTAssertEqual(tlsChild.requests.first?.transport, .tcp)
        XCTAssertEqual(tlsChild.requests.first?.tls, tls)
        XCTAssertEqual(tlsChild.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(tlsChild.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(tlsChild.requests.first?.metadata["destination"], "host:apple.com:443")
    }

    func testShadowsocksProxyAdapterRoutesDisabledTLSThroughSelectorPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [selector]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp, tls: .disabled)
        let request = ProxyRequest(node: node, destination: .ipv4("93.184.216.34", port: 443))

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(plain.requests.first?.host, "example.com")
        XCTAssertEqual(plain.requests.first?.port, 443)
        XCTAssertEqual(plain.requests.first?.transport, .tcp)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(plain.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testShadowsocksProxyAdapterMapsSelectorTLSChildFailure() async {
        let selector = TCPTLSTransportAdapter(
            plain: RecordingTransportAdapter(transport: .tcp),
            tls: FailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("tls refused"))
        )
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [selector]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, tls: tls), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected mapped TLS failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tlsHandshakeFailed("transport tls handshake failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterMapsSelectorPlainChildFailure() async {
        let selector = TCPTLSTransportAdapter(
            plain: FailingTransportAdapter(transport: .tcp, error: .tcpConnectFailed("plain refused")),
            tls: RecordingTransportAdapter(transport: .tcp)
        )
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [selector]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, tls: .disabled), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected mapped plain failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tcpConnectFailed("transport tcp connect failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeNode(
        protocolType: ProxyProtocolType,
        transport: TransportType,
        tls: TLSOptions = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
        serverHost: String = "example.com",
        serverPort: Int = 443,
        credentialAccount: String = "node-1"
    ) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo Node",
            protocolType: protocolType,
            serverHost: serverHost,
            serverPort: serverPort,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: credentialAccount),
            transport: transport,
            tls: tls,
            udpPolicy: .disabled
        )
    }

    private struct RecordingProxyAdapter: ProxyAdapter {
        let supportedProtocol: ProxyProtocolType
        let connectionNodeID: NodeID

        init(protocolType: ProxyProtocolType, connectionNodeID: NodeID = NodeID(rawValue: "node-1")) {
            self.supportedProtocol = protocolType
            self.connectionNodeID = connectionNodeID
        }

        func connect(request: ProxyRequest) async throws -> any ProxyConnection {
            EstablishedProxyConnection(nodeID: connectionNodeID, destination: request.destination)
        }
    }
}

private struct StaticShadowsocksCredentialResolver: ShadowsocksCredentialResolver {
    let credential: String

    func credential(for reference: CredentialReference) throws -> String {
        credential
    }
}

private final class RecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    private let lock = NSLock()
    private var storedRequests: [TransportRequest] = []

    var requests: [TransportRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    init(transport: TransportType) {
        self.supportedTransport = transport
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        record(request)
        return EstablishedTransportConnection(host: request.host, port: request.port, transport: request.transport)
    }

    private func record(_ request: TransportRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(request)
    }
}

private struct FailingTransportAdapter: TransportAdapter {
    let supportedTransport: TransportType
    let error: TransportError

    init(transport: TransportType, error: TransportError) {
        self.supportedTransport = transport
        self.error = error
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        throw error
    }
}
