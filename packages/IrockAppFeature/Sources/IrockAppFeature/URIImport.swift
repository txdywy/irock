import Foundation
import IrockCore

public enum URIImportError: Error, Equatable, Sendable {
    case missingScheme
    case unsupportedScheme(String)
    case malformedURI
    case invalidBase64
    case missingUserInfo
    case missingHost
    case missingPort
}

public struct URIImportResult: Equatable, Sendable {
    public let protocolType: ProxyProtocolType
    public let originalText: String

    public init(protocolType: ProxyProtocolType, originalText: String) {
        self.protocolType = protocolType
        self.originalText = originalText
    }
}

public enum URIImport {
    public static func classify(_ text: String) throws -> URIImportResult {
        guard let scheme = URLComponents(string: text)?.scheme?.lowercased() else {
            throw URIImportError.missingScheme
        }

        switch scheme {
        case "ss":
            return URIImportResult(protocolType: .shadowsocks, originalText: text)
        case "vmess":
            return URIImportResult(protocolType: .vmess, originalText: text)
        case "vless":
            return URIImportResult(protocolType: .vless, originalText: text)
        case "trojan":
            return URIImportResult(protocolType: .trojan, originalText: text)
        case "hysteria2":
            return URIImportResult(protocolType: .hysteria2, originalText: text)
        case "tuic":
            return URIImportResult(protocolType: .tuic, originalText: text)
        default:
            throw URIImportError.unsupportedScheme(scheme)
        }
    }

    public static func parseShadowsocksDraft(_ text: String) throws -> NodeDraft {
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased() else {
            throw URIImportError.missingScheme
        }
        guard scheme == "ss" else {
            throw URIImportError.unsupportedScheme(scheme)
        }

        let payload = String(text.dropFirst("ss://".count))
        guard !payload.isEmpty else {
            throw URIImportError.malformedURI
        }

        let withoutFragment = payload.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let fragmentName = components.percentEncodedFragment?.removingPercentEncoding
        let parsed = try parseShadowsocksPayload(String(withoutFragment))
        let name = fragmentName?.isEmpty == false ? fragmentName! : "\(parsed.host):\(parsed.port)"

        return NodeDraft(
            name: name,
            protocolType: .shadowsocks,
            serverHost: parsed.host,
            serverPortText: parsed.port,
            credentialAccount: parsed.userInfo,
            transport: .tcp,
            tlsEnabled: false,
            tlsServerName: "",
            udpEnabled: false
        )
    }

    private static func parseShadowsocksPayload(_ payload: String) throws -> (userInfo: String, host: String, port: String) {
        if let atIndex = payload.firstIndex(of: "@") {
            let encodedUserInfo = String(payload[..<atIndex])
            let endpoint = String(payload[payload.index(after: atIndex)...])
            let userInfo = try decodeBase64String(encodedUserInfo)
            let parsedEndpoint = try parseEndpoint(endpoint)
            return (userInfo, parsedEndpoint.host, parsedEndpoint.port)
        }

        if payload.contains(":") {
            throw URIImportError.missingUserInfo
        }

        let decoded = try decodeBase64String(payload)
        guard let atIndex = decoded.lastIndex(of: "@") else {
            throw URIImportError.missingUserInfo
        }
        let userInfo = String(decoded[..<atIndex])
        let endpoint = String(decoded[decoded.index(after: atIndex)...])
        let parsedEndpoint = try parseEndpoint(endpoint)
        return (userInfo, parsedEndpoint.host, parsedEndpoint.port)
    }

    private static func parseEndpoint(_ endpoint: String) throws -> (host: String, port: String) {
        guard let colonIndex = endpoint.lastIndex(of: ":") else {
            throw URIImportError.missingPort
        }
        let host = String(endpoint[..<colonIndex])
        let port = String(endpoint[endpoint.index(after: colonIndex)...])
        guard !host.isEmpty else {
            throw URIImportError.missingHost
        }
        guard !port.isEmpty else {
            throw URIImportError.missingPort
        }
        return (host, port)
    }

    private static func decodeBase64String(_ text: String) throws -> String {
        var normalized = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: normalized), let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty else {
            throw URIImportError.invalidBase64
        }
        return decoded
    }
}
