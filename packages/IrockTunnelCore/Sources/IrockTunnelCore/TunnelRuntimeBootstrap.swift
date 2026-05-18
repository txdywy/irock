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
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<Reader, Writer> {
        let configuration = try TunnelRuntimeConfiguration.shadowsocksTCP(
            snapshot: snapshot,
            plain: plain,
            tls: tls,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        return PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)
    }

    public static func shadowsocksRTCP<Reader: PacketReader, Writer: PacketWriter, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
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
        let configuration = try TunnelRuntimeConfiguration.shadowsocksRTCP(
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

    public static func vmessGRPC<Reader: PacketReader, Writer: PacketWriter, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        reader: Reader,
        writer: Writer,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<Reader, Writer> {
        let configuration = try TunnelRuntimeConfiguration.vmessGRPC(
            snapshot: snapshot,
            plain: plain,
            tls: tls,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        return PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)
    }

    public static func socksTCP<Reader: PacketReader, Writer: PacketWriter, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
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
        let configuration = try TunnelRuntimeConfiguration.socksTCP(
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

    public static func httpProxyTCP<Reader: PacketReader, Writer: PacketWriter, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
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
        let configuration = try TunnelRuntimeConfiguration.httpProxyTCP(
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

    public static func snellTCP<Reader: PacketReader, Writer: PacketWriter, Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
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
        let configuration = try TunnelRuntimeConfiguration.snellTCP(
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

    public static func vmessGRPC<Reader: PacketReader, Writer: PacketWriter, Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        reader: Reader,
        writer: Writer,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<Reader, Writer> {
        let configuration = try TunnelRuntimeConfiguration.vmessGRPC(
            snapshot: snapshot,
            stream: stream,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        return PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)
    }

    public static func trustTunnelHTTP2<Reader: PacketReader, Writer: PacketWriter, Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        reader: Reader,
        writer: Writer,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<Reader, Writer> {
        let configuration = try TunnelRuntimeConfiguration.trustTunnelHTTP2(
            snapshot: snapshot,
            stream: stream,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        return PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)
    }

    public static func tuicQUIC<Reader: PacketReader, Writer: PacketWriter, SessionDialer: TUICQUICSessionDialer, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        reader: Reader,
        writer: Writer,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        sessionDialer: SessionDialer,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: (any UDPDatagramForwarder)? = nil,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<Reader, Writer> {
        let configuration = try TunnelRuntimeConfiguration.tuicQUIC(
            snapshot: snapshot,
            sessionDialer: sessionDialer,
            credentialResolver: credentialResolver,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        return PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)
    }
}
