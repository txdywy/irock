import XCTest
import IrockCore
import IrockProtocols
import IrockStorage
import IrockTransport
@testable import IrockTunnelCore

final class TunnelRuntimeBootstrapTests: XCTestCase {
    func testShadowsocksTCPBootstrapBuildsRuntimeWithPlainTransport() async throws {
        let plain = BootstrapRecordingTransportAdapter(transport: .tcp)
        let tlsChild = BootstrapRecordingTransportAdapter(transport: .tcp)
        let reader = InMemoryPacketReader(packets: [Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)])
        let writer = InMemoryPacketWriter()
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: bootstrapSnapshot(tls: .disabled),
            reader: reader,
            writer: writer,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tlsChild,
            batchLimit: 16,
            flowLimit: 32
        )

        let summary = try await runtime.runOnce()

        XCTAssertEqual(summary.readCount, 1)
        XCTAssertEqual(summary.writtenCount, 1)
        XCTAssertEqual(summary.dropCount, 0)
        XCTAssertEqual(summary.proxyConnectCount, 1)
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(tlsChild.requests, [])
        XCTAssertEqual(writer.writtenResults.count, 1)
        let status = try XCTUnwrap(statusStore.load())
        XCTAssertEqual(status.phase, .connected)
        XCTAssertEqual(status.message, "Packet batch processed")
        XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Tunnel runtime connected"])
    }

    func testShadowsocksTCPBootstrapPropagatesInvalidRoutingManifest() throws {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: nil, action: .direct)]
        )
        let snapshot = bootstrapSnapshot(tls: .disabled, routingRuleManifest: manifest)

        XCTAssertThrowsError(try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: snapshot,
            reader: InMemoryPacketReader(packets: []),
            writer: InMemoryPacketWriter(),
            statusStore: InMemoryRuntimeStatusStore(),
            logStore: InMemoryRuntimeLogStore(),
            plain: BootstrapRecordingTransportAdapter(transport: .tcp),
            tls: BootstrapRecordingTransportAdapter(transport: .tcp),
            batchLimit: 16,
            flowLimit: 32
        )) { error in
            XCTAssertEqual(error as? RuntimeRoutingRuleAdapterError, .missingValue(kind: .domainSuffix))
        }
    }

    func testShadowsocksTCPBootstrapPublishesFailureWhenTLSChildFails() async throws {
        let plain = BootstrapRecordingTransportAdapter(transport: .tcp)
        let tlsChild = BootstrapFailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("secret tls refused"))
        let reader = InMemoryPacketReader(packets: [Packet.ipv4TCP(id: "tcp-1", source: .v4(10, 0, 0, 2), destination: .v4(93, 184, 216, 34), sourcePort: 51_234, destinationPort: 443)])
        let writer = InMemoryPacketWriter()
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let runtime = try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: bootstrapSnapshot(tls: tls),
            reader: reader,
            writer: writer,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tlsChild,
            batchLimit: 16,
            flowLimit: 32
        )

        do {
            _ = try await runtime.runOnce()
            XCTFail("Expected mapped TLS failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tlsHandshakeFailed("transport tls handshake failed"))
            XCTAssertEqual(plain.requests, [])
            XCTAssertEqual(writer.writtenResults, [])
            let status = try XCTUnwrap(statusStore.load())
            XCTAssertEqual(status.phase, .failed)
            XCTAssertEqual(status.message, "Proxy adapter failed: TLS handshake failed")
            XCTAssertEqual(try logStore.loadRecent().map(\.message), ["Tunnel runtime preparing", "Proxy adapter failed: TLS handshake failed"])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class BootstrapRecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
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

private struct BootstrapFailingTransportAdapter: TransportAdapter {
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

private func bootstrapSnapshot(tls: TLSOptions, routingRuleManifest: RuntimeRoutingRuleManifest = RuntimeRoutingRuleManifest(version: 1, rules: [RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)])) -> RuntimeSnapshot {
    RuntimeSnapshot(
        id: SnapshotID(rawValue: "snapshot-1"),
        selectedNode: ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo",
            protocolType: .shadowsocks,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: tls,
            udpPolicy: .disabled
        ),
        routeMode: .globalProxy,
        logLevel: .user,
        routingRuleManifest: routingRuleManifest
    )
}
