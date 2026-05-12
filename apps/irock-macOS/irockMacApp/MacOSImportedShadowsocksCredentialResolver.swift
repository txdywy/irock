import IrockCore
import IrockProtocols

struct MacOSImportedShadowsocksCredentialResolver: ShadowsocksCredentialResolver {
    let nodeID: NodeID
    let credential: String

    func credential(for reference: CredentialReference) throws -> String {
        guard reference.account == nodeID.rawValue else {
            throw ProxyProtocolError.invalidConfiguration("missing shadowsocks credential material")
        }
        return credential
    }
}
