public struct RuntimePerformanceEvidence: Equatable, Sendable {
    public let bytesProcessed: Int
    public let elapsedNanoseconds: UInt64
    public let baselineLatencyMs: Int
    public let observedLatencyMs: Int
    public let tunnelMemoryMB: Int

    public init(bytesProcessed: Int, elapsedNanoseconds: UInt64, baselineLatencyMs: Int, observedLatencyMs: Int, tunnelMemoryMB: Int) {
        self.bytesProcessed = bytesProcessed
        self.elapsedNanoseconds = elapsedNanoseconds
        self.baselineLatencyMs = baselineLatencyMs
        self.observedLatencyMs = observedLatencyMs
        self.tunnelMemoryMB = tunnelMemoryMB
    }
}

public struct PerformanceMeasurement: Equatable, Sendable {
    public let throughputMbps: Int
    public let addedLatencyMs: Int
    public let tunnelMemoryMB: Int

    public init(throughputMbps: Int, addedLatencyMs: Int, tunnelMemoryMB: Int) {
        self.throughputMbps = throughputMbps
        self.addedLatencyMs = addedLatencyMs
        self.tunnelMemoryMB = tunnelMemoryMB
    }

    public init(runtimeEvidence: RuntimePerformanceEvidence) {
        let bitsProcessed = runtimeEvidence.bytesProcessed * 8
        let throughputMbps = runtimeEvidence.elapsedNanoseconds == 0 ? bitsProcessed / 1_000_000 : Int(UInt64(bitsProcessed) * 1_000 / runtimeEvidence.elapsedNanoseconds)
        self.init(
            throughputMbps: throughputMbps,
            addedLatencyMs: max(0, runtimeEvidence.observedLatencyMs - runtimeEvidence.baselineLatencyMs),
            tunnelMemoryMB: runtimeEvidence.tunnelMemoryMB
        )
    }
}

public enum PerformanceBudgetFailure: Equatable, Sendable {
    case throughputBelowMinimum
    case latencyAboveMaximum
    case memoryAboveMaximum
}

public struct PerformanceBudgetAssessment: Equatable, Sendable {
    public let measurement: PerformanceMeasurement
    public let budget: PerformanceBudget
    public let failures: [PerformanceBudgetFailure]

    public var passed: Bool { failures.isEmpty }

    public init(measurement: PerformanceMeasurement, budget: PerformanceBudget, failures: [PerformanceBudgetFailure]) {
        self.measurement = measurement
        self.budget = budget
        self.failures = failures
    }
}

public struct PerformanceBudget: Equatable, Sendable {
    public let minimumThroughputMbps: Int
    public let maximumAddedLatencyMs: Int
    public let maximumTunnelMemoryMB: Int

    public static let alphaFlagship = PerformanceBudget(
        minimumThroughputMbps: 600,
        maximumAddedLatencyMs: 10,
        maximumTunnelMemoryMB: 50
    )

    public init(minimumThroughputMbps: Int, maximumAddedLatencyMs: Int, maximumTunnelMemoryMB: Int) {
        self.minimumThroughputMbps = minimumThroughputMbps
        self.maximumAddedLatencyMs = maximumAddedLatencyMs
        self.maximumTunnelMemoryMB = maximumTunnelMemoryMB
    }

    public func assess(_ measurement: PerformanceMeasurement) -> PerformanceBudgetAssessment {
        var failures: [PerformanceBudgetFailure] = []
        if measurement.throughputMbps < minimumThroughputMbps {
            failures.append(.throughputBelowMinimum)
        }
        if measurement.addedLatencyMs > maximumAddedLatencyMs {
            failures.append(.latencyAboveMaximum)
        }
        if measurement.tunnelMemoryMB > maximumTunnelMemoryMB {
            failures.append(.memoryAboveMaximum)
        }
        return PerformanceBudgetAssessment(measurement: measurement, budget: self, failures: failures)
    }

    public func assess(runtimeEvidence: RuntimePerformanceEvidence) -> PerformanceBudgetAssessment {
        assess(PerformanceMeasurement(runtimeEvidence: runtimeEvidence))
    }
}
