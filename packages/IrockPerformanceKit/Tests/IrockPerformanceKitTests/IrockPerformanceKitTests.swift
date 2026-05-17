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

    func testPerformanceBudgetAssessmentReportsPassAndFailures() {
        let passing = PerformanceMeasurement(
            throughputMbps: 750,
            addedLatencyMs: 6,
            tunnelMemoryMB: 42
        )
        let failing = PerformanceMeasurement(
            throughputMbps: 120,
            addedLatencyMs: 18,
            tunnelMemoryMB: 64
        )

        let passingAssessment = PerformanceBudget.alphaFlagship.assess(passing)
        let failingAssessment = PerformanceBudget.alphaFlagship.assess(failing)

        XCTAssertTrue(passingAssessment.passed)
        XCTAssertEqual(passingAssessment.failures, [])
        XCTAssertFalse(failingAssessment.passed)
        XCTAssertEqual(failingAssessment.failures, [.throughputBelowMinimum, .latencyAboveMaximum, .memoryAboveMaximum])
    }

    func testRuntimePerformanceEvidenceConvertsPacketTunnelStatsIntoBudgetMeasurement() {
        let evidence = RuntimePerformanceEvidence(
            bytesProcessed: 150_000_000,
            elapsedNanoseconds: 1_000_000_000,
            baselineLatencyMs: 2,
            observedLatencyMs: 7,
            tunnelMemoryMB: 44
        )

        let measurement = PerformanceMeasurement(runtimeEvidence: evidence)
        let assessment = PerformanceBudget.alphaFlagship.assess(runtimeEvidence: evidence)

        XCTAssertEqual(measurement.throughputMbps, 1_200)
        XCTAssertEqual(measurement.addedLatencyMs, 5)
        XCTAssertEqual(measurement.tunnelMemoryMB, 44)
        XCTAssertTrue(assessment.passed)
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
