import XCTest
import IrockCore
import IrockRouting
@testable import IrockTunnelCore

final class RuntimeRoutingRuleAdapterTests: XCTestCase {
    func testAdapterConvertsSupportedRuleKinds() throws {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domain, value: "example.com", action: .direct),
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .proxy),
                RuntimeRoutingRule(kind: .domainKeyword, value: "google", action: .reject),
                RuntimeRoutingRule(kind: .ipCIDR, value: "10.0.0.0/8", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        )

        let rules = try RuntimeRoutingRuleAdapter.routingRules(from: manifest)

        XCTAssertEqual(rules, [
            .domain("example.com", .direct),
            .domainSuffix("apple.com", .proxy),
            .domainKeyword("google", .reject),
            .ipCIDR("10.0.0.0/8", .direct),
            .final(.proxy)
        ])
    }

    func testAdapterRejectsMissingValueForNonFinalRule() {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: nil, action: .direct)]
        )

        XCTAssertThrowsError(try RuntimeRoutingRuleAdapter.routingRules(from: manifest)) { error in
            XCTAssertEqual(error as? RuntimeRoutingRuleAdapterError, .missingValue(kind: .domainSuffix))
        }
    }

    func testAdapterRejectsEmptyValueForNonFinalRule() {
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domain, value: "", action: .direct)]
        )

        XCTAssertThrowsError(try RuntimeRoutingRuleAdapter.routingRules(from: manifest)) { error in
            XCTAssertEqual(error as? RuntimeRoutingRuleAdapterError, .missingValue(kind: .domain))
        }
    }
}
