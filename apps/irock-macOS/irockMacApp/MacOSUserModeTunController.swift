import Foundation
import IrockAppFeature
import IrockCore
import IrockProtocols
import IrockStorage
import IrockTransport
import IrockTunnelCore

final class MacOSUserModeTunController: UserModeTunControlling {
    private let address: String
    private let gateway: String
    private let mtu: Int
    private let storeResolver: MacOSAppGroupRuntimeStoreResolver
    private let runtimeStores: RuntimeStoreBundle?
    private let batchLimit: Int
    private let flowLimit: Int
    private var device: MacOSUserModeTunDevice?
    private var activeEndpoint: UserModeTunEndpoint?
    private var originalDNSServers: [String]?
    private var runtimeTask: Task<Void, Never>?

    init(
        address: String = "10.255.0.2",
        gateway: String = "10.255.0.1",
        mtu: Int = 1500,
        storeResolver: MacOSAppGroupRuntimeStoreResolver = MacOSAppGroupRuntimeStoreResolver(),
        runtimeStores: RuntimeStoreBundle? = nil,
        batchLimit: Int = 8,
        flowLimit: Int = 64
    ) {
        self.address = address
        self.gateway = gateway
        self.mtu = mtu
        self.storeResolver = storeResolver
        self.runtimeStores = runtimeStores
        self.batchLimit = batchLimit
        self.flowLimit = flowLimit
    }

    func start(node: ProxyNode, credential: String) throws -> UserModeTunEndpoint {
        if let activeEndpoint {
            return activeEndpoint
        }
        guard getuid() == 0 else {
            throw UserModeTunError.authorizationRequired
        }
        _ = node
        _ = credential
        let device = try MacOSUserModeTunDevice()
        let endpoint = UserModeTunEndpoint(interfaceName: device.interfaceName, address: address, gateway: gateway, mtu: mtu)
        let commands = MacOSUserModeTunRouteCommands(endpoint: endpoint)
        var didAddDefaultRoute = false
        var didAddSecondaryDefaultRoute = false
        var didEnableDNS = false
        var rollbackDNSServers: [String]?
        do {
            try run(commands.configureInterface)
            try run(commands.addDefaultRoute)
            didAddDefaultRoute = true
            try run(commands.addSecondaryDefaultRoute)
            didAddSecondaryDefaultRoute = true
            rollbackDNSServers = try currentDNSServers(commands: commands)
            try run(commands.enableDNS)
            didEnableDNS = true
            runtimeTask = startRuntimeLoop(fileDescriptor: device.fileDescriptor, node: node, credential: credential)
            self.originalDNSServers = rollbackDNSServers
            self.device = device
            activeEndpoint = endpoint
            return endpoint
        } catch {
            if didEnableDNS { try? restoreDNS(commands: commands, servers: rollbackDNSServers) }
            if didAddSecondaryDefaultRoute { try? run(commands.deleteSecondaryDefaultRoute) }
            if didAddDefaultRoute { try? run(commands.deleteDefaultRoute) }
            device.close()
            throw UserModeTunError.unavailable
        }
    }

    func stop() throws {
        guard let endpoint = activeEndpoint else { return }
        runtimeTask?.cancel()
        runtimeTask = nil
        device?.close()
        let commands = MacOSUserModeTunRouteCommands(endpoint: endpoint)
        try? run(commands.deleteSecondaryDefaultRoute)
        try? run(commands.deleteDefaultRoute)
        let dnsServers = originalDNSServers
        device = nil
        activeEndpoint = nil
        originalDNSServers = nil
        try restoreDNS(commands: commands, servers: dnsServers)
    }

    private func run(_ arguments: [String]) throws {
        _ = try runAndCapture(arguments)
    }

    private func runAndCapture(_ arguments: [String]) throws -> String {
        guard let executable = arguments.first else { return "" }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UserModeTunError.unavailable
        }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func currentDNSServers(commands: MacOSUserModeTunRouteCommands) throws -> [String]? {
        let output = try runAndCapture(commands.getDNS)
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        if lines.contains("There aren't any DNS Servers set on Wi-Fi.") || lines.contains("There aren't any DNS Servers set on \(commands.serviceName).") {
            return nil
        }
        return lines.isEmpty ? nil : lines
    }

    private func restoreDNS(commands: MacOSUserModeTunRouteCommands, servers: [String]?) throws {
        try run(commands.setDNS(servers))
    }

    private func startRuntimeLoop(fileDescriptor: Int32, node: ProxyNode, credential: String) -> Task<Void, Never> {
        let storeResolver = storeResolver
        let runtimeStores = runtimeStores
        let batchLimit = batchLimit
        let flowLimit = flowLimit
        return Task.detached(priority: .userInitiated) {
            while !Task.isCancelled {
                do {
                    let stores = try runtimeStores ?? storeResolver.makeRuntimeStoreBundle()
                    _ = try await TunnelRuntimeController.runShadowsocksTCPBatch(
                        snapshotStore: stores.snapshotStore,
                        flow: MacOSUserModeTunPacketFlowIO(fileDescriptor: fileDescriptor),
                        statusStore: stores.statusStore,
                        logStore: stores.logStore,
                        plain: TCPTransportAdapter(dialer: MacOSPlatformTCPDialer()),
                        tls: UnsupportedTransportAdapter(transport: .tcp),
                        credentialResolver: MacOSImportedShadowsocksCredentialResolver(nodeID: node.id, credential: credential),
                        batchLimit: batchLimit,
                        flowLimit: flowLimit
                    )
                } catch {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        }
    }
}
