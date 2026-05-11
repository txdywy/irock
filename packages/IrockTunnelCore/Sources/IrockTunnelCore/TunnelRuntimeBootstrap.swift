import IrockCore
import IrockStorage
import IrockTransport

public struct TunnelRuntimeBootstrap: Sendable {
    public static func shadowsocksTCP<Reader: PacketReader, Writer: PacketWriter, Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        reader: Reader,
        writer: Writer,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<Reader, Writer> {
        let configuration = try TunnelRuntimeConfiguration.shadowsocksTCP(
            snapshot: snapshot,
            plain: plain,
            tls: tls,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        return PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)
    }
}
