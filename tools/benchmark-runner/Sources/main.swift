import Foundation
import IrockTooling

@main
struct BenchmarkRunnerCommand {
    static func main() async throws {
        let benchmarkName = CommandLine.arguments.dropFirst().first ?? "runtime-packet-batch"
        switch benchmarkName {
        case "runtime-packet-batch":
            let report = try await BenchmarkRunner().runRuntimePacketBatch()
            print(report.renderedSummary)
        case "routing-lookup":
            let report = try BenchmarkRunner().runRoutingLookup()
            print(report.renderedSummary)
        case "packet-processor":
            let report = try BenchmarkRunner().runPacketProcessor()
            print(report.renderedSummary)
        default:
            throw BenchmarkRunnerCommandError.unsupportedBenchmark(benchmarkName)
        }
    }
}

enum BenchmarkRunnerCommandError: Error, CustomStringConvertible {
    case unsupportedBenchmark(String)

    var description: String {
        switch self {
        case let .unsupportedBenchmark(name):
            return "Unsupported benchmark: \(name)"
        }
    }
}
