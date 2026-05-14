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
    case unsupportedOption(String)
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
        let uriText = try extractSupportedURI(from: text)
        guard let scheme = URLComponents(string: uriText)?.scheme?.lowercased() else {
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
        case "hysteria2", "hy2", "realm":
            return URIImportResult(protocolType: .hysteria2, originalText: text)
        case "tuic":
            return URIImportResult(protocolType: .tuic, originalText: text)
        default:
            throw URIImportError.unsupportedScheme(scheme)
        }
    }

    public static func parseDraft(_ text: String) throws -> NodeDraft {
        let uriText = try extractSupportedURI(from: text)
        guard let scheme = URLComponents(string: uriText)?.scheme?.lowercased() else {
            throw URIImportError.missingScheme
        }
        switch scheme {
        case "ss": return try parseShadowsocksDraft(uriText)
        case "vmess": return try parseVMessDraft(uriText)
        case "vless": return try parseVLESSDraft(uriText)
        case "trojan": return try parseTrojanDraft(uriText)
        case "hysteria2", "hy2", "realm": return try parseHysteria2Draft(uriText)
        case "tuic": return try parseTUICDraft(uriText)
        default: throw URIImportError.unsupportedScheme(scheme)
        }
    }

    public static func parseSubscriptionDrafts(_ text: String) throws -> [NodeDraft] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let decoded = (try? decodeBase64String(trimmed)) ?? trimmed
        return try decoded
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(parseDraft)
    }

    public static func parseShadowsocksDraft(_ text: String) throws -> NodeDraft {
        let uriText = try extractSupportedURI(from: text)
        guard let components = URLComponents(string: uriText), let scheme = components.scheme?.lowercased() else {
            throw URIImportError.missingScheme
        }
        guard scheme == "ss" else {
            throw URIImportError.unsupportedScheme(scheme)
        }

        let payload = String(uriText.dropFirst("ss://".count))
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

    private static func parseVMessDraft(_ text: String) throws -> NodeDraft {
        let encoded = String(text.dropFirst("vmess://".count))
        let decoded = try decodeBase64String(encoded)
        guard let data = decoded.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URIImportError.malformedURI
        }
        let host = try requiredString(object["add"])
        let port = try requiredString(object["port"])
        let userID = try requiredString(object["id"])
        let transportName = optionalString(object["net"]) ?? "tcp"
        let tlsName = optionalString(object["tls"])?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tcpType = optionalString(object["type"])?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sni = optionalString(object["sni"]) ?? optionalString(object["host"]) ?? host
        let path = optionalString(object["path"]) ?? "/"
        let name = optionalString(object["ps"]) ?? "\(host):\(port)"
        let transport = try transportType(transportName)
        guard transport != .tcp || tcpType == nil || tcpType == "none" else {
            throw URIImportError.unsupportedOption("vmess tcp type")
        }
        return NodeDraft(
            name: name,
            protocolType: .vmess,
            serverHost: host,
            serverPortText: port,
            credentialAccount: userID,
            transport: transport,
            tlsEnabled: tlsName == "tls",
            tlsServerName: sni,
            udpEnabled: false,
            transportOptions: transportOptions(for: transport, host: optionalString(object["host"]), path: path, service: path),
            tlsFingerprint: optionalString(object["fp"])
        )
    }

    private static func parseVLESSDraft(_ text: String) throws -> NodeDraft {
        let components = try components(text)
        guard components.scheme?.lowercased() == "vless" else { throw URIImportError.unsupportedScheme(components.scheme ?? "") }
        let credential = try requiredUserInfo(components)
        let host = try requiredHost(components)
        let port = try requiredPort(components, defaultPort: 443)
        let query = queryItems(components)
        let flow = query["flow"] ?? ""
        guard flow.isEmpty else { throw URIImportError.unsupportedOption("vless flow") }
        let security = query["security"]?.lowercased() ?? "none"
        let transport = try transportType(query["type"] ?? "tcp")
        let realityPublicKey = query["pbk"]
        guard security == "none" || security == "tls" || security == "reality" else {
            throw URIImportError.unsupportedOption("vless security")
        }
        return NodeDraft(
            name: nodeName(components, host: host, port: port),
            protocolType: .vless,
            serverHost: host,
            serverPortText: String(port),
            credentialAccount: credential,
            transport: transport,
            tlsEnabled: security == "tls" || security == "reality",
            tlsServerName: query["sni"] ?? host,
            udpEnabled: false,
            transportOptions: transportOptions(for: transport, host: query["host"], path: query["path"] ?? "/", service: query["serviceName"] ?? query["path"] ?? "/"),
            tlsALPN: splitList(query["alpn"]),
            tlsFingerprint: query["fp"],
            realityPublicKey: realityPublicKey,
            realityShortID: query["sid"],
            realitySpiderX: query["spx"]
        )
    }

    private static func parseTrojanDraft(_ text: String) throws -> NodeDraft {
        let components = try components(text)
        guard components.scheme?.lowercased() == "trojan" else { throw URIImportError.unsupportedScheme(components.scheme ?? "") }
        let credential = try requiredUserInfo(components)
        let host = try requiredHost(components)
        let port = try requiredPort(components, defaultPort: 443)
        let query = queryItems(components)
        let transport = try transportType(query["type"] ?? "tcp")
        return NodeDraft(
            name: nodeName(components, host: host, port: port),
            protocolType: .trojan,
            serverHost: host,
            serverPortText: String(port),
            credentialAccount: credential,
            transport: transport,
            tlsEnabled: true,
            tlsServerName: query["sni"] ?? host,
            udpEnabled: false,
            transportOptions: transportOptions(for: transport, host: query["host"], path: query["path"] ?? "/", service: query["serviceName"] ?? query["path"] ?? "/"),
            tlsAllowInsecure: query["allowInsecure"] == "1" || query["security"] == "none",
            tlsALPN: splitList(query["alpn"])
        )
    }

    private static func parseHysteria2Draft(_ text: String) throws -> NodeDraft {
        let components = try components(text)
        guard ["hysteria2", "hy2", "realm"].contains(components.scheme?.lowercased() ?? "") else {
            throw URIImportError.unsupportedScheme(components.scheme ?? "")
        }
        let credential = try requiredUserInfo(components)
        let host = try requiredHost(components)
        let port = try requiredPort(components, defaultPort: 443)
        let query = queryItems(components)
        return NodeDraft(
            name: nodeName(components, host: host, port: port),
            protocolType: .hysteria2,
            serverHost: host,
            serverPortText: String(port),
            credentialAccount: credential,
            transport: .quic,
            tlsEnabled: true,
            tlsServerName: query["sni"] ?? host,
            udpEnabled: true,
            tlsAllowInsecure: query["insecure"] == "1",
            tlsALPN: splitList(query["alpn"]),
            tlsFingerprint: query["pinSHA256"],
            hysteria2Realm: try query["realm"].flatMap(parseRealmOption)
        )
    }

    private static func parseTUICDraft(_ text: String) throws -> NodeDraft {
        let components = try components(text)
        guard components.scheme?.lowercased() == "tuic" else { throw URIImportError.unsupportedScheme(components.scheme ?? "") }
        let credential = try requiredUserInfo(components)
        let host = try requiredHost(components)
        let port = try requiredPort(components, defaultPort: 443)
        let query = queryItems(components)
        return NodeDraft(
            name: nodeName(components, host: host, port: port),
            protocolType: .tuic,
            serverHost: host,
            serverPortText: String(port),
            credentialAccount: credential,
            transport: .quic,
            tlsEnabled: true,
            tlsServerName: query["sni"] ?? host,
            udpEnabled: true,
            tlsALPN: splitList(query["alpn"])
        )
    }

    private static func parseRealmOption(_ text: String) throws -> Hysteria2RealmDraft? {
        if text == "1" || text.lowercased() == "true" {
            return nil
        }
        return try parseRealm(text)
    }

    private static func parseRealm(_ text: String) throws -> Hysteria2RealmDraft {
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased() else {
            throw URIImportError.malformedURI
        }
        guard scheme == "realm" || scheme == "realm+http" else {
            throw URIImportError.unsupportedScheme(scheme)
        }
        let token = try requiredUserInfo(components)
        let host = try requiredHost(components)
        let name = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).removingPercentEncoding ?? ""
        guard !name.isEmpty else { throw URIImportError.malformedURI }
        let query = queryItems(components)
        return Hysteria2RealmDraft(
            token: token,
            rendezvousHost: host,
            rendezvousPort: components.port,
            name: name,
            useTLS: scheme == "realm",
            stunServers: components.queryItems?.filter { $0.name == "stun" }.compactMap(\.value) ?? [],
            localPort: query["lport"].flatMap(Int.init)
        )
    }

    private static func extractSupportedURI(from text: String) throws -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined()
        for scheme in ["hysteria2", "vmess", "vless", "trojan", "tuic", "realm", "hy2", "ss"] {
            if let range = compact.range(of: "\(scheme)://", options: .caseInsensitive) {
                let candidate = String(compact[range.lowerBound...].prefix { $0.isASCII && !$0.isWhitespace })
                return String(candidate.split(separator: "，", maxSplits: 1, omittingEmptySubsequences: false)[0])
            }
        }
        throw URLComponents(string: text)?.scheme.map { URIImportError.unsupportedScheme($0.lowercased()) } ?? URIImportError.missingScheme
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

    private static func components(_ text: String) throws -> URLComponents {
        guard let components = URLComponents(string: text), components.scheme != nil else {
            throw URIImportError.missingScheme
        }
        return components
    }

    private static func requiredUserInfo(_ components: URLComponents) throws -> String {
        guard let user = components.percentEncodedUser?.removingPercentEncoding, !user.isEmpty else {
            throw URIImportError.missingUserInfo
        }
        if let password = components.percentEncodedPassword?.removingPercentEncoding, !password.isEmpty {
            return "\(user):\(password)"
        }
        return user
    }

    private static func requiredHost(_ components: URLComponents) throws -> String {
        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            throw URIImportError.missingHost
        }
        return host
    }

    private static func requiredPort(_ components: URLComponents, defaultPort: Int? = nil) throws -> Int {
        if let port = components.port { return port }
        if let defaultPort { return defaultPort }
        throw URIImportError.missingPort
    }

    private static func requiredString(_ value: Any?) throws -> String {
        if let string = value as? String, !string.isEmpty { return string }
        if let int = value as? Int { return String(int) }
        throw URIImportError.malformedURI
    }

    private static func optionalString(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let int = value as? Int { return String(int) }
        return nil
    }

    private static func queryItems(_ components: URLComponents) -> [String: String] {
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value, !value.isEmpty else { continue }
            result[item.name] = value
        }
        return result
    }

    private static func nodeName(_ components: URLComponents, host: String, port: Int) -> String {
        components.percentEncodedFragment?.removingPercentEncoding.flatMap { $0.isEmpty ? nil : $0 } ?? "\(host):\(port)"
    }

    private static func transportType(_ value: String) throws -> TransportType {
        switch value.lowercased() {
        case "tcp", "none": return .tcp
        case "ws", "websocket": return .webSocket
        case "h2", "http", "http2": return .http2
        case "grpc": return .grpc
        case "quic": return .quic
        default: throw URIImportError.unsupportedOption("transport")
        }
    }

    private static func transportOptions(for transport: TransportType, host: String?, path: String, service: String) -> TransportOptions {
        switch transport {
        case .webSocket:
            return TransportOptions(webSocket: WebSocketTransportOptions(host: host, path: path.isEmpty ? "/" : path))
        case .http2:
            return TransportOptions(http2: HTTP2TransportOptions(authority: host, path: path.isEmpty ? "/" : path))
        case .grpc:
            return TransportOptions(grpc: GRPCTransportOptions(authority: host, service: service.isEmpty ? "/TunService/Connect" : service))
        default:
            return TransportOptions()
        }
    }

    private static func splitList(_ value: String?) -> [String] {
        value?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
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
