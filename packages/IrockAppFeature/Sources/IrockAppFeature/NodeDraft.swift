import Foundation
import IrockCore

public enum NodeDraftError: Error, Equatable, Sendable {
    case missingName
    case missingHost
    case missingCredentialAccount
    case invalidPort
    case invalidRealityOptions
    case invalidHysteria2Realm
}

public struct Hysteria2RealmDraft: Equatable, Sendable {
    public var token: String
    public var rendezvousHost: String
    public var rendezvousPort: Int?
    public var name: String
    public var useTLS: Bool
    public var stunServers: [String]
    public var localPort: Int?

    public init(token: String, rendezvousHost: String, rendezvousPort: Int?, name: String, useTLS: Bool, stunServers: [String], localPort: Int?) {
        self.token = token
        self.rendezvousHost = rendezvousHost
        self.rendezvousPort = rendezvousPort
        self.name = name
        self.useTLS = useTLS
        self.stunServers = stunServers
        self.localPort = localPort
    }
}

public struct NodeDraft: Equatable, Sendable {
    public var name: String
    public var protocolType: ProxyProtocolType
    public var serverHost: String
    public var serverPortText: String
    public var credentialAccount: String
    public var transport: TransportType
    public var transportOptions: TransportOptions
    public var tlsEnabled: Bool
    public var tlsServerName: String
    public var tlsAllowInsecure: Bool
    public var tlsALPN: [String]
    public var tlsFingerprint: String?
    public var realityPublicKey: String?
    public var realityShortID: String?
    public var realitySpiderX: String?
    public var hysteria2Realm: Hysteria2RealmDraft?
    public var udpEnabled: Bool

    public init(
        name: String,
        protocolType: ProxyProtocolType,
        serverHost: String,
        serverPortText: String,
        credentialAccount: String,
        transport: TransportType,
        tlsEnabled: Bool,
        tlsServerName: String,
        udpEnabled: Bool,
        transportOptions: TransportOptions = TransportOptions(),
        tlsAllowInsecure: Bool = false,
        tlsALPN: [String] = [],
        tlsFingerprint: String? = nil,
        realityPublicKey: String? = nil,
        realityShortID: String? = nil,
        realitySpiderX: String? = nil,
        hysteria2Realm: Hysteria2RealmDraft? = nil
    ) {
        self.name = name
        self.protocolType = protocolType
        self.serverHost = serverHost
        self.serverPortText = serverPortText
        self.credentialAccount = credentialAccount
        self.transport = transport
        self.transportOptions = transportOptions
        self.tlsEnabled = tlsEnabled
        self.tlsServerName = tlsServerName
        self.tlsAllowInsecure = tlsAllowInsecure
        self.tlsALPN = tlsALPN
        self.tlsFingerprint = tlsFingerprint
        self.realityPublicKey = realityPublicKey
        self.realityShortID = realityShortID
        self.realitySpiderX = realitySpiderX
        self.hysteria2Realm = hysteria2Realm
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

        let trimmedRealityPublicKey = realityPublicKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reality: RealityOptions?
        if let trimmedRealityPublicKey, !trimmedRealityPublicKey.isEmpty {
            reality = RealityOptions(
                publicKey: trimmedRealityPublicKey,
                shortID: normalizedOptional(realityShortID),
                spiderX: normalizedOptional(realitySpiderX)
            )
        } else {
            if normalizedOptional(realityShortID) != nil || normalizedOptional(realitySpiderX) != nil {
                throw NodeDraftError.invalidRealityOptions
            }
            reality = nil
        }

        let realmOptions: Hysteria2Options?
        if let hysteria2Realm {
            let token = hysteria2Realm.token.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = hysteria2Realm.rendezvousHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = hysteria2Realm.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !host.isEmpty, !name.isEmpty else { throw NodeDraftError.invalidHysteria2Realm }
            if let rendezvousPort = hysteria2Realm.rendezvousPort, !(1...65535).contains(rendezvousPort) {
                throw NodeDraftError.invalidHysteria2Realm
            }
            if let localPort = hysteria2Realm.localPort, !(1...65535).contains(localPort) {
                throw NodeDraftError.invalidHysteria2Realm
            }
            realmOptions = Hysteria2Options(
                realm: Hysteria2RealmOptions(
                    tokenReference: CredentialReference(keychainService: keychainService, account: "\(id.rawValue).hysteria2.realm-token"),
                    rendezvousHost: host,
                    rendezvousPort: hysteria2Realm.rendezvousPort,
                    name: name,
                    useTLS: hysteria2Realm.useTLS,
                    stunServers: hysteria2Realm.stunServers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                    localPort: hysteria2Realm.localPort
                )
            )
        } else {
            realmOptions = nil
        }

        return ProxyNode(
            id: id,
            name: trimmedName,
            protocolType: protocolType,
            serverHost: trimmedHost,
            serverPort: port,
            credentialReference: CredentialReference(keychainService: keychainService, account: id.rawValue),
            transport: transport,
            transportOptions: transportOptions,
            tls: TLSOptions(
                enabled: tlsEnabled || reality != nil,
                serverName: normalizedOptional(tlsServerName),
                allowInsecure: tlsAllowInsecure,
                alpn: tlsALPN.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                fingerprint: normalizedOptional(tlsFingerprint),
                reality: reality
            ),
            udpPolicy: udpEnabled ? .enabled : .disabled,
            hysteria2: realmOptions
        )
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
