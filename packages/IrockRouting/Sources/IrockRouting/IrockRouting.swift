public enum RoutingAction: Equatable, Sendable {
    case direct
    case proxy
    case reject
}

public enum RoutingRule: Equatable, Sendable {
    case domainSuffix(String, RoutingAction)
    case final(RoutingAction)
}

public struct RoutingContext: Equatable, Sendable {
    public let host: String?
    public let ipAddress: String?
    public let port: Int

    public init(host: String?, ipAddress: String?, port: Int) {
        self.host = host
        self.ipAddress = ipAddress
        self.port = port
    }
}

public struct RoutingDecision: Equatable, Sendable {
    public let action: RoutingAction
    public let matchedRule: RoutingRule?

    public init(action: RoutingAction, matchedRule: RoutingRule?) {
        self.action = action
        self.matchedRule = matchedRule
    }
}

public struct RoutingEngine: Sendable {
    private let rules: [RoutingRule]

    public init(rules: [RoutingRule]) {
        self.rules = rules
    }

    public func resolve(_ context: RoutingContext) -> RoutingDecision {
        let normalizedHost = context.host?.lowercased().trimmingSuffix(".")

        for rule in rules {
            switch rule {
            case let .domainSuffix(suffix, action):
                let normalizedSuffix = suffix.lowercased().trimmingSuffix(".")
                if let host = normalizedHost, host == normalizedSuffix || host.hasSuffix("." + normalizedSuffix) {
                    return RoutingDecision(action: action, matchedRule: rule)
                }
            case let .final(action):
                return RoutingDecision(action: action, matchedRule: rule)
            }
        }

        return RoutingDecision(action: .direct, matchedRule: nil)
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
