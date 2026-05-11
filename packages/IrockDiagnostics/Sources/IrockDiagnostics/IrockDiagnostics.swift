import IrockProtocols
import IrockRouting
import IrockTransport

public enum UserFacingDiagnostic: Equatable, Sendable {
    case protocolFailure(ProxyProtocolError)
    case transportFailure(TransportError)
    case routingFailure(RoutingRuleParseError)
    case runtimeStoreUnavailable
    case runtimeSnapshotUnavailable
    case packetBatchFailed
    case statusLoadFailed
    case logLoadFailed
    case snapshotPublishFailed
}

public enum UserFacingDiagnostics {
    public static func message(for diagnostic: UserFacingDiagnostic) -> String {
        switch diagnostic {
        case let .protocolFailure(error):
            return "Proxy adapter failed: \(error.description)"
        case let .transportFailure(error):
            return "Transport failed: \(error.description)"
        case let .routingFailure(error):
            return message(for: error)
        case .runtimeStoreUnavailable:
            return "Runtime store unavailable"
        case .runtimeSnapshotUnavailable:
            return "Runtime snapshot unavailable"
        case .packetBatchFailed:
            return "Packet batch failed"
        case .statusLoadFailed:
            return "Runtime status unavailable"
        case .logLoadFailed:
            return "Runtime logs unavailable"
        case .snapshotPublishFailed:
            return "Runtime snapshot publish failed"
        }
    }

    private static func message(for error: RoutingRuleParseError) -> String {
        switch error {
        case .emptyInput:
            return "Routing rules invalid: no rules found"
        case let .invalidFieldCount(line, _):
            return "Routing rules invalid at line \(line): invalid field count"
        case let .unsupportedRuleType(line, _):
            return "Routing rules invalid at line \(line): unsupported rule type"
        case let .unsupportedAction(line, _):
            return "Routing rules invalid at line \(line): unsupported action"
        case let .emptyValue(line):
            return "Routing rules invalid at line \(line): empty value"
        case let .invalidCIDR(line, _):
            return "Routing rules invalid at line \(line): invalid CIDR"
        }
    }
}

public struct ConnectionLogEntry: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct RingConnectionLog: Equatable, Sendable {
    public private(set) var entries: [ConnectionLogEntry]
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.entries = []
    }

    public mutating func append(_ entry: ConnectionLogEntry) {
        guard capacity > 0 else { return }
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }
}
