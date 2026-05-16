import Foundation
import IrockCore
import IrockNativeHysteria2
import IrockProtocols
import IrockStorage
import IrockTransport
import IrockTunnelCore
import NetworkExtension
import Security

private struct NativeTransportByteStream: TransportByteStream {
    let stream: any NativeHysteria2ByteStream

    func read(maxLength: Int) async throws -> Data? {
        try await stream.read(maxLength: maxLength)
    }

    func write(_ data: Data) async throws {
        try await stream.write(data)
    }

    func closeWrite() async {
        try? await stream.closeWrite()
    }

    func close() async {
        await stream.close()
    }
}

private struct NativeTUICQUICSession: TUICQUICSession {
    let session: NativeHysteria2Session

    func exportKeyingMaterial(label: Data, context: Data, length: Int) async throws -> Data {
        try await session.exportKeyingMaterial(label: label, context: context, length: length)
    }

    func openUnidirectionalStream(initialPayload: Data) async throws -> any TransportByteStream {
        NativeTransportByteStream(stream: try await session.openRawUnidirectionalStream(initialPayload: initialPayload))
    }

    func openBidirectionalStream(initialPayload: Data) async throws -> any TransportByteStream {
        NativeTransportByteStream(stream: try await session.openRawBidirectionalStream(initialPayload: initialPayload))
    }
}

private struct KeychainProxyCredentialResolver: ProxyCredentialResolver {
    func credential(for reference: CredentialReference) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.keychainService,
            kSecAttrAccount as String: reference.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let credential = String(data: data, encoding: .utf8), !credential.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing proxy credential material")
        }
        return credential
    }
}

private struct NativeTUICQUICSessionDialer: TUICQUICSessionDialer {
    func openSession(host: String, port: Int, tls: TLSOptions?, metadata: [String: String]) async throws -> any TUICQUICSession {
        let configuration = try NativeHysteria2ClientConfiguration(
            serverHost: host,
            serverPort: port,
            serverName: tls?.serverName ?? host,
            alpn: tls?.alpn.isEmpty == false ? tls?.alpn ?? ["h3"] : ["h3"],
            allowInsecure: tls?.allowInsecure ?? false,
            certificatePinSHA256: tls?.fingerprint
        )
        return NativeTUICQUICSession(session: try await NativeHysteria2Client(configuration: configuration).connectQUICSession())
    }
}

struct MacOSPacketTunnelSmokeRunner: Sendable {
    private let storeResolver: PacketTunnelAppGroupStoreResolver
    private let batchLimit: Int
    private let flowLimit: Int

    init(
        storeResolver: PacketTunnelAppGroupStoreResolver = PacketTunnelAppGroupStoreResolver(),
        batchLimit: Int = 8,
        flowLimit: Int = 64
    ) {
        self.storeResolver = storeResolver
        self.batchLimit = batchLimit
        self.flowLimit = flowLimit
    }

    func validateStartup() throws {
        let stores = try storeResolver.makeRuntimeStoreBundle()
        do {
            guard try stores.snapshotStore.load() != nil else {
                reportMissingSnapshot(stores: stores)
                throw TunnelRuntimeControllerError.missingRuntimeSnapshot
            }
        } catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
            throw TunnelRuntimeControllerError.missingRuntimeSnapshot
        } catch {
            let reporter = TunnelRuntimeReporter(statusStore: stores.statusStore, logStore: stores.logStore)
            try? reporter.reportRuntimeStoreUnavailable()
            throw error
        }
    }

    func makeSession(packetFlow: NEPacketTunnelFlow) throws -> PacketTunnelRuntime<PacketFlowRuntimeIO<NEPacketTunnelFlowPacketFlowIO>, PacketFlowRuntimeIO<NEPacketTunnelFlowPacketFlowIO>> {
        let stores = try storeResolver.makeRuntimeStoreBundle()
        let snapshot = try loadSnapshot(stores: stores)
        let flow = NEPacketTunnelFlowPacketFlowIO(packetFlow: packetFlow)
        switch snapshot.selectedNode.protocolType {
        case .vmess where snapshot.selectedNode.transport == .grpc:
            return try TunnelRuntimeController.makeVMessGRPCSession(
                snapshotStore: stores.snapshotStore,
                flow: flow,
                statusStore: stores.statusStore,
                logStore: stores.logStore,
                stream: MacOSPlatformTCPByteStreamDialer(),
                credentialResolver: KeychainProxyCredentialResolver(),
                udpDatagramForwarder: DirectUDPDatagramForwarder(client: MacOSPlatformUDPDatagramClient()),
                batchLimit: batchLimit,
                flowLimit: flowLimit
            )
        case .tuic:
            return try TunnelRuntimeController.makeTUICQUICSession(
                snapshotStore: stores.snapshotStore,
                flow: flow,
                statusStore: stores.statusStore,
                logStore: stores.logStore,
                sessionDialer: NativeTUICQUICSessionDialer(),
                credentialResolver: KeychainProxyCredentialResolver(),
                udpDatagramForwarder: DirectUDPDatagramForwarder(client: MacOSPlatformUDPDatagramClient()),
                batchLimit: batchLimit,
                flowLimit: flowLimit
            )
        default:
            let plain = TCPTransportAdapter(dialer: MacOSPlatformTCPDialer())
            let tls = UnsupportedTransportAdapter(transport: .tcp)
            let credentialResolver = MissingShadowsocksCredentialResolver()
            let registry = RuntimeProxyStack.shadowsocksTCP(plain: plain, tls: tls, credentialResolver: credentialResolver)
            return try TunnelRuntimeController.makeShadowsocksTCPSession(
                snapshotStore: stores.snapshotStore,
                flow: flow,
                statusStore: stores.statusStore,
                logStore: stores.logStore,
                plain: plain,
                tls: tls,
                credentialResolver: credentialResolver,
                udpDatagramForwarder: ProtocolUDPDatagramForwarder(client: MacOSPlatformUDPDatagramClient(), proxyAdapterRegistry: registry),
                batchLimit: batchLimit,
                flowLimit: flowLimit
            )
        }
    }

    func runOnce(packetFlow: NEPacketTunnelFlow) async throws -> PacketTunnelRuntimeSummary {
        let runtime = try makeSession(packetFlow: packetFlow)
        do {
            let summary = try await runtime.runOnce()
            await runtime.closeProxyConnections()
            return summary
        } catch {
            await runtime.closeProxyConnections()
            throw error
        }
    }

    private func loadSnapshot(stores: RuntimeStoreBundle) throws -> RuntimeSnapshot {
        do {
            guard let snapshot = try stores.snapshotStore.load() else {
                reportMissingSnapshot(stores: stores)
                throw TunnelRuntimeControllerError.missingRuntimeSnapshot
            }
            return snapshot
        } catch TunnelRuntimeControllerError.missingRuntimeSnapshot {
            throw TunnelRuntimeControllerError.missingRuntimeSnapshot
        } catch {
            let reporter = TunnelRuntimeReporter(statusStore: stores.statusStore, logStore: stores.logStore)
            try? reporter.reportRuntimeStoreUnavailable()
            throw error
        }
    }

    private func reportMissingSnapshot(stores: RuntimeStoreBundle) {
        let message = "Runtime snapshot unavailable"
        try? stores.statusStore.save(RuntimeConnectionStatus(
            phase: .failed,
            selectedNodeID: nil,
            selectedNodeName: nil,
            updatedAt: Date(),
            message: message
        ))
        try? stores.logStore.append(RuntimeLogEntry(
            id: "log-\(UUID().uuidString)",
            timestamp: Date(),
            level: .user,
            message: message,
            nodeID: nil,
            phase: .failed
        ))
    }
}
