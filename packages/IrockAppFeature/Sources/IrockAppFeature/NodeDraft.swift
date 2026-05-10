import Foundation
import IrockCore

public enum NodeDraftError: Error, Equatable, Sendable {
    case missingName
    case missingHost
    case missingCredentialAccount
    case invalidPort
}

public struct NodeDraft: Equatable, Sendable {
    public var name: String
    public var protocolType: ProxyProtocolType
    public var serverHost: String
    public var serverPortText: String
    public var credentialAccount: String
    public var transport: TransportType
    public var tlsEnabled: Bool
    public var tlsServerName: String
    public var udpEnabled: Bool

    public init(name: String, protocolType: ProxyProtocolType, serverHost: String, serverPortText: String, credentialAccount: String, transport: TransportType, tlsEnabled: Bool, tlsServerName: String, udpEnabled: Bool) {
        self.name = name
        self.protocolType = protocolType
        self.serverHost = serverHost
        self.serverPortText = serverPortText
        self.credentialAccount = credentialAccount
        self.transport = transport
        self.tlsEnabled = tlsEnabled
        self.tlsServerName = tlsServerName
        self.udpEnabled = udpEnabled
    }

    public func buildNode(id: NodeID, keychainService: String) throws -> ProxyNode {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = credentialAccount.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { throw NodeDraftError.missingName }
        guard !trimmedHost.isEmpty else { throw NodeDraftError.missingHost }
        guard !trimmedAccount.isEmpty else { throw NodeDraftError.missingCredentialAccount }
        guard let port = Int(serverPortText), (1...65535).contains(port) else { throw NodeDraftError.invalidPort }

        return ProxyNode(
            id: id,
            name: trimmedName,
            protocolType: protocolType,
            serverHost: trimmedHost,
            serverPort: port,
            credentialReference: CredentialReference(keychainService: keychainService, account: trimmedAccount),
            transport: transport,
            tls: TLSOptions(enabled: tlsEnabled, serverName: tlsServerName.isEmpty ? nil : tlsServerName, allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: udpEnabled ? .enabled : .disabled
        )
    }
}
