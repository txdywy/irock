import IrockTransport

public func mapTransportErrorToProxyProtocolError(_ error: TransportError) -> ProxyProtocolError {
    switch error {
    case .invalidConfiguration:
        return .invalidConfiguration("transport invalid")
    case .dnsFailed:
        return .dnsFailed("transport dns failed")
    case .tcpConnectFailed:
        return .tcpConnectFailed("transport tcp connect failed")
    case .tlsHandshakeFailed:
        return .tlsHandshakeFailed("transport tls handshake failed")
    case let .unsupportedTransport(transport):
        return .unsupportedTransport(transport)
    case .quicHandshakeFailed:
        return .quicHandshakeFailed("transport quic handshake failed")
    case .remoteClosed:
        return .remoteClosed
    case .timeout:
        return .timeout
    }
}
