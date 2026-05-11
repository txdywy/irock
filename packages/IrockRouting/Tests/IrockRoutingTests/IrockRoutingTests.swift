import XCTest
@testable import IrockRouting

final class IrockRoutingTests: XCTestCase {
    func testParserIgnoresBlankLinesAndComments() throws {
        let rules = try RoutingRuleParser.parseLines([
            "",
            "  # Apple services",
            "DOMAIN-SUFFIX,apple.com,DIRECT",
            "FINAL,PROXY"
        ])

        XCTAssertEqual(rules, [
            .domainSuffix("apple.com", .direct),
            .final(.proxy)
        ])
    }

    func testParserParsesSupportedRuleTypes() throws {
        let rules = try RoutingRuleParser.parseLines([
            "DOMAIN,example.com,DIRECT",
            "DOMAIN-SUFFIX,apple.com,DIRECT",
            "DOMAIN-KEYWORD,google,PROXY",
            "IP-CIDR,10.0.0.0/8,DIRECT",
            "FINAL,REJECT"
        ])

        XCTAssertEqual(rules, [
            .domain("example.com", .direct),
            .domainSuffix("apple.com", .direct),
            .domainKeyword("google", .proxy),
            .ipCIDR("10.0.0.0/8", .direct),
            .final(.reject)
        ])
    }

    func testParserRejectsEmptyInput() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["", "# comment"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .emptyInput)
        }
    }

    func testParserRejectsInvalidFieldCount() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["DOMAIN,example.com"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .invalidFieldCount(line: 1, text: "DOMAIN,example.com"))
        }
    }

    func testParserRejectsUnsupportedRuleType() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["GEOIP,CN,DIRECT"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .unsupportedRuleType(line: 1, type: "GEOIP"))
        }
    }

    func testParserRejectsUnsupportedAction() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["DOMAIN,example.com,DROP"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .unsupportedAction(line: 1, action: "DROP"))
        }
    }

    func testParserRejectsEmptyValue() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["DOMAIN, ,DIRECT"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .emptyValue(line: 1))
        }
    }

    func testParserRejectsInvalidCIDR() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["IP-CIDR,10.0.0.0/33,DIRECT"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .invalidCIDR(line: 1, value: "10.0.0.0/33"))
        }
    }

    func testRoutingParserRejectsMalformedFieldCountsAndEmptyValues() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["FINAL,"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .unsupportedAction(line: 1, action: ""))
        }
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["FINAL,PROXY,extra"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .invalidFieldCount(line: 1, text: "FINAL,PROXY,extra"))
        }
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["DOMAIN,example.com,DIRECT,extra"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .invalidFieldCount(line: 1, text: "DOMAIN,example.com,DIRECT,extra"))
        }
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["DOMAIN, ,DIRECT"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .emptyValue(line: 1))
        }
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["IP-CIDR,10.0.0.0/33,DIRECT"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .invalidCIDR(line: 1, value: "10.0.0.0/33"))
        }
    }

    func testRoutingParserAcceptsCaseInsensitiveTypesAndActions() throws {
        let rules = try RoutingRuleParser.parseLines([
            "domain,Example.Com,direct",
            "domain-suffix,Apple.Com,Proxy",
            "domain-keyword,Maps,Reject",
            "ip-cidr,10.0.0.0/8,Direct",
            "final,proxy"
        ])

        XCTAssertEqual(rules, [
            .domain("Example.Com", .direct),
            .domainSuffix("Apple.Com", .proxy),
            .domainKeyword("Maps", .reject),
            .ipCIDR("10.0.0.0/8", .direct),
            .final(.proxy)
        ])
    }

    func testFinalRuleReturnsProxyDecision() {
        let engine = RoutingEngine(rules: [.final(.proxy)])
        let decision = engine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .proxy)
        XCTAssertEqual(decision.matchedRule, .final(.proxy))
    }

    func testDomainRuleMatchesExactHostOnly() {
        let engine = RoutingEngine(rules: [.domain("example.com", .direct), .final(.proxy)])

        let exact = engine.resolve(RoutingContext(host: "Example.Com.", ipAddress: nil, port: 443))
        let subdomain = engine.resolve(RoutingContext(host: "www.example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(exact.action, .direct)
        XCTAssertEqual(exact.matchedRule, .domain("example.com", .direct))
        XCTAssertEqual(subdomain.action, .proxy)
        XCTAssertEqual(subdomain.matchedRule, .final(.proxy))
    }

    func testDomainSuffixRuleBeatsFinalRule() {
        let engine = RoutingEngine(rules: [.domainSuffix("apple.com", .direct), .final(.proxy)])
        let decision = engine.resolve(RoutingContext(host: "developer.apple.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }

    func testDomainKeywordRuleMatchesNormalizedHost() {
        let engine = RoutingEngine(rules: [.domainKeyword("google", .proxy), .final(.direct)])
        let decision = engine.resolve(RoutingContext(host: "Maps.Googleapis.Com.", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .proxy)
        XCTAssertEqual(decision.matchedRule, .domainKeyword("google", .proxy))
    }

    func testIPCIDRRuleMatchesIPv4Address() {
        let engine = RoutingEngine(rules: [.ipCIDR("10.0.0.0/8", .direct), .final(.proxy)])
        let matched = engine.resolve(RoutingContext(host: nil, ipAddress: "10.42.1.9", port: 443))
        let missed = engine.resolve(RoutingContext(host: nil, ipAddress: "192.168.1.1", port: 443))

        XCTAssertEqual(matched.action, .direct)
        XCTAssertEqual(matched.matchedRule, .ipCIDR("10.0.0.0/8", .direct))
        XCTAssertEqual(missed.action, .proxy)
        XCTAssertEqual(missed.matchedRule, .final(.proxy))
    }

    func testRuleOrderWinsBeforeMoreSpecificLaterRule() {
        let engine = RoutingEngine(rules: [
            .domainSuffix("example.com", .proxy),
            .domain("api.example.com", .direct),
            .final(.reject)
        ])
        let decision = engine.resolve(RoutingContext(host: "api.example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .proxy)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("example.com", .proxy))
    }

    func testNoMatchUsesExplicitDefaultAction() {
        let engine = RoutingEngine(rules: [.domainSuffix("apple.com", .proxy)], defaultAction: .reject)
        let decision = engine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .reject)
        XCTAssertNil(decision.matchedRule)
    }

    func testEngineAcceptsCompiledRules() throws {
        let rules = try RoutingRuleParser.parseLines([
            "DOMAIN-SUFFIX,apple.com,DIRECT",
            "FINAL,PROXY"
        ])
        let engine = RoutingEngine(compiledRules: try CompiledRoutingRules(rules: rules))
        let decision = engine.resolve(RoutingContext(host: "developer.apple.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }

    func testRoutingCompletenessCoversActionsAcrossRuleKinds() {
        let engine = RoutingEngine(rules: [
            .domain("direct.example.com", .direct),
            .domain("proxy.example.com", .proxy),
            .domain("reject.example.com", .reject),
            .domainSuffix("direct-suffix.test", .direct),
            .domainSuffix("proxy-suffix.test", .proxy),
            .domainSuffix("reject-suffix.test", .reject),
            .domainKeyword("direct-keyword", .direct),
            .domainKeyword("proxy-keyword", .proxy),
            .domainKeyword("reject-keyword", .reject),
            .ipCIDR("10.0.0.0/8", .direct),
            .ipCIDR("172.16.0.0/12", .proxy),
            .ipCIDR("192.168.0.0/16", .reject),
            .final(.proxy)
        ], defaultAction: .reject)

        XCTAssertEqual(engine.resolve(RoutingContext(host: "direct.example.com", ipAddress: nil, port: 443)).action, .direct)
        XCTAssertEqual(engine.resolve(RoutingContext(host: "proxy.example.com", ipAddress: nil, port: 443)).action, .proxy)
        XCTAssertEqual(engine.resolve(RoutingContext(host: "reject.example.com", ipAddress: nil, port: 443)).action, .reject)
        XCTAssertEqual(engine.resolve(RoutingContext(host: "direct-suffix.test", ipAddress: nil, port: 443)).action, .direct)
        XCTAssertEqual(engine.resolve(RoutingContext(host: "api.proxy-suffix.test", ipAddress: nil, port: 443)).action, .proxy)
        XCTAssertEqual(engine.resolve(RoutingContext(host: "api.reject-suffix.test", ipAddress: nil, port: 443)).action, .reject)
        XCTAssertEqual(engine.resolve(RoutingContext(host: "cdn.direct-keyword.test", ipAddress: nil, port: 443)).action, .direct)
        XCTAssertEqual(engine.resolve(RoutingContext(host: "cdn.proxy-keyword.test", ipAddress: nil, port: 443)).action, .proxy)
        XCTAssertEqual(engine.resolve(RoutingContext(host: "cdn.reject-keyword.test", ipAddress: nil, port: 443)).action, .reject)
        XCTAssertEqual(engine.resolve(RoutingContext(host: nil, ipAddress: "10.1.2.3", port: 443)).action, .direct)
        XCTAssertEqual(engine.resolve(RoutingContext(host: nil, ipAddress: "172.16.2.3", port: 443)).action, .proxy)
        XCTAssertEqual(engine.resolve(RoutingContext(host: nil, ipAddress: "192.168.2.3", port: 443)).action, .reject)
        XCTAssertEqual(engine.resolve(RoutingContext(host: "fallback.example", ipAddress: nil, port: 443)).action, .proxy)
    }

    func testRoutingCompletenessCoversCIDRBoundariesAndInvalidIPFallback() {
        let engine = RoutingEngine(rules: [
            .ipCIDR("203.0.113.8/32", .direct),
            .ipCIDR("0.0.0.0/0", .proxy)
        ], defaultAction: .reject)

        XCTAssertEqual(engine.resolve(RoutingContext(host: nil, ipAddress: "203.0.113.8", port: 443)).action, .direct)
        XCTAssertEqual(engine.resolve(RoutingContext(host: nil, ipAddress: "203.0.113.9", port: 443)).action, .proxy)
        XCTAssertEqual(engine.resolve(RoutingContext(host: nil, ipAddress: "198.51.100.1", port: 443)).action, .proxy)
        XCTAssertEqual(engine.resolve(RoutingContext(host: nil, ipAddress: "not-an-ip", port: 443)).action, .reject)
    }

    func testRoutingCompletenessCoversPrecedenceAndFinalTermination() {
        let ordered = RoutingEngine(rules: [
            .domainSuffix("example.com", .reject),
            .domain("api.example.com", .direct),
            .final(.proxy)
        ])
        let finalFirst = RoutingEngine(rules: [
            .final(.direct),
            .domain("blocked.example.com", .reject)
        ])

        let orderedDecision = ordered.resolve(RoutingContext(host: "api.example.com", ipAddress: nil, port: 443))
        let finalDecision = finalFirst.resolve(RoutingContext(host: "blocked.example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(orderedDecision.action, .reject)
        XCTAssertEqual(orderedDecision.matchedRule, .domainSuffix("example.com", .reject))
        XCTAssertEqual(finalDecision.action, .direct)
        XCTAssertEqual(finalDecision.matchedRule, .final(.direct))
    }
}
