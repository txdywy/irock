import XCTest
import IrockCore
@testable import IrockProtocols

final class IrockProtocolsTests: XCTestCase {
    func testProxyRequestStoresNodeAndDestination() {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo Trojan",
            protocolType: .trojan,
            serverHost: "example.com",
            serverPort: 443,
            credentials: .password("secret"),
            transport: .tcp,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: .disabled
        )
        let request = ProxyRequest(node: node, destinationHost: "apple.com", destinationPort: 443)

        XCTAssertEqual(request.node.protocolType, .trojan)
        XCTAssertEqual(request.destinationHost, "apple.com")
        XCTAssertEqual(request.destinationPort, 443)
    }

    func testNoopProxyAdapterFailsWithUnsupportedProtocol() async {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo TUIC",
            protocolType: .tuic,
            serverHost: "example.com",
            serverPort: 443,
            credentials: .token("token"),
            transport: .quic,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: .enabled
        )
        let adapter = NoopProxyAdapter()
        let request = ProxyRequest(node: node, destinationHost: "apple.com", destinationPort: 443)

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProtocolAdapterError {
            XCTAssertEqual(error, .unsupportedProtocol(.tuic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
