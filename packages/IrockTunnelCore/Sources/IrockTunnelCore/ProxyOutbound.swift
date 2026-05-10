import IrockCore
import IrockProtocols

public struct ProxyOutbound: Sendable {
    private let node: ProxyNode
    private let registry: ProxyAdapterRegistry

    public init(node: ProxyNode, registry: ProxyAdapterRegistry) {
        self.node = node
        self.registry = registry
    }

    public func connect(result: PacketProcessingResult) async throws -> (any ProxyConnection)? {
        guard case .proxy = result.action, let parsedPacket = result.parsedPacket else {
            return nil
        }

        if parsedPacket.transportProtocol == .udp && node.udpPolicy == .disabled {
            throw ProxyProtocolError.udpUnsupported
        }

        let request = ProxyRequest(
            node: node,
            destination: destination(for: parsedPacket),
            metadata: [
                "packetID": result.packet.id,
                "transportProtocol": transportProtocolName(parsedPacket.transportProtocol)
            ]
        )
        return try await registry.adapter(for: node.protocolType).connect(request: request)
    }

    private func destination(for packet: ParsedPacket) -> ProxyDestination {
        switch packet.destinationIP {
        case .v4:
            return .ipv4(packet.destinationIP.stringValue, port: packet.destinationPort)
        case .v6:
            return .ipv6(packet.destinationIP.stringValue, port: packet.destinationPort)
        }
    }

    private func transportProtocolName(_ transportProtocol: TransportProtocol) -> String {
        switch transportProtocol {
        case .tcp:
            return "tcp"
        case .udp:
            return "udp"
        }
    }
}
