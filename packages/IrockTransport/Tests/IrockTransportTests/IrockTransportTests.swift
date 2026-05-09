import XCTest
import IrockCore
@testable import IrockTransport

final class IrockTransportTests: XCTestCase {
    func testTransportRequestStoresEndpointAndKind() {
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 443)
        XCTAssertEqual(request.transport, .grpc)
    }

    func testNoopTransportFailsWithUnsupportedTransport() async {
        let transport = NoopTransportAdapter()
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        do {
            _ = try await transport.open(request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.quic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
