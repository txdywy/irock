import XCTest
import IrockCore
import IrockRouting
@testable import IrockAppFeature

final class RoutingRuleManifestBuilderTests: XCTestCase {
    func testBuilderConvertsLocalRuleTextToRuntimeManifest() throws {
        let manifest = try RoutingRuleManifestBuilder.buildManifest(from: """
        DOMAIN,example.com,DIRECT
        DOMAIN-SUFFIX,apple.com,PROXY
        DOMAIN-KEYWORD,google,REJECT
        IP-CIDR,10.0.0.0/8,DIRECT
        FINAL,PROXY
        """)

        XCTAssertEqual(manifest, RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domain, value: "example.com", action: .direct),
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .proxy),
                RuntimeRoutingRule(kind: .domainKeyword, value: "google", action: .reject),
                RuntimeRoutingRule(kind: .ipCIDR, value: "10.0.0.0/8", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        ))
    }

    func testBuilderReturnsEmptyManifestForEmptyOrCommentOnlyText() throws {
        let manifest = try RoutingRuleManifestBuilder.buildManifest(from: "\n# no local rules\n")

        XCTAssertEqual(manifest, .empty)
    }

    func testBuilderPropagatesParserErrors() {
        XCTAssertThrowsError(try RoutingRuleManifestBuilder.buildManifest(from: "DOMAIN,example.com,DROP")) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .unsupportedAction(line: 1, action: "DROP"))
        }
    }
}
