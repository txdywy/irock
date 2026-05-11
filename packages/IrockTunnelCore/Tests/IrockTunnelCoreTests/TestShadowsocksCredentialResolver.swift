import IrockCore
import IrockProtocols

struct TestShadowsocksCredentialResolver: ShadowsocksCredentialResolver {
    func credential(for reference: CredentialReference) throws -> String {
        "aes-256-gcm:pass"
    }
}
