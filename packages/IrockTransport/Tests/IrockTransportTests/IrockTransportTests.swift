import XCTest
import IrockCore
@testable import IrockTransport

final class IrockTransportTests: XCTestCase {
    func testTransportRequestStoresEndpointTLSAndMetadata() {
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc, tls: tls, metadata: ["source": "unit-test"])

        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 443)
        XCTAssertEqual(request.transport, .grpc)
        XCTAssertEqual(request.tls, tls)
        XCTAssertEqual(request.metadata, ["source": "unit-test"])
    }

    func testTransportRequestDefaultsTLSAndMetadata() {
        let request = TransportRequest(host: "example.com", port: 80, transport: .tcp)

        XCTAssertNil(request.tls)
        XCTAssertEqual(request.metadata, [:])
    }

    func testEstablishedTransportConnectionStoresEndpointAndKind() {
        let connection = EstablishedTransportConnection(host: "example.com", port: 443, transport: .tcp)

        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
    }

    func testUnsupportedTransportAdapterFailsWithRequestedTransport() async {
        let adapter = UnsupportedTransportAdapter(transport: .quic)
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.quic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNoopTransportAdapterRemainsUnsupportedAlias() async {
        let adapter = NoopTransportAdapter()
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportErrorDescriptionsAreStableAndCredentialSafe() {
        let errors: [(TransportError, String)] = [
            (.invalidConfiguration("secret missing server host"), "Invalid configuration"),
            (.dnsFailed("secret.example.com"), "DNS failed"),
            (.tcpConnectFailed("password refused"), "TCP connect failed"),
            (.tlsHandshakeFailed("token rejected"), "TLS handshake failed"),
            (.unsupportedTransport(.quic), "Unsupported transport: quic"),
            (.quicHandshakeFailed("secret timeout"), "QUIC handshake failed"),
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
}
