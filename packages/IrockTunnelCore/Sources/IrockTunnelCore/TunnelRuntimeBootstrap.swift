import IrockCore
import IrockProtocols
import IrockStorage
import IrockTransport

public struct TunnelRuntimeBootstrap: Sendable {
    public static func shadowsocksTCP<Reader: PacketReader, Writer: PacketWriter, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        snapshot: RuntimeSnapshot,
        reader: Reader,
        writer: Writer,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<Reader, Writer> {
        let configuration = try TunnelRuntimeConfiguration.shadowsocksTCP(
            snapshot: snapshot,
            plain: plain,
            tls: tls,
            credentialResolver: credentialResolver,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        return PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)
    }
}
