import XCTest
import IrockCore
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

    func testEstablishedProxyConnectionStoresNodeIDAndDestination() {
        let connection = EstablishedProxyConnection(
            nodeID: NodeID(rawValue: "node-1"),
            destination: .host("apple.com", port: 443)
        )

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .host("apple.com", port: 443))
    }

    func testNoopProxyAdapterFailsWithUnsupportedProtocol() async {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo TUIC",
            protocolType: .tuic,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .quic,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: .enabled
        )
        let adapter = NoopProxyAdapter()
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProtocolAdapterError {
            XCTAssertEqual(error, .unsupportedProtocol(.tuic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeNode(protocolType: ProxyProtocolType, transport: TransportType) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo Node",
            protocolType: protocolType,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: transport,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: .disabled
        )
    }
}
