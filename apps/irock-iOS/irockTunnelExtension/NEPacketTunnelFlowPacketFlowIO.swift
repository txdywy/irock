import Foundation
import IrockTunnelCore
import NetworkExtension

struct NEPacketTunnelFlowPacketFlowIO: PacketFlowIO {
    private let packetFlow: NEPacketTunnelFlow

    init(packetFlow: NEPacketTunnelFlow) {
        self.packetFlow = packetFlow
    }

    func readPackets(limit: Int) async throws -> [Packet] {
        let packets = await packetFlow.readPacketObjects()
        return packets.prefix(max(0, limit)).enumerated().map { index, packet in
            Packet(id: "ne-packet-\(index)", bytes: Array(packet.data))
        }
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        let packets = results.compactMap { result -> NEPacket? in
            switch result.action {
            case .direct, .proxy:
                return NEPacket(data: Data(result.packet.bytes), protocolFamily: AF_INET as NSNumber)
            case .reject, .drop:
                return nil
            }
        }
        guard !packets.isEmpty else { return }
        await packetFlow.writePacketObjects(packets)
    }
}
