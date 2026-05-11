import IrockCore
import IrockProtocols
import IrockRouting
import IrockTransport

public struct RuntimeProxyStack: Sendable {
    public static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver
    ) -> ProxyAdapterRegistry {
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tls)
        let transportRegistry = TransportAdapterRegistry(adapters: [selector])
        let shadowsocks = ShadowsocksProxyAdapter(transportRegistry: transportRegistry, credentialResolver: credentialResolver)
        return ProxyAdapterRegistry(adapters: [shadowsocks])
    }

    public static func vmessTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        plain: Plain,
        tls: TLS
    ) -> ProxyAdapterRegistry {
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tls)
        let transportRegistry = TransportAdapterRegistry(adapters: [selector])
        let vmess = VMessProxyAdapter(transportRegistry: transportRegistry)
        return ProxyAdapterRegistry(adapters: [vmess])
    }

    public static func vlessTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        plain: Plain,
        tls: TLS
    ) -> ProxyAdapterRegistry {
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tls)
        let transportRegistry = TransportAdapterRegistry(adapters: [selector])
        let vless = VLESSProxyAdapter(transportRegistry: transportRegistry)
        return ProxyAdapterRegistry(adapters: [vless])
    }

    public static func vlessRealityTCP<Plain: TransportAdapter>(
        plain: Plain
    ) -> ProxyAdapterRegistry {
        let reality = RealityTransportAdapter(underlying: plain)
        let transportRegistry = TransportAdapterRegistry(adapters: [reality])
        let vless = VLESSProxyAdapter(transportRegistry: transportRegistry)
        return ProxyAdapterRegistry(adapters: [vless])
    }

    public static func trojanTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        plain: Plain,
        tls: TLS
    ) -> ProxyAdapterRegistry {
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tls)
        let transportRegistry = TransportAdapterRegistry(adapters: [selector])
        let trojan = TrojanProxyAdapter(transportRegistry: transportRegistry)
        return ProxyAdapterRegistry(adapters: [trojan])
    }

    public static func hysteria2QUIC<QUIC: TransportAdapter>(
        quic: QUIC
    ) -> ProxyAdapterRegistry {
        let transportRegistry = TransportAdapterRegistry(adapters: [quic])
        let hysteria2 = Hysteria2ProxyAdapter(transportRegistry: transportRegistry)
        return ProxyAdapterRegistry(adapters: [hysteria2])
    }
}

public extension TunnelRuntimeConfiguration {
    static func vmessTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.vmessTCP(plain: plain, tls: tls),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vmessTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try TunnelRuntimeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.vmessTCP(plain: plain, tls: tls),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vlessTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.vlessTCP(plain: plain, tls: tls),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vlessTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try TunnelRuntimeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.vlessTCP(plain: plain, tls: tls),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vlessRealityTCP<Plain: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.vlessRealityTCP(plain: plain),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func vlessRealityTCP<Plain: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try TunnelRuntimeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.vlessRealityTCP(plain: plain),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func hysteria2QUIC<QUIC: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        quic: QUIC,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.hysteria2QUIC(quic: quic),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func hysteria2QUIC<QUIC: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        quic: QUIC,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try TunnelRuntimeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.hysteria2QUIC(quic: quic),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func trojanTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        routingEngine: RoutingEngine,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.trojanTCP(plain: plain, tls: tls),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func trojanTCP<Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try TunnelRuntimeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.trojanTCP(plain: plain, tls: tls),
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
        batchLimit: Int,
        flowLimit: Int
    ) -> TunnelRuntimeConfiguration {
        TunnelRuntimeConfiguration(
            snapshot: snapshot,
            routingEngine: routingEngine,
            proxyAdapterRegistry: RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }

    static func shadowsocksTCP<Plain: TransportAdapter, TLS: TransportAdapter, CredentialResolver: ShadowsocksCredentialResolver>(
        snapshot: RuntimeSnapshot,
        plain: Plain,
        tls: TLS,
        credentialResolver: CredentialResolver,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> TunnelRuntimeConfiguration {
        try TunnelRuntimeConfiguration(
            snapshot: snapshot,
            proxyAdapterRegistry: RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tls, credentialResolver: credentialResolver),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
}
