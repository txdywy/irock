import XCTest
import IrockCore
import IrockProtocols
import IrockRouting
import IrockTransport
@testable import IrockTunnelCore

final class TunnelRuntimeConfigurationTests: XCTestCase {
    func testConfigurationConsumesRuntimeSnapshotRouteModeAndLimits() {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .globalProxy,
            logLevel: .user
        )

        let configuration = TunnelRuntimeConfiguration(snapshot: snapshot, routingEngine: RoutingEngine(rules: [.final(.reject)]), batchLimit: 32, flowLimit: 128)

        XCTAssertEqual(configuration.routeMode, .globalProxy)
        XCTAssertEqual(configuration.batchLimit, 32)
        XCTAssertEqual(configuration.flowLimit, 128)
    }

    func testConfigurationExposesRoutingRuleManifest() {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct)]
        )
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )
        let configuration = TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: RoutingEngine(rules: [.final(.reject)]),
            batchLimit: 32,
            flowLimit: 128
        )

        XCTAssertEqual(configuration.routingRuleManifest, manifest)
    }

    func testConfigurationBuildsRoutingEngineFromSnapshotManifest() throws {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        )
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )
        let configuration = try TunnelRuntimeConfiguration(snapshot: snapshot, batchLimit: 32, flowLimit: 128)

        let decision = configuration.routingEngine.resolve(RoutingContext(host: "developer.apple.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }

    func testConfigurationBuiltFromEmptyManifestUsesRejectDefault() throws {
        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: makeNode(),
            routeMode: .ruleBased,
            logLevel: .user
        )
        let configuration = try TunnelRuntimeConfiguration(snapshot: snapshot, batchLimit: 32, flowLimit: 128)

        let decision = configuration.routingEngine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .reject)
        XCTAssertNil(decision.matchedRule)
    }

    func testDirectUDPDatagramForwarderSendsPayloadToPacketDestination() async throws {
        let client = RecordingUDPDatagramClient(responsePayload: [0xde, 0xad])
        let forwarder = DirectUDPDatagramForwarder(client: client)
        let parsed = try PacketParser().parse(Packet.ipv4UDP(
            id: "udp-direct",
            source: .v4(10, 0, 0, 2),
            destination: .v4(1, 1, 1, 1),
            sourcePort: 55_555,
            destinationPort: 53,
            payload: [0x01, 0x02]
        ))
        let request = UDPDatagramForwardingRequest(
            mode: .direct,
            node: makeNode(),
            flowKey: FlowKey(parsed),
            parsedPacket: parsed,
            payload: parsed.udpPayload
        )

        let response = try await forwarder.forward(request)

        XCTAssertEqual(response, [0xde, 0xad])
        XCTAssertEqual(client.requests, [UDPDatagramClientRequest(flowKey: FlowKey(parsed), destination: .ipv4("1.1.1.1", port: 53), payload: [0x01, 0x02])])
    }

    func testProtocolUDPDatagramForwarderEncapsulatesShadowsocksProxyDatagram() async throws {
        let responsePacket = try ShadowsocksUDPDatagramRequest(
            credential: "aes-256-gcm:pass",
            destination: .ipv4("1.1.1.1", port: 53),
            payload: Data([0xde, 0xad]),
            salt: Data(repeating: 9, count: 32)
        ).packet
        let client = RecordingUDPDatagramClient(responsePayload: Array(responsePacket))
        let registry = RuntimeProxyStack.shadowsocksTCP(
            plain: UnsupportedTransportAdapter(transport: .tcp),
            tls: UnsupportedTransportAdapter(transport: .tcp),
            credentialResolver: TestShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let forwarder = ProtocolUDPDatagramForwarder(client: client, proxyAdapterRegistry: registry)
        let parsed = try PacketParser().parse(Packet.ipv4UDP(
            id: "udp-proxy-ss",
            source: .v4(10, 0, 0, 2),
            destination: .v4(1, 1, 1, 1),
            sourcePort: 55_555,
            destinationPort: 53,
            payload: [0x01, 0x02]
        ))
        let request = UDPDatagramForwardingRequest(
            mode: .proxy,
            node: makeNode(protocolType: .shadowsocks, udpPolicy: .enabled),
            flowKey: FlowKey(parsed),
            parsedPacket: parsed,
            payload: parsed.udpPayload
        )

        let response = try await forwarder.forward(request)

        XCTAssertEqual(response, [0xde, 0xad])
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests.first?.destination, .host("example.com", port: 443))
        XCTAssertEqual(try ShadowsocksUDPDatagramRequest.decryptPayload(Data(try XCTUnwrap(client.requests.first?.payload)), credential: "aes-256-gcm:pass"), Data([0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x35, 0x01, 0x02]))
    }

    private func makeNode(protocolType: ProxyProtocolType = .trojan, transport: TransportType = .tcp, udpPolicy: UDPPolicy = .disabled) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo",
            protocolType: protocolType,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: transport,
            tls: .disabled,
            udpPolicy: udpPolicy
        )
    }
}

private final class RecordingUDPDatagramClient: UDPDatagramClient, @unchecked Sendable {
    private let responsePayload: [UInt8]
    private let queue = DispatchQueue(label: "RecordingUDPDatagramClient")
    private var requestValues: [UDPDatagramClientRequest] = []

    var requests: [UDPDatagramClientRequest] {
        queue.sync { requestValues }
    }

    init(responsePayload: [UInt8]) {
        self.responsePayload = responsePayload
    }

    func send(_ request: UDPDatagramClientRequest) async throws -> [UInt8]? {
        queue.sync { requestValues.append(request) }
        return responsePayload
    }
}
