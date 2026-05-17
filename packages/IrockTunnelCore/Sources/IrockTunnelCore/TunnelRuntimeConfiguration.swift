import Foundation
import IrockCore
import IrockProtocols
import IrockRouting

public enum UDPDatagramForwardingMode: Equatable, Sendable {
    case direct
    case proxy
}

public struct UDPDatagramForwardingRequest: Equatable, Sendable {
    public let mode: UDPDatagramForwardingMode
    public let node: ProxyNode
    public let flowKey: FlowKey
    public let parsedPacket: ParsedPacket
    public let payload: [UInt8]

    public init(mode: UDPDatagramForwardingMode, node: ProxyNode, flowKey: FlowKey, parsedPacket: ParsedPacket, payload: [UInt8]) {
        self.mode = mode
        self.node = node
        self.flowKey = flowKey
        self.parsedPacket = parsedPacket
        self.payload = payload
    }
}

public struct UDPDatagramClientRequest: Equatable, Sendable {
    public let flowKey: FlowKey
    public let destination: ProxyDestination
    public let payload: [UInt8]

    public init(flowKey: FlowKey, destination: ProxyDestination, payload: [UInt8]) {
        self.flowKey = flowKey
        self.destination = destination
        self.payload = payload
    }
}

public protocol UDPDatagramClient: Sendable {
    func send(_ request: UDPDatagramClientRequest) async throws -> [UInt8]?
}

public protocol UDPDatagramForwarder: Sendable {
    func forward(_ request: UDPDatagramForwardingRequest) async throws -> [UInt8]?
}

public struct DirectUDPDatagramForwarder<Client: UDPDatagramClient>: UDPDatagramForwarder {
    private let client: Client

    public init(client: Client) {
        self.client = client
    }

    public func forward(_ request: UDPDatagramForwardingRequest) async throws -> [UInt8]? {
        guard request.mode == .direct else { return nil }
        return try await client.send(UDPDatagramClientRequest(flowKey: request.flowKey, destination: destination(for: request.parsedPacket), payload: request.payload))
    }

    private func destination(for packet: ParsedPacket) -> ProxyDestination {
        switch packet.destinationIP {
        case .v4:
            return .ipv4(packet.destinationIP.stringValue, port: packet.destinationPort)
        case .v6:
            return .ipv6(packet.destinationIP.stringValue, port: packet.destinationPort)
        }
    }
}

public struct ProtocolUDPDatagramForwarder<Client: UDPDatagramClient>: UDPDatagramForwarder {
    private let client: Client
    private let proxyAdapterRegistry: ProxyAdapterRegistry

    public init(client: Client, proxyAdapterRegistry: ProxyAdapterRegistry) {
        self.client = client
        self.proxyAdapterRegistry = proxyAdapterRegistry
    }

    public func forward(_ request: UDPDatagramForwardingRequest) async throws -> [UInt8]? {
        switch request.mode {
        case .direct:
            return try await client.send(UDPDatagramClientRequest(flowKey: request.flowKey, destination: destination(for: request.parsedPacket), payload: request.payload))
        case .proxy:
            let adapter = proxyAdapterRegistry.adapter(for: request.node.protocolType)
            let proxyRequest = ProxyUDPDatagramRequest(node: request.node, destination: destination(for: request.parsedPacket), payload: Data(request.payload))
            let encoded = try adapter.encodeUDPDatagram(request: proxyRequest)
            guard let response = try await client.send(UDPDatagramClientRequest(flowKey: request.flowKey, destination: encoded.server, payload: Array(encoded.payload))) else { return nil }
            return try adapter.decodeUDPDatagramResponse(Data(response), request: proxyRequest)?.payload.map { $0 }
        }
    }

    private func destination(for packet: ParsedPacket) -> ProxyDestination {
        switch packet.destinationIP {
        case .v4:
            return .ipv4(packet.destinationIP.stringValue, port: packet.destinationPort)
        case .v6:
            return .ipv6(packet.destinationIP.stringValue, port: packet.destinationPort)
        }
    }
}

public struct TUICQUICUDPDatagramForwarder<SessionDialer: TUICQUICSessionDialer, CredentialResolver: ProxyCredentialResolver>: UDPDatagramForwarder {
    private let sessionDialer: SessionDialer
    private let credentialResolver: CredentialResolver
    private let state = TUICQUICUDPForwarderState()

    public init(sessionDialer: SessionDialer, credentialResolver: CredentialResolver) {
        self.sessionDialer = sessionDialer
        self.credentialResolver = credentialResolver
    }

    public func forward(_ request: UDPDatagramForwardingRequest) async throws -> [UInt8]? {
        guard request.mode == .proxy else { return nil }
        guard request.node.protocolType == .tuic else { return nil }
        let credential = try credentialResolver.credential(for: request.node.credentialReference)
        let associationID = await state.associationID(for: request.flowKey)
        let packetID = await state.nextPacketID(for: request.flowKey)
        let destination = destination(for: request.parsedPacket)
        let command = try TUICPacketCommand(associationID: associationID, packetID: packetID, destination: destination, payload: Data(request.payload))
        let session = try await authenticatedSession(for: request, credential: credential, associationID: associationID, packetID: packetID)
        guard let response = try await session.sendDatagram(command.bytes) else { return nil }
        let responseCommand = try TUICPacketCommand.parse(response)
        guard responseCommand.associationID == associationID else {
            throw ProxyProtocolError.invalidConfiguration("tuic udp response association mismatch")
        }
        return responseCommand.payload.map { $0 }
    }

    private func authenticatedSession(for request: UDPDatagramForwardingRequest, credential: String, associationID: UInt16, packetID: UInt16) async throws -> any TUICQUICSession {
        if let session = await state.session(for: request.flowKey) {
            return session
        }
        let session = try await TUICSessionAuthenticator(sessionDialer: sessionDialer).openAuthenticatedSession(
            node: request.node,
            credential: credential,
            metadata: [
                "tuicUDPRelay": "quic",
                "tuicAssociationID": "\(associationID)",
                "tuicPacketID": "\(packetID)"
            ]
        )
        await state.setSession(session, for: request.flowKey)
        return session
    }

    private func destination(for packet: ParsedPacket) -> ProxyDestination {
        switch packet.destinationIP {
        case .v4:
            return .ipv4(packet.destinationIP.stringValue, port: packet.destinationPort)
        case .v6:
            return .ipv6(packet.destinationIP.stringValue, port: packet.destinationPort)
        }
    }
}

private actor TUICQUICUDPForwarderState {
    private var sessions: [FlowKey: any TUICQUICSession] = [:]
    private var associationIDs: [FlowKey: UInt16] = [:]
    private var packetIDs: [FlowKey: UInt16] = [:]
    private var nextAssociationID: UInt16 = 1

    func session(for flowKey: FlowKey) -> (any TUICQUICSession)? {
        sessions[flowKey]
    }

    func setSession(_ session: any TUICQUICSession, for flowKey: FlowKey) {
        sessions[flowKey] = session
    }

    func associationID(for flowKey: FlowKey) -> UInt16 {
        if let associationID = associationIDs[flowKey] {
            return associationID
        }
        let associationID = nextAssociationID
        associationIDs[flowKey] = associationID
        nextAssociationID = nextAssociationID == UInt16.max ? 1 : nextAssociationID + 1
        return associationID
    }

    func nextPacketID(for flowKey: FlowKey) -> UInt16 {
        let packetID = packetIDs[flowKey, default: 1]
        packetIDs[flowKey] = packetID == UInt16.max ? 1 : packetID + 1
        return packetID
    }
}

public struct NoopUDPDatagramForwarder: UDPDatagramForwarder {
    public init() {}

    public func forward(_ request: UDPDatagramForwardingRequest) async throws -> [UInt8]? {
        nil
    }
}

public struct TunnelRuntimeConfiguration: Sendable {
    public let snapshot: RuntimeSnapshot
    public let routingEngine: RoutingEngine
    public let proxyAdapterRegistry: ProxyAdapterRegistry
    public let udpDatagramForwarder: any UDPDatagramForwarder
    public let batchLimit: Int
    public let flowLimit: Int

    public var routeMode: RouteMode {
        snapshot.routeMode
    }

    public var routingRuleManifest: RuntimeRoutingRuleManifest {
        snapshot.routingRuleManifest
    }

    public init(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        proxyAdapterRegistry: ProxyAdapterRegistry = ProxyAdapterRegistry(adapters: []),
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) {
        self.snapshot = snapshot
        self.routingEngine = routingEngine
        self.proxyAdapterRegistry = proxyAdapterRegistry
        self.udpDatagramForwarder = udpDatagramForwarder
        self.batchLimit = max(0, batchLimit)
        self.flowLimit = max(0, flowLimit)
    }

    public init(
        snapshot: RuntimeSnapshot,
        proxyAdapterRegistry: ProxyAdapterRegistry = ProxyAdapterRegistry(adapters: []),
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws {
        let rules = try RuntimeRoutingRuleAdapter.routingRules(from: snapshot.routingRuleManifest)
        self.init(
            snapshot: snapshot,
            routingEngine: RoutingEngine(rules: rules),
            proxyAdapterRegistry: proxyAdapterRegistry,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
}
