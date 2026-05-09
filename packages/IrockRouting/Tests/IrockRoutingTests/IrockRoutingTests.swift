import XCTest
@testable import IrockRouting

final class IrockRoutingTests: XCTestCase {
    func testFinalRuleReturnsProxyDecision() {
        let engine = RoutingEngine(rules: [.final(.proxy)])
        let decision = engine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .proxy)
        XCTAssertEqual(decision.matchedRule, .final(.proxy))
    }

    func testDomainSuffixRuleBeatsFinalRule() {
        let engine = RoutingEngine(rules: [.domainSuffix("apple.com", .direct), .final(.proxy)])
        let decision = engine.resolve(RoutingContext(host: "developer.apple.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }

    func testDomainSuffixRuleIgnoresCaseAndTrailingDot() {
        let engine = RoutingEngine(rules: [.domainSuffix("apple.com", .direct), .final(.proxy)])
        let decision = engine.resolve(RoutingContext(host: "Developer.Apple.Com.", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }

    func testNoMatchUsesExplicitDefaultAction() {
        let engine = RoutingEngine(rules: [.domainSuffix("apple.com", .proxy)], defaultAction: .reject)
        let decision = engine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .reject)
        XCTAssertNil(decision.matchedRule)
    }
}
