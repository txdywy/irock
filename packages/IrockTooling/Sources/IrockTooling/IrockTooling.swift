import Foundation
import IrockCore
import IrockRouting
import IrockTunnelCore

public enum IrockTooling {}

public struct BenchmarkReport: Equatable, Sendable {
    public let name: String
    public let packetCount: Int
    public let writtenCount: Int
    public let dropCount: Int
    public let elapsedNanoseconds: UInt64
    public let averageNanosecondsPerPacket: UInt64
    public let packetsPerSecond: UInt64
    public let budgetAssessment: PerformanceBudgetAssessment?

    public var renderedSummary: String {
        let budgetSummary = budgetAssessment.map { $0.passed ? "pass" : "fail" } ?? "evidence-incomplete"
        return "\(name) packets=\(packetCount) written=\(writtenCount) dropped=\(dropCount) elapsedNs=\(elapsedNanoseconds) avgNs=\(averageNanosecondsPerPacket) pps=\(packetsPerSecond) budget=\(budgetSummary)"
    }
}

public struct RoutingBenchmarkReport: Equatable, Sendable {
    public let name: String
    public let iterationCount: Int
    public let elapsedNanoseconds: UInt64
    public let averageNanosecondsPerLookup: UInt64
    public let lookupsPerSecond: UInt64

    public var renderedSummary: String {
        "\(name) lookups=\(iterationCount) elapsedNs=\(elapsedNanoseconds) avgNs=\(averageNanosecondsPerLookup) lps=\(lookupsPerSecond)"
    }
}

public struct PacketProcessorBenchmarkReport: Equatable, Sendable {
    public let name: String
    public let packetCount: Int
    public let dropCount: Int
    public let elapsedNanoseconds: UInt64
    public let averageNanosecondsPerPacket: UInt64
    public let packetsPerSecond: UInt64

    public var renderedSummary: String {
        "\(name) packets=\(packetCount) dropped=\(dropCount) elapsedNs=\(elapsedNanoseconds) avgNs=\(averageNanosecondsPerPacket) pps=\(packetsPerSecond)"
    }
}

public enum BenchmarkRunnerError: Error, Equatable, Sendable {
    case invalidPacketCount(Int)
    case invalidIterationCount(Int)
}

public struct BenchmarkRunner: Sendable {
    public init() {}

    public func runPacketProcessor(packetCount: Int = 4_096) throws -> PacketProcessorBenchmarkReport {
        guard packetCount >= 0 else {
            throw BenchmarkRunnerError.invalidPacketCount(packetCount)
        }

        var packets: [Packet] = []
        packets.reserveCapacity(packetCount)
        for index in 0..<packetCount {
            let source = IPAddress.v4(10, 0, UInt8((index / 255) % 255), UInt8(index % 255))
            packets.append(
                Packet.ipv4UDP(
                    id: "packet-processor-benchmark-\(index)",
                    source: source,
                    destination: .v4(1, 1, 1, 1),
                    sourcePort: 50_000 + (index % 1_000),
                    destinationPort: 53,
                    payload: [0x01, 0x02, 0x03, 0x04]
                )
            )
        }
        let evidence = PacketProcessingPerformanceEvidence.measure(
            packets: packets,
            configuration: TunnelRuntimeConfiguration(
                snapshot: benchmarkSnapshot(routeMode: .direct),
                routingEngine: RoutingEngine(rules: [.final(.direct)]),
                batchLimit: packetCount,
                flowLimit: packetCount
            )
        )

        return PacketProcessorBenchmarkReport(
            name: "packet-processor",
            packetCount: evidence.packetCount,
            dropCount: evidence.dropCount,
            elapsedNanoseconds: evidence.elapsedNanoseconds,
            averageNanosecondsPerPacket: evidence.averageNanosecondsPerPacket,
            packetsPerSecond: evidence.packetsPerSecond
        )
    }

    public func runRoutingLookup(iterationCount: Int = 4_096) throws -> RoutingBenchmarkReport {
        guard iterationCount >= 0 else {
            throw BenchmarkRunnerError.invalidIterationCount(iterationCount)
        }

        let rules = (0..<128).flatMap { index in
            [
                RoutingRule.domain("exact-\(index).example.com", .direct),
                RoutingRule.domainSuffix("suffix-\(index).example.com", .proxy),
                RoutingRule.domainKeyword("keyword-\(index)", .reject),
                RoutingRule.ipCIDR("10.\(index).0.0/16", .direct)
            ]
        } + [.final(.proxy)]
        let engine = RoutingEngine(rules: rules)
        let contexts = (0..<iterationCount).map { index in
            RoutingContext(host: "api.suffix-\(index % 128).example.com", ipAddress: "10.\(index % 128).1.\(index % 255)", port: 443)
        }

        let startNanoseconds = DispatchTime.now().uptimeNanoseconds
        for context in contexts {
            _ = engine.resolve(context)
        }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startNanoseconds
        let averageNanosecondsPerLookup = iterationCount > 0 ? elapsedNanoseconds / UInt64(iterationCount) : 0
        let lookupsPerSecond = elapsedNanoseconds > 0 ? UInt64(iterationCount) * 1_000_000_000 / elapsedNanoseconds : UInt64(iterationCount)

        return RoutingBenchmarkReport(
            name: "routing-lookup",
            iterationCount: iterationCount,
            elapsedNanoseconds: elapsedNanoseconds,
            averageNanosecondsPerLookup: averageNanosecondsPerLookup,
            lookupsPerSecond: lookupsPerSecond
        )
    }

    public func runRuntimePacketBatch(packetCount: Int = 4_096) async throws -> BenchmarkReport {
        guard packetCount >= 0 else {
            throw BenchmarkRunnerError.invalidPacketCount(packetCount)
        }

        var packets: [Packet] = []
        packets.reserveCapacity(packetCount)
        for index in 0..<packetCount {
            let source = IPAddress.v4(10, 0, UInt8((index / 255) % 255), UInt8(index % 255))
            packets.append(
                Packet.ipv4TCP(
                    id: "runtime-benchmark-\(index)",
                    source: source,
                    destination: .v4(93, 184, 216, 34),
                    sourcePort: 40_000 + (index % 1_000),
                    destinationPort: 443
                )
            )
        }
        let runtime = PacketTunnelRuntime(
            reader: InMemoryPacketReader(packets: packets),
            writer: InMemoryPacketWriter(),
            configuration: TunnelRuntimeConfiguration(
                snapshot: benchmarkSnapshot(routeMode: .direct),
                routingEngine: RoutingEngine(rules: [.final(.direct)]),
                batchLimit: packetCount,
                flowLimit: packetCount
            )
        )

        let summary = try await runtime.runOnce()
        return BenchmarkReport(
            name: "runtime-packet-batch",
            packetCount: summary.performanceEvidence.packetCount,
            writtenCount: summary.performanceEvidence.writtenCount,
            dropCount: summary.performanceEvidence.dropCount,
            elapsedNanoseconds: summary.performanceEvidence.elapsedNanoseconds,
            averageNanosecondsPerPacket: summary.performanceEvidence.averageNanosecondsPerPacket,
            packetsPerSecond: summary.performanceEvidence.packetsPerSecond,
            budgetAssessment: nil
        )
    }

    private func benchmarkSnapshot(routeMode: RouteMode) -> RuntimeSnapshot {
        RuntimeSnapshot(
            id: SnapshotID(rawValue: "benchmark-snapshot"),
            selectedNode: ProxyNode(
                id: NodeID(rawValue: "benchmark-node"),
                name: "Benchmark",
                protocolType: .trojan,
                serverHost: "example.com",
                serverPort: 443,
                credentialReference: CredentialReference(keychainService: "com.irock.benchmark", account: "benchmark-node"),
                transport: .tcp,
                tls: .disabled,
                udpPolicy: .disabled
            ),
            routeMode: routeMode,
            logLevel: .user
        )
    }
}
