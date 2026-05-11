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

    func testTransportAdapterRegistryReturnsRegisteredAdapter() async throws {
        let adapter = RecordingTransportAdapter(transport: .grpc)
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .grpc)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .grpc)
        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .grpc)
    }

    func testTransportAdapterRegistryFallsBackToUnsupportedAdapter() async {
        let registry = TransportAdapterRegistry(adapters: [])
        let selected = registry.adapter(for: .quic)
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        do {
            _ = try await selected.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.quic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportAdapterRegistryUsesLastRegisteredAdapterForDuplicates() async throws {
        let first = RecordingTransportAdapter(transport: .tcp, connectionHost: "first.example.com")
        let second = RecordingTransportAdapter(transport: .tcp, connectionHost: "second.example.com")
        let registry = TransportAdapterRegistry(adapters: [first, second])
        let selected = registry.adapter(for: .tcp)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(connection.host, "second.example.com")
    }

    func testTCPTransportAdapterRejectsNonTCPBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(dialer.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTransportAdapterRejectsEmptyHostBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let request = TransportRequest(host: "   ", port: 443, transport: .tcp)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as TransportError {
            XCTAssertEqual(error, .invalidConfiguration("missing tcp host"))
            XCTAssertEqual(dialer.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTransportAdapterRejectsInvalidPortBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)

        for port in [0, 65_536] {
            let request = TransportRequest(host: "example.com", port: port, transport: .tcp)

            do {
                _ = try await adapter.open(request: request)
                XCTFail("Expected invalid configuration")
            } catch let error as TransportError {
                XCTAssertEqual(error, .invalidConfiguration("invalid tcp port"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(dialer.requests, [])
    }

    func testTCPTransportAdapterRejectsTLSBeforeDialing() async {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.tcp))
            XCTAssertEqual(dialer.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTCPTransportAdapterReportsSupportedTransport() {
        let adapter = TCPTransportAdapter(dialer: RecordingTCPDialer())

        XCTAssertEqual(adapter.supportedTransport, .tcp)
    }

    func testTCPTransportAdapterDialsHostAndPortAndReturnsConnection() async throws {
        let dialer = RecordingTCPDialer()
        let adapter = TCPTransportAdapter(dialer: dialer)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(dialer.requests, [TCPDialRequest(host: "example.com", port: 443)])
    }

    func testTCPTransportAdapterPropagatesDialerTransportError() async {
        let adapter = TCPTransportAdapter(dialer: FailingTCPDialer(error: .tcpConnectFailed("connection refused")))
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        do {
            _ = try await adapter.open(request: request)
            XCTFail("Expected dialer failure")
        } catch let error as TransportError {
            XCTAssertEqual(error, .tcpConnectFailed("connection refused"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportAdapterRegistryCanSelectTCPTransportAdapter() async throws {
        let adapter = TCPTransportAdapter(dialer: RecordingTCPDialer())
        let registry = TransportAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .tcp)
        let request = TransportRequest(host: "example.com", port: 443, transport: .tcp)

        let connection = try await selected.open(request: request)

        XCTAssertEqual(selected.supportedTransport, .tcp)
        XCTAssertEqual(connection.host, "example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
    }

    func testTLSTransportAdapterReportsTCPTransport() {
        let adapter = TLSTransportAdapter(underlying: RecordingTransportAdapter(transport: .tcp))

        XCTAssertEqual(adapter.supportedTransport, .tcp)
    }

    func testTLSTransportAdapterStripsTLSAndReturnsUnderlyingConnection() async throws {
        let underlying = RecordingTransportAdapter(transport: .tcp, connectionHost: "connected.example.com")
        let adapter = TLSTransportAdapter(underlying: underlying)
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: nil)
        let request = TransportRequest(host: " example.com ", port: 443, transport: .tcp, tls: tls, metadata: ["source": "unit-test"])

        let connection = try await adapter.open(request: request)

        XCTAssertEqual(connection.host, "connected.example.com")
        XCTAssertEqual(connection.port, 443)
        XCTAssertEqual(connection.transport, .tcp)
        XCTAssertEqual(underlying.requests, [TransportAdapterRequest(host: "example.com", port: 443, transport: .tcp, tls: nil, metadata: ["source": "unit-test"])])
    }
}

private struct TransportAdapterRequest: Equatable {
    let host: String
    let port: Int
    let transport: TransportType
    let tls: TLSOptions?
    let metadata: [String: String]
}

private final class RecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    let connectionHost: String
    private let lock = NSLock()
    private var storedRequests: [TransportAdapterRequest] = []

    init(transport: TransportType, connectionHost: String = "example.com") {
        self.supportedTransport = transport
        self.connectionHost = connectionHost
    }

    var requests: [TransportAdapterRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        record(request)
        return EstablishedTransportConnection(host: connectionHost, port: request.port, transport: request.transport)
    }

    private func record(_ request: TransportRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(TransportAdapterRequest(host: request.host, port: request.port, transport: request.transport, tls: request.tls, metadata: request.metadata))
    }
}

private struct TCPDialRequest: Equatable {
    let host: String
    let port: Int
}

private final class RecordingTCPDialer: TCPDialer, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [TCPDialRequest] = []

    var requests: [TCPDialRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func open(host: String, port: Int) async throws -> TCPDialResult {
        record(host: host, port: port)
        return TCPDialResult(host: host, port: port)
    }

    private func record(host: String, port: Int) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(TCPDialRequest(host: host, port: port))
    }
}

private struct FailingTCPDialer: TCPDialer {
    let error: TransportError

    func open(host: String, port: Int) async throws -> TCPDialResult {
        throw error
    }
}
