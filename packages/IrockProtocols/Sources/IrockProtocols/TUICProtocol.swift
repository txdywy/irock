import Foundation
import IrockCore
import IrockTransport

public protocol TUICQUICSession: Sendable {
    func exportKeyingMaterial(label: Data, context: Data, length: Int) async throws -> Data
    func openUnidirectionalStream(initialPayload: Data) async throws -> any TransportByteStream
    func openBidirectionalStream(initialPayload: Data) async throws -> any TransportByteStream
    func sendDatagram(_ payload: Data) async throws -> Data?
}

public protocol TUICQUICSessionDialer: Sendable {
    func openSession(host: String, port: Int, tls: TLSOptions?, metadata: [String: String]) async throws -> any TUICQUICSession
}

public struct TUICAuthenticateCommand: Equatable, Sendable {
    public let bytes: Data

    public var metadata: [String: String] {
        [
            "tuicUUIDPresent": "true",
            "tuicPasswordPresent": "true"
        ]
    }

    public init(credential: String, exportedToken: Data) throws {
        let uuid = try TUICCredentialParser.uuidBytes(from: credential)
        guard exportedToken.count == 32 else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic exported token")
        }
        var bytes = Data([0x05, 0x00])
        bytes.append(contentsOf: uuid)
        bytes.append(exportedToken)
        self.bytes = bytes
    }
}

public struct TUICConnectCommand: Equatable, Sendable {
    public let destinationDescription: String
    public let bytes: Data

    public var metadata: [String: String] {
        ["tuicDestination": destinationDescription]
    }

    public init(destination: ProxyDestination) throws {
        let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x00, ipv4Type: 0x01, ipv6Type: 0x02)
        self.destinationDescription = frame.description
        var bytes = Data([0x05, 0x01])
        bytes.append(frame.bytes)
        self.bytes = bytes
    }
}

public struct TUICPacketCommand: Equatable, Sendable {
    public let associationID: UInt16
    public let packetID: UInt16
    public let destination: ProxyDestination
    public let payload: Data
    public let bytes: Data

    public var metadata: [String: String] {
        [
            "tuicAssociationID": "\(associationID)",
            "tuicPacketID": "\(packetID)"
        ]
    }

    public init(associationID: UInt16, packetID: UInt16, destination: ProxyDestination, payload: Data) throws {
        let addressFrame = try ProtocolAddressFrame(destination: destination, domainType: 0x00, ipv4Type: 0x01, ipv6Type: 0x02)
        guard payload.count <= Int(UInt16.max) else {
            throw ProxyProtocolError.invalidConfiguration("tuic udp packet too large")
        }
        self.associationID = associationID
        self.packetID = packetID
        self.destination = destination
        self.payload = payload
        var bytes = Data([0x05, 0x02])
        bytes.append(Self.uint16Bytes(associationID))
        bytes.append(Self.uint16Bytes(packetID))
        bytes.append(contentsOf: [0x01, 0x00])
        bytes.append(Self.uint16Bytes(UInt16(payload.count)))
        bytes.append(addressFrame.bytes)
        bytes.append(payload)
        self.bytes = bytes
    }

    private init(associationID: UInt16, packetID: UInt16, destination: ProxyDestination, payload: Data, bytes: Data) {
        self.associationID = associationID
        self.packetID = packetID
        self.destination = destination
        self.payload = payload
        self.bytes = bytes
    }

    public static func parse(_ bytes: Data) throws -> TUICPacketCommand {
        guard bytes.count >= 10, bytes[0] == 0x05, bytes[1] == 0x02 else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic udp packet")
        }
        let associationID = readUInt16(bytes, at: 2)
        let packetID = readUInt16(bytes, at: 4)
        guard bytes[6] == 0x01, bytes[7] == 0x00 else {
            throw ProxyProtocolError.invalidConfiguration("unsupported tuic udp fragment")
        }
        let payloadSize = Int(readUInt16(bytes, at: 8))
        var offset = 10
        let destination = try readDestination(bytes, offset: &offset)
        guard bytes.count == offset + payloadSize else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic udp packet length")
        }
        return TUICPacketCommand(
            associationID: associationID,
            packetID: packetID,
            destination: destination,
            payload: bytes.subdata(in: offset..<bytes.count),
            bytes: bytes
        )
    }

    private static func readDestination(_ bytes: Data, offset: inout Int) throws -> ProxyDestination {
        guard offset < bytes.count else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic udp address")
        }
        let type = bytes[offset]
        offset += 1
        switch type {
        case 0x00:
            guard offset < bytes.count else {
                throw ProxyProtocolError.invalidConfiguration("invalid tuic udp domain")
            }
            let length = Int(bytes[offset])
            offset += 1
            guard bytes.count >= offset + length + 2 else {
                throw ProxyProtocolError.invalidConfiguration("invalid tuic udp domain")
            }
            let host = String(decoding: bytes.subdata(in: offset..<(offset + length)), as: UTF8.self)
            offset += length
            let port = Int(readUInt16(bytes, at: offset))
            offset += 2
            return .host(host, port: port)
        case 0x01:
            guard bytes.count >= offset + 6 else {
                throw ProxyProtocolError.invalidConfiguration("invalid tuic udp ipv4")
            }
            let address = "\(bytes[offset]).\(bytes[offset + 1]).\(bytes[offset + 2]).\(bytes[offset + 3])"
            offset += 4
            let port = Int(readUInt16(bytes, at: offset))
            offset += 2
            return .ipv4(address, port: port)
        case 0x02:
            guard bytes.count >= offset + 18 else {
                throw ProxyProtocolError.invalidConfiguration("invalid tuic udp ipv6")
            }
            let groups = stride(from: offset, to: offset + 16, by: 2).map { index in
                String(format: "%x", Int(bytes[index]) << 8 | Int(bytes[index + 1]))
            }
            offset += 16
            let port = Int(readUInt16(bytes, at: offset))
            offset += 2
            return .ipv6(groups.joined(separator: ":"), port: port)
        default:
            throw ProxyProtocolError.invalidConfiguration("unsupported tuic udp address")
        }
    }

    private static func uint16Bytes(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xff)])
    }

    private static func readUInt16(_ bytes: Data, at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
}

enum TUICCredentialParser {
    static func uuidBytes(from credential: String) throws -> [UInt8] {
        let parts = try parts(from: credential)
        guard let uuid = UUID(uuidString: String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic uuid")
        }
        let tuple = uuid.uuid
        return [tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7, tuple.8, tuple.9, tuple.10, tuple.11, tuple.12, tuple.13, tuple.14, tuple.15]
    }

    static func passwordBytes(from credential: String) throws -> [UInt8] {
        let parts = try parts(from: credential)
        return Array(String(parts[1]).utf8)
    }

    private static func parts(from credential: String) throws -> [Substring] {
        let parts = credential.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic credential")
        }
        guard !String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing tuic password")
        }
        return parts
    }
}

public struct TUICSessionAuthenticator<Dialer: TUICQUICSessionDialer>: Sendable {
    private let sessionDialer: Dialer

    public init(sessionDialer: Dialer) {
        self.sessionDialer = sessionDialer
    }

    public func openAuthenticatedSession(node: ProxyNode, credential: String, metadata: [String: String] = [:]) async throws -> any TUICQUICSession {
        try validate(node)
        let uuid = try TUICCredentialParser.uuidBytes(from: credential)
        let password = try TUICCredentialParser.passwordBytes(from: credential)
        var requestMetadata = metadata
        requestMetadata["proxyProtocol"] = node.protocolType.rawValue
        requestMetadata["quicServerName"] = node.tls.serverName ?? node.serverHost
        requestMetadata["quicProtocol"] = "tuic"
        requestMetadata["quicALPN"] = node.tls.alpn.isEmpty ? "h3" : node.tls.alpn.joined(separator: ",")
        let session = try await sessionDialer.openSession(
            host: node.serverHost,
            port: node.serverPort,
            tls: node.tls.enabled ? node.tls : nil,
            metadata: requestMetadata
        )
        let token = try await session.exportKeyingMaterial(label: Data(uuid), context: Data(password), length: 32)
        let authenticateCommand = try TUICAuthenticateCommand(credential: credential, exportedToken: token)
        let authStream = try await session.openUnidirectionalStream(initialPayload: Data())
        try await authStream.write(authenticateCommand.bytes)
        await authStream.closeWrite()
        return session
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .tuic else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard node.transport == .quic else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing tuic server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic server port")
        }
    }
}

public struct TUICStreamOpener<Dialer: TUICQUICSessionDialer>: Sendable {
    private let sessionDialer: Dialer

    public init(sessionDialer: Dialer) {
        self.sessionDialer = sessionDialer
    }

    public func openStream(node: ProxyNode, credential: String, destination: ProxyDestination, metadata: [String: String] = [:]) async throws -> any TransportByteStream {
        let connectCommand = try TUICConnectCommand(destination: destination)
        var requestMetadata = metadata
        for (key, value) in connectCommand.metadata {
            requestMetadata[key] = value
        }
        let session = try await TUICSessionAuthenticator(sessionDialer: sessionDialer).openAuthenticatedSession(node: node, credential: credential, metadata: requestMetadata)
        let stream = try await session.openBidirectionalStream(initialPayload: Data())
        try await stream.write(connectCommand.bytes)
        return stream
    }

    private func validate(_ node: ProxyNode) throws {
        guard node.protocolType == .tuic else {
            throw ProxyProtocolError.unsupportedProtocol(node.protocolType)
        }
        guard node.transport == .quic else {
            throw ProxyProtocolError.unsupportedTransport(node.transport)
        }
        guard !node.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyProtocolError.invalidConfiguration("missing tuic server host")
        }
        guard (1...65_535).contains(node.serverPort) else {
            throw ProxyProtocolError.invalidConfiguration("invalid tuic server port")
        }
    }
}

public struct UnavailableTUICQUICSessionDialer: TUICQUICSessionDialer {
    public init() {}

    public func openSession(host: String, port: Int, tls: TLSOptions?, metadata: [String: String]) async throws -> any TUICQUICSession {
        throw ProxyProtocolError.invalidConfiguration("tuic tls exporter authentication unavailable")
    }
}
