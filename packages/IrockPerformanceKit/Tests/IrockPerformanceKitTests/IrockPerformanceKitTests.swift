import Dispatch
import XCTest
import IrockRouting
@testable import IrockPerformanceKit

final class IrockPerformanceKitTests: XCTestCase {
    func testPerformanceBudgetStoresAlphaTargets() {
        let budget = PerformanceBudget.alphaFlagship

        XCTAssertEqual(budget.minimumThroughputMbps, 600)
        XCTAssertEqual(budget.maximumAddedLatencyMs, 10)
        XCTAssertEqual(budget.maximumTunnelMemoryMB, 50)
    }

    func testRoutingLookupPerformanceBudgetRecordsHotPathEvidence() {
        let rules = (0..<128).flatMap { index in
            [
                RoutingRule.domain("exact-\(index).example.com", .direct),
                RoutingRule.domainSuffix("suffix-\(index).example.com", .proxy),
                RoutingRule.domainKeyword("keyword-\(index)", .reject),
                RoutingRule.ipCIDR("10.\(index).0.0/16", .direct)
            ]
        } + [.final(.proxy)]
        let engine = RoutingEngine(rules: rules)
        let contexts = (0..<512).map { index in
            RoutingContext(host: "api.suffix-\(index % 128).example.com", ipAddress: "10.\(index % 128).1.\(index % 255)", port: 443)
        }

        let start = DispatchTime.now().uptimeNanoseconds
        for context in contexts {
            _ = engine.resolve(context)
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let averageLookupNanoseconds = elapsed / UInt64(contexts.count)

        XCTAssertLessThan(averageLookupNanoseconds, 1_000_000)
    }
}
