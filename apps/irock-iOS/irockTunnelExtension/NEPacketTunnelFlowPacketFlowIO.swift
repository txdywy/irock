import Foundation
import IrockTunnelCore
import NetworkExtension

private final class CancellationResumeGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var value: Value?
    private var didResume = false

    func setContinuation(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock()
        if didResume {
            let value = self.value
            lock.unlock()
            continuation.resume(returning: value!)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with value: Value) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        self.value = value
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

struct NEPacketTunnelFlowPacketFlowIO: PacketFlowIO {
    private let packetFlow: NEPacketTunnelFlow

    init(packetFlow: NEPacketTunnelFlow) {
        self.packetFlow = packetFlow
    }

    func readPackets(limit: Int) async throws -> [Packet] {
        guard !Task.isCancelled else { return [] }
        let packets = await readPacketObjects()
        guard !Task.isCancelled else { return [] }
        return packets.prefix(max(0, limit)).enumerated().map { index, packet in
            Packet(id: "ne-packet-\(index)", bytes: Array(packet.data))
        }
    }

    private func readPacketObjects() async -> [NEPacket] {
        let gate = CancellationResumeGate<[NEPacket]>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.setContinuation(continuation)
                packetFlow.readPacketObjects { packets in
                    gate.resume(with: packets)
                }
            }
        } onCancel: {
            gate.resume(with: [])
        }
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        let packets = results.compactMap { result -> NEPacket? in
            guard let responsePacketBytes = result.responsePacketBytes, !responsePacketBytes.isEmpty else {
                return nil
            }
            guard let family = protocolFamily(for: responsePacketBytes) else {
                return nil
            }
            return NEPacket(data: Data(responsePacketBytes), protocolFamily: family)
        }
        guard !packets.isEmpty else { return }
        await packetFlow.writePacketObjects(packets)
    }

    private func protocolFamily(for packetBytes: [UInt8]) -> sa_family_t? {
        guard let firstByte = packetBytes.first else { return nil }
        switch firstByte >> 4 {
        case 4:
            return sa_family_t(AF_INET)
        case 6:
            return sa_family_t(AF_INET6)
        default:
            return nil
        }
    }
}
