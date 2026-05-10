import IrockCore
import IrockRouting

public enum RoutingRuleManifestBuilder {
    public static func buildManifest(from text: String) throws -> RuntimeRoutingRuleManifest {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        do {
            let rules = try RoutingRuleParser.parseLines(lines)
            return RuntimeRoutingRuleManifest(version: 1, rules: rules.map(runtimeRule(from:)))
        } catch RoutingRuleParseError.emptyInput {
            return .empty
        }
    }

    private static func runtimeRule(from rule: RoutingRule) -> RuntimeRoutingRule {
        switch rule {
        case let .domain(value, action):
            return RuntimeRoutingRule(kind: .domain, value: value, action: runtimeAction(from: action))
        case let .domainSuffix(value, action):
            return RuntimeRoutingRule(kind: .domainSuffix, value: value, action: runtimeAction(from: action))
        case let .domainKeyword(value, action):
            return RuntimeRoutingRule(kind: .domainKeyword, value: value, action: runtimeAction(from: action))
        case let .ipCIDR(value, action):
            return RuntimeRoutingRule(kind: .ipCIDR, value: value, action: runtimeAction(from: action))
        case let .final(action):
            return RuntimeRoutingRule(kind: .finalRule, value: nil, action: runtimeAction(from: action))
        }
    }

    private static func runtimeAction(from action: RoutingAction) -> RuntimeRoutingAction {
        switch action {
        case .direct:
            return .direct
        case .proxy:
            return .proxy
        case .reject:
            return .reject
        }
    }
}
