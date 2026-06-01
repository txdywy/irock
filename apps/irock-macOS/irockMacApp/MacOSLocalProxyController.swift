import Darwin
import Foundation
import IrockAppFeature
import IrockCore
import IrockNativeHysteria2
import IrockProtocols
import IrockTransport

private final class AsyncResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

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

    func sendDatagram(_ payload: Data) async throws -> Data? {
        try await session.sendDatagram(payload)
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

final class MacOSLocalProxyController: LocalProxyControlling {
    private let socksListenerQueue = DispatchQueue(label: "dev.irock.macos-local-proxy.socks-listener")
    private let httpListenerQueue = DispatchQueue(label: "dev.irock.macos-local-proxy.http-listener")
    private let connectionQueue = DispatchQueue(label: "dev.irock.macos-local-proxy.connections", attributes: .concurrent)
    private let endpoint: LocalProxyEndpoint
    private let lock = NSLock()
    private var listenerSockets: [Int32] = []
    private var activeSockets: Set<Int32> = []

    init(endpoint: LocalProxyEndpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)) {
        signal(SIGPIPE, SIG_IGN)
        self.endpoint = endpoint
    }

    func start(node: ProxyNode, credential: String, realmCredential: String?) throws -> LocalProxyEndpoint {
        guard Self.isSupportedLocalProxyNode(node) else {
            throw LocalProxyError.unavailable
        }
        stopListeners()
        let socks = try makeListenerSocket(port: endpoint.socksPort)
        let http = try makeListenerSocket(port: endpoint.httpPort)
        listenerSockets = [socks, http]
        startAcceptLoop(socket: socks, queue: socksListenerQueue) { [weak self] client in
            self?.handleSOCKS(client: client, node: node, credential: credential, realmCredential: realmCredential)
        }
        startAcceptLoop(socket: http, queue: httpListenerQueue) { [weak self] client in
            self?.handleHTTP(client: client, node: node, credential: credential, realmCredential: realmCredential)
        }
        return endpoint
    }

    func stop() throws {
        stopListeners()
    }

    private static func isSupportedLocalProxyNode(_ node: ProxyNode) -> Bool {
        switch node.protocolType {
        case .shadowsocks:
            return node.transport == .tcp
        case .hysteria2:
            return node.transport == .quic
        case .tuic:
            return node.transport == .quic
                && node.tls.enabled
        case .trustTunnel:
            return node.transport == .http2
                && node.tls.enabled
        case .trojan:
            return node.transport == .tcp
        case .vmess:
            return (node.transport == .tcp || node.transport == .webSocket || node.transport == .http2 || node.transport == .grpc)
                && node.tls.enabled
                && node.tls.fingerprint == nil
                && node.tls.reality == nil
        case .vless:
            return node.transport == .tcp
                && node.tls.enabled
                && node.tls.fingerprint == nil
                && node.tls.reality == nil
        default:
            return false
        }
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

    private func startAcceptLoop(socket: Int32, queue: DispatchQueue, handler: @escaping (Int32) -> Void) {
        queue.async { [weak self] in
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

    private func handleSOCKS(client: Int32, node: ProxyNode, credential: String, realmCredential: String?) {
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
            try openOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, realmCredential: realmCredential) {
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

    private func handleHTTP(client: Int32, node: ProxyNode, credential: String, realmCredential: String?) {
        do {
            let request = try readHTTPHeaders(from: client)
            guard let destination = Self.parseConnectDestination(request) else {
                try sendUnsupportedHTTPResponse(to: client)
                return
            }
            try openOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, realmCredential: realmCredential) {
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

    private func openOutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, realmCredential: String?, sendSuccess: () throws -> Void) throws {
        switch node.protocolType {
        case .shadowsocks:
            try openShadowsocksOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, sendSuccess: sendSuccess)
        case .trojan:
            try openTrojanOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, sendSuccess: sendSuccess)
        case .vmess:
            try openVMessOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, sendSuccess: sendSuccess)
        case .vless:
            try openVLESSOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, sendSuccess: sendSuccess)
        case .hysteria2:
            try openHysteria2OutboundAndRelay(client: client, destination: destination, node: node, credential: credential, realmCredential: realmCredential, sendSuccess: sendSuccess)
        case .tuic:
            try openTUICOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, sendSuccess: sendSuccess)
        case .trustTunnel:
            try openTrustTunnelOutboundAndRelay(client: client, destination: destination, node: node, credential: credential, sendSuccess: sendSuccess)
        default:
            throw LocalProxyError.unavailable
        }
    }

    private func openTrustTunnelOutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, sendSuccess: () throws -> Void) throws {
        let tlsStream = try MacOSTLSByteStream(host: node.serverHost, port: node.serverPort, tls: h2TLSOptions(from: node.tls), initialPayload: nil)
        let stream = HTTP2ClientByteStream(
            underlying: tlsStream,
            authority: authority(for: destination),
            path: "/",
            method: "CONNECT",
            additionalHeaders: [
                ("user-agent", "irock trusttunnel"),
                ("proxy-authorization", "Basic \(Data(credential.utf8).base64EncodedString())")
            ],
            initialPayload: nil
        )
        try runAsync { try await tlsStream.start() }
        do {
            try runAsync { try await stream.start() }
            try runAsync { try await stream.waitForResponseHeaders() }
            try sendSuccess()
            relay(local: client, stream: stream)
        } catch {
            try? runAsync { await stream.close() }
            throw error
        }
    }

    private func openTUICOutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, sendSuccess: () throws -> Void) throws {
        let stream = try runAsync {
            try await TUICStreamOpener(sessionDialer: NativeTUICQUICSessionDialer()).openStream(
                node: node,
                credential: credential,
                destination: destination,
                metadata: ["source": "macos-local-proxy"]
            )
        }
        do {
            try sendSuccess()
            relay(local: client, stream: stream)
        } catch {
            try? runAsync { await stream.close() }
            throw error
        }
    }

    private func openHysteria2OutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, realmCredential: String?, sendSuccess: () throws -> Void) throws {
        let connectedUDPPath = try realmCredential.flatMap { credential in
            try node.hysteria2?.realm.map { realm in
                try runAsync {
                    let configuration = try Self.nativeRealmConfiguration(for: realm, credential: credential)
                    return try await NativeHysteria2RealmResolver(configuration: configuration).resolve(configuration: configuration)
                }
            }
        } ?? nil
        let configuration = try NativeHysteria2ClientConfiguration(
            serverHost: node.serverHost,
            serverPort: node.serverPort,
            serverName: node.tls.serverName,
            alpn: node.tls.alpn.isEmpty ? ["h3"] : node.tls.alpn,
            allowInsecure: node.tls.allowInsecure,
            certificatePinSHA256: node.tls.fingerprint,
            connectedUDPPath: connectedUDPPath
        )
        let nativeClient = NativeHysteria2Client(configuration: configuration)
        let stream = try runAsync {
            let session = try await nativeClient.connect(authentication: credential)
            return try await session.openTCPStream(address: Self.hysteria2AddressString(for: destination))
        }
        let transportStream = NativeTransportByteStream(stream: stream)
        do {
            try sendSuccess()
            relay(local: client, stream: transportStream)
        } catch {
            try? runAsync { await transportStream.close() }
            throw error
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

    private func openTrojanOutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, sendSuccess: () throws -> Void) throws {
        let serverName = node.tls.serverName ?? node.serverHost
        let request = try TrojanOpenRequest(password: credential, destination: destination, serverName: serverName)
        let tls = TLSOptions(
            enabled: true,
            serverName: serverName,
            allowInsecure: node.tls.allowInsecure,
            alpn: node.tls.alpn,
            fingerprint: node.tls.fingerprint,
            reality: node.tls.reality
        )
        try openTLSOutboundAndRelay(client: client, node: node, tls: tls, initialPayload: request.openBytes, sendSuccess: sendSuccess)
    }

    private func openVLESSOutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, sendSuccess: () throws -> Void) throws {
        let serverName = node.tls.serverName ?? node.serverHost
        let request = try VLESSOpenRequest(userID: credential, destination: destination)
        let tls = TLSOptions(
            enabled: true,
            serverName: serverName,
            allowInsecure: node.tls.allowInsecure,
            alpn: node.tls.alpn,
            fingerprint: node.tls.fingerprint,
            reality: node.tls.reality
        )
        try openTLSOutboundAndRelay(client: client, node: node, tls: tls, initialPayload: request.openBytes, sendSuccess: sendSuccess)
    }

    private func openVMessOutboundAndRelay(client: Int32, destination: ProxyDestination, node: ProxyNode, credential: String, sendSuccess: () throws -> Void) throws {
        let serverName = node.tls.serverName ?? node.serverHost
        let request = try VMessOpenRequest(userID: credential, destination: destination)
        let tls = TLSOptions(
            enabled: true,
            serverName: serverName,
            allowInsecure: node.tls.allowInsecure,
            alpn: node.tls.alpn,
            fingerprint: node.tls.fingerprint,
            reality: node.tls.reality
        )
        switch node.transport {
        case .webSocket:
            try openWebSocketTLSOutboundAndRelay(client: client, node: node, tls: tls, initialPayload: request.openBytes, sendSuccess: sendSuccess)
        case .http2:
            try openHTTP2TLSOutboundAndRelay(client: client, node: node, tls: tls, initialPayload: request.openBytes, sendSuccess: sendSuccess)
        case .grpc:
            try openGRPCTLSOutboundAndRelay(client: client, node: node, tls: tls, initialPayload: request.openBytes, sendSuccess: sendSuccess)
        default:
            try openTLSOutboundAndRelay(client: client, node: node, tls: tls, initialPayload: request.openBytes, sendSuccess: sendSuccess)
        }
    }

    private func openWebSocketTLSOutboundAndRelay(client: Int32, node: ProxyNode, tls: TLSOptions, initialPayload: Data, sendSuccess: () throws -> Void) throws {
        guard let options = node.transportOptions.webSocket else {
            throw TransportError.invalidConfiguration("missing websocket options")
        }
        let tlsStream = try MacOSTLSByteStream(host: node.serverHost, port: node.serverPort, tls: tls, initialPayload: nil)
        let stream = WebSocketClientByteStream(
            underlying: tlsStream,
            host: options.host ?? node.serverHost,
            path: options.path,
            protocolName: "vmess",
            initialPayload: initialPayload
        )
        try runAsync { try await tlsStream.start() }
        try runAsync { try await stream.start() }
        do {
            try sendSuccess()
            relay(local: client, stream: stream)
        } catch {
            try? runAsync { await stream.close() }
            throw error
        }
    }

    private func openHTTP2TLSOutboundAndRelay(client: Int32, node: ProxyNode, tls: TLSOptions, initialPayload: Data, sendSuccess: () throws -> Void) throws {
        guard let options = node.transportOptions.http2 else {
            throw TransportError.invalidConfiguration("missing http2 options")
        }
        let tlsStream = try MacOSTLSByteStream(host: node.serverHost, port: node.serverPort, tls: h2TLSOptions(from: tls), initialPayload: nil)
        let stream = HTTP2ClientByteStream(
            underlying: tlsStream,
            authority: options.authority ?? node.tls.serverName ?? node.serverHost,
            path: options.path,
            initialPayload: initialPayload
        )
        try runAsync { try await tlsStream.start() }
        do {
            try runAsync { try await stream.start() }
            try runAsync { try await stream.waitForResponseHeaders() }
            try sendSuccess()
            relay(local: client, stream: stream)
        } catch {
            try? runAsync { await stream.close() }
            throw error
        }
    }

    private func openGRPCTLSOutboundAndRelay(client: Int32, node: ProxyNode, tls: TLSOptions, initialPayload: Data, sendSuccess: () throws -> Void) throws {
        guard let options = node.transportOptions.grpc else {
            throw TransportError.invalidConfiguration("missing grpc options")
        }
        let tlsStream = try MacOSTLSByteStream(host: node.serverHost, port: node.serverPort, tls: h2TLSOptions(from: tls), initialPayload: nil)
        let stream = GRPCClientByteStream(
            underlying: tlsStream,
            authority: options.authority ?? node.tls.serverName ?? node.serverHost,
            service: options.service,
            initialPayload: initialPayload
        )
        try runAsync { try await tlsStream.start() }
        do {
            try runAsync { try await stream.start() }
            try runAsync { try await stream.waitForResponseHeaders() }
            try sendSuccess()
            relay(local: client, stream: stream)
        } catch {
            try? runAsync { await stream.close() }
            throw error
        }
    }

    private func authority(for destination: ProxyDestination) -> String {
        switch destination {
        case .host(let host, let port): return "\(host):\(port)"
        case .ipv4(let address, let port): return "\(address):\(port)"
        case .ipv6(let address, let port): return "[\(address)]:\(port)"
        }
    }

    private func h2TLSOptions(from tls: TLSOptions) -> TLSOptions {
        TLSOptions(
            enabled: true,
            serverName: tls.serverName,
            allowInsecure: tls.allowInsecure,
            alpn: ["h2"] + tls.alpn.filter { $0 != "h2" },
            fingerprint: tls.fingerprint,
            reality: tls.reality
        )
    }

    private func openTLSOutboundAndRelay(client: Int32, node: ProxyNode, tls: TLSOptions, initialPayload: Data, sendSuccess: () throws -> Void) throws {
        let stream = try MacOSTLSByteStream(host: node.serverHost, port: node.serverPort, tls: tls, initialPayload: initialPayload)
        try runAsync { try await stream.start() }
        do {
            try sendSuccess()
            relay(local: client, stream: stream)
        } catch {
            try? runAsync { await stream.close() }
            throw error
        }
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

    private func relay(local: Int32, stream: any TransportByteStream) {
        let group = DispatchGroup()
        group.enter()
        connectionQueue.async {
            self.relayLocalToStream(local: local, stream: stream)
            group.leave()
        }
        group.enter()
        connectionQueue.async {
            self.relayStreamToLocal(stream: stream, local: local)
            group.leave()
        }
        group.wait()
        try? runAsync { await stream.close() }
    }

    private func relayLocalToStream(local: Int32, stream: any TransportByteStream) {
        do {
            while let payload = try readAvailable(from: local, maxLength: 16_384) {
                try runAsync { try await stream.write(payload) }
            }
            try runAsync { await stream.closeWrite() }
        } catch {}
    }

    private func relayStreamToLocal(stream: any TransportByteStream, local: Int32) {
        do {
            while let payload = try runAsync({ try await stream.read(maxLength: 16_384) }) {
                try writeAll(payload, to: local)
            }
        } catch {}
        shutdown(local, SHUT_WR)
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

    private func runAsync<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = AsyncResultBox<T>()
        Task.detached {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
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
        let body = "HTTP proxy only supports CONNECT tunneling for supported local proxy protocols."
        let response = "HTTP/1.1 501 Not Implemented\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
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

    private static func hysteria2AddressString(for destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port), let .ipv4(host, port):
            return "\(host):\(port)"
        case let .ipv6(address, port):
            return "[\(address)]:\(port)"
        }
    }

    private static func nativeRealmConfiguration(for realm: Hysteria2RealmOptions, credential: String) throws -> NativeHysteria2RealmConfiguration {
        let scheme = realm.useTLS ? "https" : "http"
        var components = URLComponents()
        components.scheme = scheme
        components.host = realm.rendezvousHost
        components.port = realm.rendezvousPort
        guard let baseURL = components.url else {
            throw LocalProxyError.unavailable
        }
        let stunServers = realm.stunServers.isEmpty ? ["stun.nextcloud.com:3478", "stun.sip.us:3478", "global.stun.twilio.com:3478"] : realm.stunServers
        return try NativeHysteria2RealmConfiguration(
            rendezvousBaseURL: baseURL,
            realmID: realm.name,
            token: credential,
            stunServers: stunServers,
            localPort: realm.localPort
        )
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
