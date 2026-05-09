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
}
