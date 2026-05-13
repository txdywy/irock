import Darwin
import Foundation
import IrockAppFeature
import IrockCore
import IrockProtocols

final class MacOSLocalProxyController: LocalProxyControlling {
    private let listenerQueue = DispatchQueue(label: "dev.irock.macos-local-proxy.listeners")
    private let connectionQueue = DispatchQueue(label: "dev.irock.macos-local-proxy.connections", attributes: .concurrent)
    private let endpoint: LocalProxyEndpoint
    private let lock = NSLock()
    private var listenerSockets: [Int32] = []
    private var activeSockets: Set<Int32> = []

    init(endpoint: LocalProxyEndpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)) {
        self.endpoint = endpoint
    }

    func start(node: ProxyNode, credential: String) throws -> LocalProxyEndpoint {
        guard node.protocolType == .shadowsocks, node.transport == .tcp else {
            throw LocalProxyError.unavailable
        }
        stopListeners()
        let socks = try makeListenerSocket(port: endpoint.socksPort)
        let http = try makeListenerSocket(port: endpoint.httpPort)
        listenerSockets = [socks, http]
        startAcceptLoop(socket: socks) { [weak self] client in
            self?.handleSOCKS(client: client, node: node, credential: credential)
        }
        startAcceptLoop(socket: http) { [weak self] client in
            self?.handleHTTP(client: client, node: node, credential: credential)
        }
        return endpoint
    }

    func stop() throws {
        stopListeners()
    }

    private func makeListenerSocket(port: Int) throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw LocalProxyError.unavailable }

        var reuse: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse))) == 0 else {
            Darwin.close(fd)
            throw LocalProxyError.unavailable
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(endpoint.host))

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, SOMAXCONN) == 0 else {
            Darwin.close(fd)
            throw LocalProxyError.unavailable
        }
        return fd
    }

    private func startAcceptLoop(socket: Int32, handler: @escaping (Int32) -> Void) {
        listenerQueue.async { [weak self] in
            guard let self else { return }
            while true {
                let client = Darwin.accept(socket, nil, nil)
                if client < 0 {
                    if errno == EBADF || errno == EINVAL {
                        break
                    }
                    continue
                }
                self.track(client)
                self.connectionQueue.async { [weak self] in
                    guard let self else { return }
                    handler(client)
                    self.closeTrackedSocket(client)
                }
            }
        }
    }

    private func handleSOCKS(client: Int32, node: ProxyNode, credential: String) {
        do {
            let greetingHeader = try readExact(2, from: client)
            guard greetingHeader[0] == 0x05, greetingHeader[1] > 0 else { return }
            let methods = try readExact(Int(greetingHeader[1]), from: client)
            guard methods.contains(0x00) else {
                try writeAll(Data([0x05, 0xff]), to: client)
                return
            }
            try writeAll(Data([0x05, 0x00]), to: client)

            let header = try readExact(4, from: client)
            guard header[0] == 0x05, header[1] == 0x01 else {
                try sendSOCKSFailure(to: client)
                return
            }
            let destination = try readSOCKSDestination(atyp: header[3], from: client)
            try openOutboundAndRelay(client: client, destination: destination, node: node, credential: credential) {
                try self.writeAll(Data([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]), to: client)
            }
        } catch {
            try? sendSOCKSFailure(to: client)
        }
    }

    private func readSOCKSDestination(atyp: UInt8, from client: Int32) throws -> ProxyDestination {
        switch atyp {
        case 0x01:
            let bytes = try readExact(6, from: client)
            let host = bytes[0..<4].map(String.init).joined(separator: ".")
            return .ipv4(host, port: port(from: bytes, at: 4))
        case 0x03:
            let length = Int(try readExact(1, from: client)[0])
            let bytes = try readExact(length + 2, from: client)
            guard let host = String(data: Data(bytes[0..<length]), encoding: .utf8) else {
                throw LocalProxyError.unavailable
            }
            return .host(host, port: port(from: bytes, at: length))
        case 0x04:
            let bytes = try readExact(18, from: client)
            let groups = stride(from: 0, to: 16, by: 2).map { String(format: "%02x%02x", bytes[$0], bytes[$0 + 1]) }
            return .ipv6(groups.joined(separator: ":"), port: port(from: bytes, at: 16))
        default:
            throw LocalProxyError.unavailable
        }
    }

    private func handleHTTP(client: Int32, node: ProxyNode, credential: String) {
        do {
            let request = try readHTTPHeaders(from: client)
            guard let destination = Self.parseConnectDestination(request) else {
                try sendUnsupportedHTTPResponse(to: client)
                return
            }
            try openOutboundAndRelay(client: client, destination: destination, node: node, credential: credential) {
                try self.writeAll(Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), to: client)
            }
        } catch {
            try? sendUnsupportedHTTPResponse(to: client)
        }
    }

    private func readHTTPHeaders(from client: Int32) throws -> String {
        var buffer = Data()
        while buffer.count < 8_192 {
            guard let chunk = try readAvailable(from: client, maxLength: 1024) else { break }
            buffer.append(chunk)
            if let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") {
                return request
            }
        }
        throw LocalProxyError.unavailable
    }

    private func openOutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, sendSuccess: () throws -> Void) throws {
        switch node.protocolType {
        case .shadowsocks:
            try openShadowsocksOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, sendSuccess: sendSuccess)
        default:
            throw LocalProxyError.unavailable
        }
    }

    private func openShadowsocksOutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, sendSuccess: () throws -> Void) throws {
        let remote = try connectRemote(host: node.serverHost, port: node.serverPort)
        track(remote)
        defer { closeTrackedSocket(remote) }
        let clientSalt = try sendShadowsocksOpen(destination: destination, remote: remote, credential: credential)
        try sendSuccess()
        relay(local: client, remote: remote, credential: credential, clientSalt: clientSalt)
    }

    private func sendShadowsocksOpen(destination: ProxyDestination, remote: Int32, credential: String) throws -> Data {
        let salt = Self.randomSalt(byteCount: try ShadowsocksStreamRequest.saltLength(forCredential: credential))
        let request = try ShadowsocksStreamRequest(credential: credential, destination: destination, salt: salt)
        try writeAll(request.openBytes, to: remote)
        return salt
    }

    private func relay(local: Int32, remote: Int32, credential: String, clientSalt: Data) {
        let group = DispatchGroup()
        group.enter()
        connectionQueue.async {
            self.relayLocalToRemote(local: local, remote: remote, credential: credential, clientSalt: clientSalt)
            group.leave()
        }
        group.enter()
        connectionQueue.async {
            self.relayRemoteToLocal(remote: remote, local: local, credential: credential, clientSalt: clientSalt)
            group.leave()
        }
        group.wait()
    }

    private func relayLocalToRemote(local: Int32, remote: Int32, credential: String, clientSalt: Data) {
        do {
            var encoder = try ShadowsocksAEADStreamEncoder(credential: credential, salt: clientSalt, initialNonce: 2)
            while let payload = try readAvailable(from: local, maxLength: 16_384) {
                let frame = try encoder.encrypt(payload)
                try writeAll(frame, to: remote)
            }
        } catch {}
        shutdown(remote, SHUT_WR)
    }

    private func relayRemoteToLocal(remote: Int32, local: Int32, credential: String, clientSalt: Data) {
        do {
            var remoteBuffer = Data()
            var decoder: ShadowsocksAEADStreamDecoder?
            while let chunk = try readAvailable(from: remote, maxLength: 16_384) {
                remoteBuffer.append(chunk)
                if decoder == nil {
                    let saltLength = try ShadowsocksStreamRequest.saltLength(forCredential: credential)
                    guard remoteBuffer.count >= saltLength else { continue }
                    let salt = Data(remoteBuffer.prefix(saltLength))
                    remoteBuffer.removeFirst(saltLength)
                    decoder = try ShadowsocksAEADStreamDecoder(credential: credential, salt: salt, requestSalt: clientSalt)
                }
                guard var activeDecoder = decoder else { continue }
                let payloads = try activeDecoder.appendAndDecryptAvailable(remoteBuffer)
                remoteBuffer.removeAll()
                decoder = activeDecoder
                for payload in payloads {
                    try writeAll(payload, to: local)
                }
            }
        } catch {}
        shutdown(local, SHUT_WR)
    }

    private func connectRemote(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else {
            throw LocalProxyError.unavailable
        }
        defer { freeaddrinfo(result) }

        var pointer: UnsafeMutablePointer<addrinfo>? = first
        while let current = pointer {
            let fd = Darwin.socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            if fd >= 0 {
                if Darwin.connect(fd, current.pointee.ai_addr, current.pointee.ai_addrlen) == 0 {
                    return fd
                }
                Darwin.close(fd)
            }
            pointer = current.pointee.ai_next
        }
        throw LocalProxyError.unavailable
    }

    private func readExact(_ count: Int, from fd: Int32) throws -> [UInt8] {
        var data = Data()
        while data.count < count {
            guard let chunk = try readAvailable(from: fd, maxLength: count - data.count) else {
                throw LocalProxyError.unavailable
            }
            data.append(chunk)
        }
        return Array(data)
    }

    private func readAvailable(from fd: Int32, maxLength: Int) throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: maxLength)
        let received = Darwin.read(fd, &buffer, maxLength)
        if received > 0 {
            return Data(buffer.prefix(received))
        }
        if received == 0 {
            return nil
        }
        throw LocalProxyError.unavailable
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < data.count {
                let result = Darwin.write(fd, baseAddress.advanced(by: written), data.count - written)
                if result <= 0 {
                    throw LocalProxyError.unavailable
                }
                written += result
            }
        }
    }

    private func sendSOCKSFailure(to client: Int32) throws {
        try writeAll(Data([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]), to: client)
    }

    private func sendUnsupportedHTTPResponse(to client: Int32) throws {
        let response = "HTTP/1.1 501 Not Implemented\r\nContent-Length: 62\r\nConnection: close\r\n\r\nHTTP proxy only supports CONNECT tunneling for Shadowsocks relay."
        try writeAll(Data(response.utf8), to: client)
    }

    private func track(_ socket: Int32) {
        lock.lock()
        activeSockets.insert(socket)
        lock.unlock()
    }

    private func closeTrackedSocket(_ socket: Int32) {
        lock.lock()
        let removed = activeSockets.remove(socket) != nil
        lock.unlock()
        if removed {
            Darwin.close(socket)
        }
    }

    private func stopListeners() {
        lock.lock()
        let listeners = listenerSockets
        let sockets = activeSockets
        listenerSockets.removeAll()
        activeSockets.removeAll()
        lock.unlock()
        for socket in listeners + Array(sockets) {
            Darwin.close(socket)
        }
    }

    private func port(from bytes: [UInt8], at index: Int) -> Int {
        Int(bytes[index]) << 8 | Int(bytes[index + 1])
    }

    private static func parseConnectDestination(_ request: String) -> ProxyDestination? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0].uppercased() == "CONNECT" else { return nil }
        let hostPort = parts[1].split(separator: ":", maxSplits: 1)
        guard hostPort.count == 2, let port = Int(hostPort[1]), (1...65_535).contains(port) else { return nil }
        return .host(String(hostPort[0]), port: port)
    }

    private static func randomSalt(byteCount: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<byteCount).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) })
    }
}
