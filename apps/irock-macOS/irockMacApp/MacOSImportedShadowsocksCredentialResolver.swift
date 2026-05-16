import IrockCore
import IrockProtocols

struct MacOSImportedProxyCredentialResolver: ProxyCredentialResolver {
    let nodeID: NodeID
    let credential: String

    func credential(for reference: CredentialReference) throws -> String {
        guard reference.account == nodeID.rawValue else {
            throw ProxyProtocolError.invalidConfiguration("missing proxy credential material")
        }
        return credential
    }
}

typealias MacOSImportedShadowsocksCredentialResolver = MacOSImportedProxyCredentialResolver
