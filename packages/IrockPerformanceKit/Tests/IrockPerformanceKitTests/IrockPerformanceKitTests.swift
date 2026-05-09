import XCTest
@testable import IrockPerformanceKit

final class IrockPerformanceKitTests: XCTestCase {
    func testPerformanceBudgetStoresAlphaTargets() {
        let budget = PerformanceBudget.alphaFlagship

        XCTAssertEqual(budget.minimumThroughputMbps, 600)
        XCTAssertEqual(budget.maximumAddedLatencyMs, 10)
        XCTAssertEqual(budget.maximumTunnelMemoryMB, 50)
    }
}
