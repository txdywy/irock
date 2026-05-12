import Foundation
import IrockAppFeature
import IrockCore
import IrockProtocols
import Network

final class MacOSLocalProxyController: LocalProxyControlling {
    private let queue = DispatchQueue(label: "dev.irock.macos-local-proxy")
    private let endpoint: LocalProxyEndpoint
    private let lock = NSLock()
    private var socksListener: NWListener?
    private var httpListener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var activeHandlers: [ObjectIdentifier: AnyObject] = [:]

    init(endpoint: LocalProxyEndpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)) {
        self.endpoint = endpoint
    }

    func start(node: ProxyNode, credential: String) throws -> LocalProxyEndpoint {
        guard node.protocolType == .shadowsocks, node.transport == .tcp else {
            throw LocalProxyError.unavailable
        }
        stopListeners()
        let socks = try makeListener(port: endpoint.socksPort)
        let http = try makeListener(port: endpoint.httpPort)
        socks.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.track(connection)
            let handler = MacOSSOCKS5ConnectionHandler(
                connection: connection,
                node: node,
                credential: credential,
                onClose: { [weak self, weak connection] in
                    if let connection { self?.untrack(connection) }
                }
            )
            self.retain(handler, for: connection)
            handler.start(on: self.queue)
        }
        http.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.track(connection)
            let handler = MacOSHTTPProxyConnectionHandler(
                connection: connection,
                node: node,
                credential: credential,
                onClose: { [weak self, weak connection] in
                    if let connection { self?.untrack(connection) }
                }
            )
            self.retain(handler, for: connection)
            handler.start(on: self.queue)
        }
        socks.start(queue: queue)
        http.start(queue: queue)
        socksListener = socks
        httpListener = http
        return endpoint
    }

    func stop() throws {
        stopListeners()
    }

    private func makeListener(port: Int) throws -> NWListener {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw LocalProxyError.unavailable
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(endpoint.host), port: nwPort)
        return try NWListener(using: parameters, on: nwPort)
    }

    private func track(_ connection: NWConnection) {
        lock.lock()
        activeConnections.append(connection)
        lock.unlock()
    }

    private func untrack(_ connection: NWConnection) {
        lock.lock()
        activeConnections.removeAll { $0 === connection }
        activeHandlers.removeValue(forKey: ObjectIdentifier(connection))
        lock.unlock()
    }

    private func retain(_ handler: AnyObject, for connection: NWConnection) {
        lock.lock()
        activeHandlers[ObjectIdentifier(connection)] = handler
        lock.unlock()
    }

    private func stopListeners() {
        socksListener?.cancel()
        httpListener?.cancel()
        socksListener = nil
        httpListener = nil
        lock.lock()
        let connections = activeConnections
        activeConnections.removeAll()
        activeHandlers.removeAll()
        lock.unlock()
        for connection in connections {
            connection.cancel()
        }
    }
}

private final class MacOSSOCKS5ConnectionHandler {
    private let connection: NWConnection
    private let node: ProxyNode
    private let credential: String
    private let onClose: () -> Void
    private var remoteConnection: NWConnection?
    private var relay: MacOSShadowsocksRelay?

    init(connection: NWConnection, node: ProxyNode, credential: String, onClose: @escaping () -> Void) {
        self.connection = connection
        self.node = node
        self.credential = credential
        self.onClose = onClose
    }

    func start(on queue: DispatchQueue) {
        connection.start(queue: queue)
        readGreetingHeader(on: queue)
    }

    private func readGreetingHeader(on queue: DispatchQueue) {
        readExact(2, from: connection, on: queue) { [weak self] data in
            guard let self else { return }
            let bytes = Array(data)
            guard bytes.count == 2, bytes[0] == 0x05, bytes[1] > 0 else {
                self.close()
                return
            }
            self.readGreetingMethods(count: Int(bytes[1]), on: queue)
        }
    }

    private func readGreetingMethods(count: Int, on queue: DispatchQueue) {
        readExact(count, from: connection, on: queue) { [weak self] data in
            guard let self else { return }
            guard data.contains(0x00) else {
                self.connection.send(content: Data([0x05, 0xff]), completion: .contentProcessed { [weak self] _ in self?.close() })
                return
            }
            self.connection.send(content: Data([0x05, 0x00]), completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil {
                    self.close()
                    return
                }
                self.readRequestHeader(on: queue)
            })
        }
    }

    private func readRequestHeader(on queue: DispatchQueue) {
        readExact(4, from: connection, on: queue) { [weak self] header in
            guard let self else { return }
            let bytes = Array(header)
            guard bytes.count == 4, bytes[0] == 0x05, bytes[1] == 0x01 else {
                self.sendSOCKSFailure()
                return
            }
            self.readDestination(atyp: bytes[3], on: queue)
        }
    }

    private func readDestination(atyp: UInt8, on queue: DispatchQueue) {
        switch atyp {
        case 0x01:
            readExact(6, from: connection, on: queue) { [weak self] data in
                guard let self else { return }
                let bytes = Array(data)
                let host = bytes[0..<4].map(String.init).joined(separator: ".")
                self.openRemote(destination: .ipv4(host, port: Self.port(from: bytes, at: 4)), on: queue)
            }
        case 0x03:
            readExact(1, from: connection, on: queue) { [weak self] lengthData in
                guard let self, let length = lengthData.first else { return }
                self.readDomain(length: Int(length), on: queue)
            }
        case 0x04:
            readExact(18, from: connection, on: queue) { [weak self] data in
                guard let self else { return }
                let bytes = Array(data)
                let groups = stride(from: 0, to: 16, by: 2).map { String(format: "%02x%02x", bytes[$0], bytes[$0 + 1]) }
                self.openRemote(destination: .ipv6(groups.joined(separator: ":"), port: Self.port(from: bytes, at: 16)), on: queue)
            }
        default:
            sendSOCKSFailure()
        }
    }

    private func readDomain(length: Int, on queue: DispatchQueue) {
        readExact(length + 2, from: connection, on: queue) { [weak self] data in
            guard let self else { return }
            let bytes = Array(data)
            guard bytes.count == length + 2, let host = String(data: Data(bytes[0..<length]), encoding: .utf8) else {
                self.sendSOCKSFailure()
                return
            }
            self.openRemote(destination: .host(host, port: Self.port(from: bytes, at: length)), on: queue)
        }
    }

    private func openRemote(destination: ProxyDestination, on queue: DispatchQueue) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(node.serverPort)) else {
            sendSOCKSFailure()
            return
        }
        let remote = NWConnection(host: NWEndpoint.Host(node.serverHost), port: port, using: .tcp)
        remoteConnection = remote
        remote.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendShadowsocksOpen(destination: destination, remote: remote, on: queue)
            case .failed, .cancelled:
                self.close()
            case .setup, .preparing, .waiting:
                break
            @unknown default:
                self.close()
            }
        }
        remote.start(queue: queue)
    }

    private func sendShadowsocksOpen(destination: ProxyDestination, remote: NWConnection, on queue: DispatchQueue) {
        do {
            let salt = Self.randomSalt()
            let request = try ShadowsocksStreamRequest(credential: credential, destination: destination, salt: salt)
            let relay = try MacOSShadowsocksRelay(credential: credential, clientSalt: salt)
            self.relay = relay
            remote.send(content: request.openBytes, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil {
                    self.sendSOCKSFailure()
                    return
                }
                self.connection.send(content: Data([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]), completion: .contentProcessed { [weak self] error in
                    guard let self else { return }
                    if error != nil {
                        self.close()
                        return
                    }
                    relay.pipeLocalToRemote(local: self.connection, remote: remote)
                    relay.pipeRemoteToLocal(remote: remote, local: self.connection, on: queue)
                })
            })
        } catch {
            sendSOCKSFailure()
        }
    }

    private func readExact(_ count: Int, from connection: NWConnection, on queue: DispatchQueue, completion: @escaping (Data) -> Void) {
        readExact(count, accumulated: Data(), from: connection, on: queue, completion: completion)
    }

    private func readExact(_ count: Int, accumulated: Data, from connection: NWConnection, on queue: DispatchQueue, completion: @escaping (Data) -> Void) {
        guard accumulated.count < count else {
            completion(accumulated)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard error == nil, !isComplete, let data, !data.isEmpty else {
                self.close()
                return
            }
            var next = accumulated
            next.append(data)
            self.readExact(count, accumulated: next, from: connection, on: queue, completion: completion)
        }
    }

    private func sendSOCKSFailure() {
        connection.send(content: Data([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]), completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    private func close() {
        connection.cancel()
        remoteConnection?.cancel()
        relay = nil
        onClose()
    }

    private static func port(from bytes: [UInt8], at index: Int) -> Int {
        Int(bytes[index]) << 8 | Int(bytes[index + 1])
    }

    private static func randomSalt() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) })
    }
}

private final class MacOSHTTPProxyConnectionHandler {
    private let connection: NWConnection
    private let node: ProxyNode
    private let credential: String
    private let onClose: () -> Void
    private var remoteConnection: NWConnection?
    private var relay: MacOSShadowsocksRelay?

    init(connection: NWConnection, node: ProxyNode, credential: String, onClose: @escaping () -> Void) {
        self.connection = connection
        self.node = node
        self.credential = credential
        self.onClose = onClose
    }

    func start(on queue: DispatchQueue) {
        connection.start(queue: queue)
        readHeaders(buffer: Data(), on: queue)
    }

    private func readHeaders(buffer: Data, on queue: DispatchQueue) {
        if let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") {
            guard let destination = Self.parseConnectDestination(request) else {
                sendUnsupportedHTTPResponse()
                return
            }
            openTunnel(destination: destination, on: queue)
            return
        }
        guard buffer.count < 8_192 else {
            sendUnsupportedHTTPResponse()
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192 - buffer.count) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard error == nil, !isComplete, let data, !data.isEmpty else {
                self.close()
                return
            }
            var next = buffer
            next.append(data)
            self.readHeaders(buffer: next, on: queue)
        }
    }

    private func openTunnel(destination: ProxyDestination, on queue: DispatchQueue) {
        guard let serverPort = NWEndpoint.Port(rawValue: UInt16(node.serverPort)) else {
            sendUnsupportedHTTPResponse()
            return
        }
        let remote = NWConnection(host: NWEndpoint.Host(node.serverHost), port: serverPort, using: .tcp)
        remoteConnection = remote
        remote.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendHTTPShadowsocksOpen(destination: destination, remote: remote, on: queue)
            case .failed, .cancelled:
                self.close()
            case .setup, .preparing, .waiting:
                break
            @unknown default:
                self.close()
            }
        }
        remote.start(queue: queue)
    }

    private func sendHTTPShadowsocksOpen(destination: ProxyDestination, remote: NWConnection, on queue: DispatchQueue) {
        do {
            let salt = Self.randomSalt()
            let request = try ShadowsocksStreamRequest(credential: credential, destination: destination, salt: salt)
            let relay = try MacOSShadowsocksRelay(credential: credential, clientSalt: salt)
            self.relay = relay
            remote.send(content: request.openBytes, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil {
                    self.sendUnsupportedHTTPResponse()
                    return
                }
                self.connection.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { [weak self] error in
                    guard let self else { return }
                    if error != nil {
                        self.close()
                        return
                    }
                    relay.pipeLocalToRemote(local: self.connection, remote: remote)
                    relay.pipeRemoteToLocal(remote: remote, local: self.connection, on: queue)
                })
            })
        } catch {
            sendUnsupportedHTTPResponse()
        }
    }

    private func sendUnsupportedHTTPResponse() {
        let response = "HTTP/1.1 501 Not Implemented\r\nContent-Length: 62\r\nConnection: close\r\n\r\nHTTP proxy only supports CONNECT tunneling for Shadowsocks relay."
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    private func close() {
        connection.cancel()
        remoteConnection?.cancel()
        relay = nil
        onClose()
    }

    private static func parseConnectDestination(_ request: String) -> ProxyDestination? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0].uppercased() == "CONNECT" else { return nil }
        let hostPort = parts[1].split(separator: ":", maxSplits: 1)
        guard hostPort.count == 2, let port = Int(hostPort[1]), (1...65_535).contains(port) else { return nil }
        return .host(String(hostPort[0]), port: port)
    }

    private static func randomSalt() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) })
    }
}

private final class MacOSShadowsocksRelay {
    private let lock = NSLock()
    private let credential: String
    private var clientEncoder: ShadowsocksAEADStreamEncoder
    private var remoteDecoder: ShadowsocksAEADStreamDecoder?
    private var remoteBuffer = Data()

    init(credential: String, clientSalt: Data) throws {
        self.credential = credential
        self.clientEncoder = try ShadowsocksAEADStreamEncoder(credential: credential, salt: clientSalt, initialNonce: 2)
    }

    func pipeLocalToRemote(local: NWConnection, remote: NWConnection) {
        local.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let frame: Data
                do {
                    frame = try self.encryptLocal(data)
                } catch {
                    local.cancel()
                    remote.cancel()
                    return
                }
                remote.send(content: frame, completion: .contentProcessed { [weak self] sendError in
                    guard let self else { return }
                    if sendError != nil {
                        local.cancel()
                        remote.cancel()
                        return
                    }
                    self.pipeLocalToRemote(local: local, remote: remote)
                })
                return
            }
            if isComplete || error != nil {
                local.cancel()
                remote.cancel()
            } else {
                self.pipeLocalToRemote(local: local, remote: remote)
            }
        }
    }

    func pipeRemoteToLocal(remote: NWConnection, local: NWConnection, on queue: DispatchQueue) {
        remote.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let payloads: [Data]
                do {
                    payloads = try self.decryptRemote(data)
                } catch {
                    remote.cancel()
                    local.cancel()
                    return
                }
                self.send(payloads: payloads, to: local) { [weak self] success in
                    guard let self else { return }
                    if success {
                        self.pipeRemoteToLocal(remote: remote, local: local, on: queue)
                    } else {
                        remote.cancel()
                        local.cancel()
                    }
                }
                return
            }
            if isComplete || error != nil {
                remote.cancel()
                local.cancel()
            } else {
                self.pipeRemoteToLocal(remote: remote, local: local, on: queue)
            }
        }
    }

    private func encryptLocal(_ data: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        return try clientEncoder.encrypt(data)
    }

    private func decryptRemote(_ data: Data) throws -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        remoteBuffer.append(data)
        if remoteDecoder == nil {
            guard remoteBuffer.count >= 32 else { return [] }
            let salt = Data(remoteBuffer.prefix(32))
            remoteBuffer.removeFirst(32)
            remoteDecoder = try ShadowsocksAEADStreamDecoder(credential: credential, salt: salt)
        }
        guard var decoder = remoteDecoder else { return [] }
        let payloads = try decoder.appendAndDecryptAvailable(remoteBuffer)
        remoteBuffer.removeAll()
        remoteDecoder = decoder
        return payloads
    }

    private func send(payloads: [Data], to connection: NWConnection, completion: @escaping (Bool) -> Void) {
        guard let first = payloads.first else {
            completion(true)
            return
        }
        connection.send(content: first, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                completion(false)
                return
            }
            self.send(payloads: Array(payloads.dropFirst()), to: connection, completion: completion)
        })
    }
}
