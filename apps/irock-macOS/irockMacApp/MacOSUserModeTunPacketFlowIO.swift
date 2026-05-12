import Darwin
import Foundation
import IrockTunnelCore

struct MacOSUserModeTunPacketFlowIO: PacketFlowIO {
    private let fileDescriptor: Int32

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    func readPackets(limit: Int) async throws -> [Packet] {
        guard limit > 0, !Task.isCancelled else { return [] }
        var buffer = [UInt8](repeating: 0, count: 65_535)
        let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
        guard count > 4 else { return [] }
        return [Packet(id: "utun-packet-\(UUID().uuidString)", bytes: Array(buffer[4..<count]))]
    }

    func writePackets(_ results: [PacketProcessingResult]) async throws {
        for result in results {
            guard let bytes = result.responsePacketBytes, !bytes.isEmpty else { continue }
            guard let family = protocolFamily(for: bytes) else { continue }
            var packet = family + bytes
            let byteCount = packet.count
            _ = packet.withUnsafeMutableBytes { pointer in
                Darwin.write(fileDescriptor, pointer.baseAddress, byteCount)
            }
        }
    }

    private func protocolFamily(for packetBytes: [UInt8]) -> [UInt8]? {
        guard let firstByte = packetBytes.first else { return nil }
        switch firstByte >> 4 {
        case 4:
            return [0, 0, 0, UInt8(AF_INET)]
        case 6:
            return [0, 0, 0, UInt8(AF_INET6)]
        default:
            return nil
        }
    }
}
