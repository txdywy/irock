import Foundation
import IrockCore
import IrockTransport

public struct Hysteria2AuthRequest: Equatable, Sendable {
    public let path: String
    public let method: String
    public let headers: [String: String]

    public var metadata: [String: String] {
        [
            "hysteria2AuthPresent": "true",
            "hysteria2AuthMethod": "http3-post"
        ]
    }

    public init(authentication: String, receiveMbps: Int = 100, padding: String? = nil) throws {
        let trimmedAuthentication = authentication.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthentication.isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing hysteria2 authentication")
        }
        self.path = "/auth"
        self.method = "POST"
        var headers = [
            "Hysteria-Auth": trimmedAuthentication,
            "Hysteria-CC-RX": String(max(1, receiveMbps))
        ]
        if let padding, !padding.isEmpty {
            headers["Hysteria-Padding"] = padding
        }
        self.headers = headers
    }
}

public struct Hysteria2OpenRequest: Equatable, Sendable {
    public let destinationDescription: String
    public let sni: String
    public let obfuscationPresent: Bool
    public let openBytes: Data

    public var metadata: [String: String] {
        [
            "hysteria2AuthPresent": "true",
            "hysteria2Destination": destinationDescription,
            "hysteria2SNI": sni,
            "hysteria2ObfsPresent": obfuscationPresent ? "true" : "false",
            "hysteria2TCPCommand": "connect"
        ]
    }

    public init(authentication: String, destination: ProxyDestination, sni: String = "", obfuscation: String? = nil) throws {
        guard !authentication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing hysteria2 authentication")
        }
        let trimmedSNI = sni.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = Self.addressString(for: destination)
        self.destinationDescription = Self.destinationDescription(destination)
        self.sni = trimmedSNI
        self.obfuscationPresent = obfuscation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        var bytes = Self.encodeQUICVariableInteger(0x401)
        bytes.append(Self.encodeQUICVariableInteger(UInt64(address.utf8.count)))
        bytes.append(Data(address.utf8))
        bytes.append(Self.encodeQUICVariableInteger(0))
        self.openBytes = bytes
    }

    private static func addressString(for destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port), let .ipv4(host, port):
            return "\(host):\(port)"
        case let .ipv6(address, port):
            return "[\(address)]:\(port)"
        }
    }

    private static func destinationDescription(_ destination: ProxyDestination) -> String {
        switch destination {
        case let .host(host, port):
            return "host:\(host):\(port)"
        case let .ipv4(address, port):
            return "ipv4:\(address):\(port)"
        case let .ipv6(address, port):
            return "ipv6:\(address):\(port)"
        }
    }

    private static func encodeQUICVariableInteger(_ value: UInt64) -> Data {
        if value < 0x40 {
            return Data([UInt8(value)])
        }
        if value < 0x4000 {
            let encoded = UInt16(value) | 0x4000
            return Data([UInt8(encoded >> 8), UInt8(encoded & 0xff)])
        }
        if value < 0x4000_0000 {
            let encoded = UInt32(value) | 0x8000_0000
            return Data([
                UInt8((encoded >> 24) & 0xff),
                UInt8((encoded >> 16) & 0xff),
                UInt8((encoded >> 8) & 0xff),
                UInt8(encoded & 0xff)
            ])
        }
        let encoded = value | 0xc000_0000_0000_0000
        return Data([
            UInt8((encoded >> 56) & 0xff),
            UInt8((encoded >> 48) & 0xff),
            UInt8((encoded >> 40) & 0xff),
            UInt8((encoded >> 32) & 0xff),
            UInt8((encoded >> 24) & 0xff),
            UInt8((encoded >> 16) & 0xff),
            UInt8((encoded >> 8) & 0xff),
            UInt8(encoded & 0xff)
        ])
    }
}

public struct Hysteria2StreamOpener<Dialer: QUICStreamDialer>: Sendable {
    private let streamAdapter: QUICStreamTransportAdapter<Dialer>

    public init(streamAdapter: QUICStreamTransportAdapter<Dialer>) {
        self.streamAdapter = streamAdapter
    }

    public func openStream(node: ProxyNode, credential: String, destination: ProxyDestination, metadata: [String: String] = [:]) async throws -> any TransportByteStream {
        try validate(node)
        let authRequest = try Hysteria2AuthRequest(authentication: credential)
        let openRequest = try Hysteria2OpenRequest(
            authentication: credential,
            destination: destination,
            sni: node.tls.serverName ?? node.serverHost
        )
        var requestMetadata = metadata
        requestMetadata["proxyProtocol"] = node.protocolType.rawValue
        requestMetadata["quicServerName"] = node.tls.serverName ?? node.serverHost
        requestMetadata["quicProtocol"] = "hysteria2"
        requestMetadata["quicALPN"] = node.tls.alpn.isEmpty ? "h3" : node.tls.alpn.joined(separator: ",")
        requestMetadata["quicHandshake"] = "native"
        for (key, value) in authRequest.metadata {
            requestMetadata[key] = value
        }
        for (key, value) in openRequest.metadata {
            requestMetadata[key] = value
        }
        let request = TransportRequest(
            host: node.serverHost,
            port: node.serverPort,
            transport: node.transport,
            tls: node.tls.enabled ? node.tls : nil,
            metadata: requestMetadata,
            initialPayload: openRequest.openBytes
        )
        do {
            let stream = try await streamAdapter.openStream(request: request)
            try await validateTCPResponse(from: stream)
            return stream
        } catch let error as TransportError {
            throw mapTransportErrorToProxyProtocolError(error)
        }
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .hysteria2 else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard node.transport == .quic else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing hysteria2 server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid hysteria2 server port")
        }
    }

    private func validateTCPResponse(from stream: any TransportByteStream) async throws {
        let status = try await readTCPResponseBytes(1, from: stream)[0]
        let messageLength = Int(try await readQUICVariableInteger(from: stream))
        _ = try await readTCPResponseBytes(messageLength, from: stream)
        let paddingLength = Int(try await readQUICVariableInteger(from: stream))
        _ = try await readTCPResponseBytes(paddingLength, from: stream)
        guard status == 0x00 else {
            throw ProxyProtocolError.remoteClosed
        }
    }

    private func readTCPResponseBytes(_ count: Int, from stream: any TransportByteStream) async throws -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try await stream.read(maxLength: count - data.count), !chunk.isEmpty else {
                throw ProxyProtocolError.remoteClosed
            }
            data.append(chunk)
        }
        return data
    }

    private func readQUICVariableInteger(from stream: any TransportByteStream) async throws -> UInt64 {
        let first = try await readTCPResponseBytes(1, from: stream)[0]
        let prefix = first >> 6
        let byteCount: Int
        switch prefix {
        case 0: byteCount = 1
        case 1: byteCount = 2
        case 2: byteCount = 4
        default: byteCount = 8
        }
        var bytes = Data([first])
        if byteCount > 1 {
            bytes.append(try await readTCPResponseBytes(byteCount - 1, from: stream))
        }
        var value = UInt64(bytes[0] & 0x3f)
        for byte in bytes.dropFirst() {
            value = (value << 8) | UInt64(byte)
        }
        return value
    }
}
