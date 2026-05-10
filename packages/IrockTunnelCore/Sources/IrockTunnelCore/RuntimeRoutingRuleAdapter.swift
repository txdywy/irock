import IrockCore
import IrockRouting

public enum RuntimeRoutingRuleAdapterError: Error, Equatable, Sendable {
    case missingValue(kind: RuntimeRoutingRuleKind)
}

public enum RuntimeRoutingRuleAdapter {
    public static func routingRules(from manifest: RuntimeRoutingRuleManifest) throws -> [RoutingRule] {
        try manifest.rules.map(routingRule(from:))
    }

    private static func routingRule(from rule: RuntimeRoutingRule) throws -> RoutingRule {
        let action = routingAction(from: rule.action)

        switch rule.kind {
        case .domain:
            return .domain(try requiredValue(from: rule), action)
        case .domainSuffix:
            return .domainSuffix(try requiredValue(from: rule), action)
        case .domainKeyword:
            return .domainKeyword(try requiredValue(from: rule), action)
        case .ipCIDR:
            return .ipCIDR(try requiredValue(from: rule), action)
        case .finalRule:
            return .final(action)
        }
    }

    private static func routingAction(from action: RuntimeRoutingAction) -> RoutingAction {
        switch action {
        case .direct:
            return .direct
        case .proxy:
            return .proxy
        case .reject:
            return .reject
        }
    }

    private static func requiredValue(from rule: RuntimeRoutingRule) throws -> String {
        guard let value = rule.value, !value.isEmpty else {
            throw RuntimeRoutingRuleAdapterError.missingValue(kind: rule.kind)
        }
        return value
    }
}
