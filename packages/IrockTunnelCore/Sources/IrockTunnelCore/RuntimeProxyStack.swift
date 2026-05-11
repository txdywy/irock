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
}

public extension TunnelRuntimeConfiguration {
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
