import Foundation
import IrockTransport

struct MacOSPlatformTCPDialer: TCPDialer {
    func open(host: String, port: Int, initialPayload: Data?) async throws -> TCPDialResult {
        throw TransportError.tcpConnectFailed("macOS TCP dialing deferred until runtime integration")
    }
}
