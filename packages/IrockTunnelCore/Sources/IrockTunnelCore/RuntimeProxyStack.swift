import IrockCore
import IrockProtocols
import IrockRouting
import IrockTransport

// MARK: - Configuration-driven factory types

public enum ProxyProtocolKind: Sendable {
    case shadowsocks
    case shadowsocksR
    case vmess
    case vless
    case trojan
    case hysteria2
    case tuic
    case socks
    case httpProxy
    case snell
}

public struct RuntimeProxyStack: Sendable {
    public static func nativeBoundary(for protocolType: ProxyProtocolType) -> ProxyAdapterRegistry {
        ProxyAdapterRegistry(adapters: [UnsupportedNativeRuntimeProxyAdapter(protocolType: protocolType)])
    }

    // MARK: - Generic factories

    public static func makeTCPRegistry<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        protocol protocolKind: ProxyProtocolKind,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tls)
        let transportRegistry = TransportAdapterRegistry(adapters: [selector])
        return makeProtocolRegistry(
            protocol: protocolKind,
            transportRegistry: transportRegistry,
            credentialResolver: credentialResolver
        )
    }

    public static func makeQUICRegistry<QUIC: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        protocol protocolKind: ProxyProtocolKind,
        quic: QUIC,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        let transportRegistry = TransportAdapterRegistry(adapters: [quic])
        return makeProtocolRegistry(
            protocol: protocolKind,
            transportRegistry: transportRegistry,
            credentialResolver: credentialResolver
        )
    }

    public static func makeRealityRegistry<Plain: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        plain: Plain,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        let reality = RealityTransportAdapter(underlying: plain)
        let transportRegistry = TransportAdapterRegistry(adapters: [reality])
        let vless = VLESSProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
        return ProxyAdapterRegistry(adapters: [vless])
    }

    public static func makeGRPCTCPRegistry<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        protocol protocolKind: ProxyProtocolKind,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tls)
        let grpc = GRPCTransportAdapter(underlying: selector)
        let transportRegistry = TransportAdapterRegistry(adapters: [grpc])
        return makeProtocolRegistry(
            protocol: protocolKind,
            transportRegistry: transportRegistry,
            credentialResolver: credentialResolver
        )
    }

    public static func makeGRPCStreamRegistry<Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        stream: Stream,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        let grpc = GRPCStreamTransportAdapter(underlying: stream)
        let streamRegistry = TransportStreamAdapterRegistry(adapters: [grpc])
        let vmess = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: []), streamRegistry: streamRegistry, credentialResolver: credentialResolver)
        return ProxyAdapterRegistry(adapters: [vmess])
    }

    public static func makeHTTP2StreamRegistry<Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        stream: Stream,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        let http2 = HTTP2ConnectStreamTransportAdapter(underlying: stream)
        let streamRegistry = TransportStreamAdapterRegistry(adapters: [http2])
        let trustTunnel = TrustTunnelProxyAdapter(streamRegistry: streamRegistry, credentialResolver: credentialResolver)
        return ProxyAdapterRegistry(adapters: [trustTunnel])
    }

    // MARK: - Protocol adapter dispatch

    private static func makeProtocolRegistry<CredentialResolver: ProxyCredentialResolver>(
        protocol protocolKind: ProxyProtocolKind,
        transportRegistry: TransportAdapterRegistry,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        switch protocolKind {
        case .shadowsocks:
            let adapter = ShadowsocksProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        case .shadowsocksR:
            let adapter = ShadowsocksRProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        case .vmess:
            let adapter = VMessProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        case .vless:
            let adapter = VLESSProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        case .trojan:
            let adapter = TrojanProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        case .hysteria2:
            let adapter = Hysteria2ProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        case .tuic:
            let adapter = TUICProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        case .socks:
            let adapter = SOCKSProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        case .httpProxy:
            let adapter = HTTPProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        case .snell:
            let adapter = SnellProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
            return ProxyAdapterRegistry(adapters: [adapter])
        }
    }

    // MARK: - Convenience methods (backward-compatible)

    public static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeTCPRegistry(protocol: .shadowsocks, plain: plain, tls: tls, credentialResolver: credentialResolver)
    }

    public static func shadowsocksRTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeTCPRegistry(protocol: .shadowsocksR, plain: plain, tls: tls, credentialResolver: credentialResolver)
    }

    public static func vmessTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeTCPRegistry(protocol: .vmess, plain: plain, tls: tls, credentialResolver: credentialResolver)
    }

    public static func socksTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeTCPRegistry(protocol: .socks, plain: plain, tls: tls, credentialResolver: credentialResolver)
    }

    public static func httpProxyTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeTCPRegistry(protocol: .httpProxy, plain: plain, tls: tls, credentialResolver: credentialResolver)
    }

    public static func snellTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeTCPRegistry(protocol: .snell, plain: plain, tls: tls, credentialResolver: credentialResolver)
    }

    public static func vmessGRPC<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeGRPCTCPRegistry(protocol: .vmess, plain: plain, tls: tls, credentialResolver: credentialResolver)
    }

    public static func vmessGRPC<Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        stream: Stream,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeGRPCStreamRegistry(stream: stream, credentialResolver: credentialResolver)
    }

    public static func trustTunnelHTTP2<Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        stream: Stream,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeHTTP2StreamRegistry(stream: stream, credentialResolver: credentialResolver)
    }

    public static func vlessTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeTCPRegistry(protocol: .vless, plain: plain, tls: tls, credentialResolver: credentialResolver)
    }

    public static func vlessRealityTCP<Plain: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        plain: Plain,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeRealityRegistry(plain: plain, credentialResolver: credentialResolver)
    }

    public static func trojanTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeTCPRegistry(protocol: .trojan, plain: plain, tls: tls, credentialResolver: credentialResolver)
    }

    public static func hysteria2QUIC<QUIC: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        quic: QUIC,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeQUICRegistry(protocol: .hysteria2, quic: quic, credentialResolver: credentialResolver)
    }

    public static func tuicQUIC<QUIC: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        quic: QUIC,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        makeQUICRegistry(protocol: .tuic, quic: quic, credentialResolver: credentialResolver)
    }

    public static func tuicQUIC<SessionDialer: TUICQUICSessionDialer, CredentialResolver: ProxyCredentialResolver>(
        sessionDialer: SessionDialer,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        let tuic = TUICProxyAdapter(sessionDialer: sessionDialer, credentialResolver: credentialResolver)
        return ProxyAdapterRegistry(adapters: [tuic])
    }
}

// MARK: - Generic TunnelRuntimeConfiguration factories

public extension TunnelRuntimeConfiguration {
    static func makeConfiguration(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        proxyAdapterRegistry: ProxyAdapterRegistry,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: proxyAdapterRegistry,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func makeConfiguration(
        snapshot: RuntimeSnapshot,
        proxyAdapterRegistry: ProxyAdapterRegistry,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try TunnelRuntimeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: proxyAdapterRegistry,
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    // MARK: - Convenience methods (backward-compatible)

    static func vmessTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.vmessTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vmessTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.vmessTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func socksTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.socksTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func socksTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.socksTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func httpProxyTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.httpProxyTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func httpProxyTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.httpProxyTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func snellTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.snellTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func snellTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.snellTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vmessGRPC<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.vmessGRPC(plain: plain, tls: tls, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vmessGRPC<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.vmessGRPC(plain: plain, tls: tls, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vmessGRPC<Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.vmessGRPC(stream: stream, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vmessGRPC<Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.vmessGRPC(stream: stream, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func trustTunnelHTTP2<Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.trustTunnelHTTP2(stream: stream, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func trustTunnelHTTP2<Stream: TransportStreamAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        stream: Stream,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.trustTunnelHTTP2(stream: stream, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vlessTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.vlessTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vlessTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.vlessTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vlessRealityTCP<Plain: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.vlessRealityTCP(plain: plain, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vlessRealityTCP<Plain: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.vlessRealityTCP(plain: plain, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func hysteria2QUIC<QUIC: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        quic: QUIC,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.hysteria2QUIC(quic: quic, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func hysteria2QUIC<QUIC: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        quic: QUIC,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.hysteria2QUIC(quic: quic, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func tuicQUIC<QUIC: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        quic: QUIC,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.tuicQUIC(quic: quic, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func tuicQUIC<QUIC: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        quic: QUIC,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.tuicQUIC(quic: quic, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func tuicQUIC<SessionDialer: TUICQUICSessionDialer, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        sessionDialer: SessionDialer,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: (any UDPDatagramForwarder)? = nil,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.tuicQUIC(sessionDialer: sessionDialer, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder ?? TUICQUICUDPDatagramForwarder(sessionDialer: sessionDialer, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func tuicQUIC<SessionDialer: TUICQUICSessionDialer, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        sessionDialer: SessionDialer,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: (any UDPDatagramForwarder)? = nil,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.tuicQUIC(sessionDialer: sessionDialer, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder ?? TUICQUICUDPDatagramForwarder(sessionDialer: sessionDialer, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func trojanTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.trojanTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func trojanTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ProxyCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.trojanTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func shadowsocksRTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.shadowsocksRTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        makeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        udpDatagramForwarder: any UDPDatagramForwarder = NoopUDPDatagramForwarder(),
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try makeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            udpDatagramForwarder: udpDatagramForwarder,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
}
