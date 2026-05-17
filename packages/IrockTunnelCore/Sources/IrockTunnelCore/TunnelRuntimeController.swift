import Foundation
import IrockCore
import IrockProtocols
import IrockStorage
import IrockTransport

public enum TunnelRuntimeControllerError: Error, Equatable, Sendable {
    case missingRuntimeSnapshot
}

public struct TunnelRuntimeController: Sendable {
    public static func makeShadowsocksTCPSession<Flow: PacketFlowIO, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<PacketFlowRuntimeIO<Flow>, PacketFlowRuntimeIO<Flow>> {
        let snapshot = try loadSnapshot(snapshotStore: snapshotStore, statusStore: statusStore, logStore: logStore)
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: batchLimit)
        return try TunnelRuntimeBootstrap.shadowsocksTCP(
            snapshot: snapshot,
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tls,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    public static func runShadowsocksTCPBatch<Flow: PacketFlowIO, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary {
        let runtime = try makeShadowsocksTCPSession(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tls,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        return try await runtime.runOnce()
    }

    public static func makeVMessGRPCSession<Flow: PacketFlowIO, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<PacketFlowRuntimeIO<Flow>, PacketFlowRuntimeIO<Flow>> {
        let snapshot = try loadSnapshot(snapshotStore: snapshotStore, statusStore: statusStore, logStore: logStore)
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: batchLimit)
        return try TunnelRuntimeBootstrap.vmessGRPC(
            snapshot: snapshot,
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tls,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    public static func runVMessGRPCBatch<Flow: PacketFlowIO, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary {
        let runtime = try makeVMessGRPCSession(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            plain: plain,
            tls: tls,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        return try await runtime.runOnce()
    }

    public static func makeVMessGRPCSession<Flow: PacketFlowIO, Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<PacketFlowRuntimeIO<Flow>, PacketFlowRuntimeIO<Flow>> {
        let snapshot = try loadSnapshot(snapshotStore: snapshotStore, statusStore: statusStore, logStore: logStore)
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: batchLimit)
        return try TunnelRuntimeBootstrap.vmessGRPC(
            snapshot: snapshot,
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            stream: stream,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    public static func runVMessGRPCBatch<Flow: PacketFlowIO, Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary {
        let runtime = try makeVMessGRPCSession(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            stream: stream,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        return try await runtime.runOnce()
    }

    public static func makeTrustTunnelHTTP2Session<Flow: PacketFlowIO, Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<PacketFlowRuntimeIO<Flow>, PacketFlowRuntimeIO<Flow>> {
        let snapshot = try loadSnapshot(snapshotStore: snapshotStore, statusStore: statusStore, logStore: logStore)
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: batchLimit)
        return try TunnelRuntimeBootstrap.trustTunnelHTTP2(
            snapshot: snapshot,
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            stream: stream,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    public static func runTrustTunnelHTTP2Batch<Flow: PacketFlowIO, Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary {
        let runtime = try makeTrustTunnelHTTP2Session(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            stream: stream,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        return try await runtime.runOnce()
    }

    public static func makeTUICQUICSession<Flow: PacketFlowIO, SessionDialer: TUICQUICSessionDialer, CredentialResolver: ProxyCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        sessionDialer: SessionDialer,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: (any UDPDatagramForwarder)? = nil,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<PacketFlowRuntimeIO<Flow>, PacketFlowRuntimeIO<Flow>> {
        let snapshot = try loadSnapshot(snapshotStore: snapshotStore, statusStore: statusStore, logStore: logStore)
        let io = PacketFlowRuntimeIO(flow: flow, batchLimit: batchLimit)
        return try TunnelRuntimeBootstrap.tuicQUIC(
            snapshot: snapshot,
            reader: io,
            writer: io,
            statusStore: statusStore,
            logStore: logStore,
            sessionDialer: sessionDialer,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    public static func runTUICQUICBatch<Flow: PacketFlowIO, SessionDialer: TUICQUICSessionDialer, CredentialResolver: ProxyCredentialResolver>(
        snapshotStore: RuntimeSnapshotStore,
        flow: Flow,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        sessionDialer: SessionDialer,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: (any UDPDatagramForwarder)? = nil,
        batchLimit: Int,
        flowLimit: Int
    ) async throws -> PacketTunnelRuntimeSummary {
        let runtime = try makeTUICQUICSession(
            snapshotStore: snapshotStore,
            flow: flow,
            statusStore: statusStore,
            logStore: logStore,
            sessionDialer: sessionDialer,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        return try await runtime.runOnce()
    }

    private static func loadSnapshot(
        snapshotStore: RuntimeSnapshotStore,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore
    ) throws -> RuntimeSnapshot {
        do {
            guard let loadedSnapshot = try snapshotStore.load() else {
                reportMissingSnapshot(statusStore: statusStore, logStore: logStore)
                throw TunnelRuntimeControllerError.missingRuntimeSnapshot
            }
            return loadedSnapshot
        } catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
            throw TunnelRuntimeControllerError.missingRuntimeSnapshot
        } catch {
            let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
            try? reporter.reportRuntimeStoreUnavailable()
            throw error
        }
    }

    private static func reportMissingSnapshot(statusStore: RuntimeStatusStore, logStore: RuntimeLogStore) {
        let message = "Runtime snapshot unavailable"
        try? statusStore.save(RuntimeConnectionStatus(
            phase: .failed,
            selectedNodeID: nil,
            selectedNodeName: nil,
            updatedAt: Date(),
            message: message
        ))
        try? logStore.append(RuntimeLogEntry(
            id: "log-\(UUID().uuidString)",
            timestamp: Date(),
            level: .user,
            message: message,
            nodeID: nil,
            phase: .failed
        ))
    }
}
