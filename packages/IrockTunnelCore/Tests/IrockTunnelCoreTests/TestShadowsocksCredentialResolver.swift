import IrockCore
import IrockProtocols

struct TestProxyCredentialResolver: ProxyCredentialResolver {
    let storedCredential: String

    init(credential: String = "aes-256-gcm:pass") {
        self.storedCredential = credential
    }

    func credential(for reference: CredentialReference) throws -> String {
        storedCredential
    }
}

typealias TestShadowsocksCredentialResolver = TestProxyCredentialResolver
