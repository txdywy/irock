import XCTest
@testable import IrockTooling

final class BenchmarkRunnerTests: XCTestCase {
    func testRuntimePacketBatchBenchmarkReportContainsMeasuredEvidence() async throws {
        let runner = BenchmarkRunner()

        let report = try await runner.runRuntimePacketBatch(packetCount: 2_048)

        XCTAssertEqual(report.name, "runtime-packet-batch")
        XCTAssertEqual(report.packetCount, 2_048)
        XCTAssertEqual(report.writtenCount, 2_048)
        XCTAssertEqual(report.dropCount, 0)
        XCTAssertGreaterThan(report.elapsedNanoseconds, 0)
        XCTAssertGreaterThan(report.packetsPerSecond, 1_000)
        XCTAssertLessThan(report.averageNanosecondsPerPacket, 2_000_000)
        XCTAssertTrue(report.renderedSummary.contains("runtime-packet-batch"))
        XCTAssertTrue(report.renderedSummary.contains("packets=2048"))
        XCTAssertTrue(report.renderedSummary.contains("pps="))
    }

    func testRuntimePacketBatchBenchmarkRejectsNegativePacketCount() async {
        let runner = BenchmarkRunner()

        do {
            _ = try await runner.runRuntimePacketBatch(packetCount: -1)
            XCTFail("Expected negative packet count to be rejected")
        } catch let error as BenchmarkRunnerError {
            XCTAssertEqual(error, .invalidPacketCount(-1))
        } catch {
            XCTFail("Expected BenchmarkRunnerError, got \(error)")
        }
    }

    func testRoutingLookupBenchmarkReportContainsMeasuredEvidence() throws {
        let runner = BenchmarkRunner()

        let report = try runner.runRoutingLookup(iterationCount: 1_024)

        XCTAssertEqual(report.name, "routing-lookup")
        XCTAssertEqual(report.iterationCount, 1_024)
        XCTAssertGreaterThan(report.elapsedNanoseconds, 0)
        XCTAssertGreaterThan(report.lookupsPerSecond, 1_000)
        XCTAssertLessThan(report.averageNanosecondsPerLookup, 1_000_000)
        XCTAssertTrue(report.renderedSummary.contains("routing-lookup"))
        XCTAssertTrue(report.renderedSummary.contains("lookups=1024"))
        XCTAssertTrue(report.renderedSummary.contains("lps="))
    }

    func testRoutingLookupBenchmarkRejectsNegativeIterationCount() {
        let runner = BenchmarkRunner()

        XCTAssertThrowsError(try runner.runRoutingLookup(iterationCount: -1)) { error in
            XCTAssertEqual(error as? BenchmarkRunnerError, .invalidIterationCount(-1))
        }
    }

    func testPacketProcessorBenchmarkReportContainsMeasuredEvidence() throws {
        let runner = BenchmarkRunner()

        let report = try runner.runPacketProcessor(packetCount: 4_096)

        XCTAssertEqual(report.name, "packet-processor")
        XCTAssertEqual(report.packetCount, 4_096)
        XCTAssertEqual(report.dropCount, 0)
        XCTAssertGreaterThan(report.elapsedNanoseconds, 0)
        XCTAssertGreaterThan(report.packetsPerSecond, 10_000)
        XCTAssertLessThan(report.averageNanosecondsPerPacket, 1_000_000)
        XCTAssertTrue(report.renderedSummary.contains("packet-processor"))
        XCTAssertTrue(report.renderedSummary.contains("packets=4096"))
        XCTAssertTrue(report.renderedSummary.contains("pps="))
    }

    func testPacketProcessorBenchmarkRejectsNegativePacketCount() {
        let runner = BenchmarkRunner()

        XCTAssertThrowsError(try runner.runPacketProcessor(packetCount: -1)) { error in
            XCTAssertEqual(error as? BenchmarkRunnerError, .invalidPacketCount(-1))
        }
    }
}
