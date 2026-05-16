import Dispatch
import IrockCore
import IrockRouting

public enum PacketDropReason: Equatable, Sendable {
    case parseFailed(PacketParseError)
    case unsupportedProtocol
    case flowLimitExceeded
    case noRoute
}

public enum PacketAction: Equatable, Sendable {
    case direct(FlowKey)
    case proxy(FlowKey)
    case reject(FlowKey)
    case drop(PacketDropReason)
}

public enum UDPForwardingDecision: Equatable, Sendable {
    case direct(FlowKey)
    case proxy(FlowKey)
    case unsupported(FlowKey)
    case reject(FlowKey)
    case drop(PacketDropReason)
}

public struct PacketProcessingResult: Equatable, Sendable {
    public let packet: Packet
    public let parsedPacket: ParsedPacket?
    public let flowKey: FlowKey?
    public let action: PacketAction
    public let responsePacketBytes: [UInt8]?

    public init(packet: Packet, parsedPacket: ParsedPacket?, flowKey: FlowKey?, action: PacketAction, responsePacketBytes: [UInt8]? = nil) {
        self.packet = packet
        self.parsedPacket = parsedPacket
        self.flowKey = flowKey
        self.action = action
        self.responsePacketBytes = responsePacketBytes
    }

    public func withResponsePacketBytes(_ bytes: [UInt8]?) -> PacketProcessingResult {
        PacketProcessingResult(packet: packet, parsedPacket: parsedPacket, flowKey: flowKey, action: action, responsePacketBytes: bytes)
    }

    public func udpForwardingDecision(udpPolicy: UDPPolicy) -> UDPForwardingDecision? {
        switch action {
        case let .direct(flowKey) where parsedPacket?.transportProtocol == .udp:
            return .direct(flowKey)
        case let .proxy(flowKey) where parsedPacket?.transportProtocol == .udp:
            return udpPolicy == .enabled ? .proxy(flowKey) : .unsupported(flowKey)
        case let .reject(flowKey) where parsedPacket?.transportProtocol == .udp:
            return .reject(flowKey)
        case let .drop(reason) where parsedPacket == nil:
            return .drop(reason)
        default:
            return nil
        }
    }
}

public struct PacketProcessingPerformanceEvidence: Equatable, Sendable {
    public let packetCount: Int
    public let dropCount: Int
    public let elapsedNanoseconds: UInt64

    public var averageNanosecondsPerPacket: UInt64 {
        guard packetCount > 0 else { return 0 }
        return elapsedNanoseconds / UInt64(packetCount)
    }

    public var packetsPerSecond: UInt64 {
        guard elapsedNanoseconds > 0 else { return UInt64(packetCount) }
        return UInt64(packetCount) * 1_000_000_000 / elapsedNanoseconds
    }

    public init(packetCount: Int, dropCount: Int, elapsedNanoseconds: UInt64) {
        self.packetCount = packetCount
        self.dropCount = dropCount
        self.elapsedNanoseconds = elapsedNanoseconds
    }

    public static func measure(packets: [Packet], configuration: TunnelRuntimeConfiguration) -> PacketProcessingPerformanceEvidence {
        var processor = PacketProcessor(configuration: configuration)
        let start = DispatchTime.now().uptimeNanoseconds
        let results = processor.process(packets)
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let dropCount = results.filter { result in
            if case .drop = result.action {
                return true
            }
            return false
        }.count
        return PacketProcessingPerformanceEvidence(packetCount: results.count, dropCount: dropCount, elapsedNanoseconds: elapsed)
    }
}

public struct PacketProcessor: Sendable {
    private let configuration: TunnelRuntimeConfiguration
    private let parser: PacketParser
    private var flowTable: FlowTable

    public init(configuration: TunnelRuntimeConfiguration, parser: PacketParser = PacketParser()) {
        self.configuration = configuration
        self.parser = parser
        self.flowTable = FlowTable(capacity: configuration.flowLimit)
    }

    public mutating func process(_ packet: Packet) -> PacketProcessingResult {
        let parsed: ParsedPacket
        do {
            parsed = try parser.parse(packet)
        } catch PacketParseError.unsupportedTransportProtocol {
            return PacketProcessingResult(packet: packet, parsedPacket: nil, flowKey: nil, action: .drop(.unsupportedProtocol))
        } catch let error as PacketParseError {
            return PacketProcessingResult(packet: packet, parsedPacket: nil, flowKey: nil, action: .drop(.parseFailed(error)))
        } catch {
            return PacketProcessingResult(packet: packet, parsedPacket: nil, flowKey: nil, action: .drop(.noRoute))
        }

        let record = flowTable.record(parsed)
        let key = record.key
        return PacketProcessingResult(packet: packet, parsedPacket: parsed, flowKey: key, action: action(for: parsed, key: key))
    }

    public mutating func process(_ packets: [Packet]) -> [PacketProcessingResult] {
        packets.prefix(configuration.batchLimit).map { process($0) }
    }

    private func action(for packet: ParsedPacket, key: FlowKey) -> PacketAction {
        switch configuration.routeMode {
        case .globalProxy:
            return .proxy(key)
        case .direct:
            return .direct(key)
        case .ruleBased:
            let decision = configuration.routingEngine.resolve(RoutingContext(host: nil, ipAddress: packet.destinationIP.stringValue, port: packet.destinationPort))
            switch decision.action {
            case .direct:
                return .direct(key)
            case .proxy:
                return .proxy(key)
            case .reject:
                return .reject(key)
            }
        }
    }
}
