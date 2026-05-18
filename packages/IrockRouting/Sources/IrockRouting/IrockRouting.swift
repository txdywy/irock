import Darwin
public enum RoutingAction: Equatable, Sendable {
    case direct
    case proxy
    case reject
}

public enum RoutingRule: Equatable, Sendable {
    case domain(String, RoutingAction)
    case domainSuffix(String, RoutingAction)
    case domainKeyword(String, RoutingAction)
    case ipCIDR(String, RoutingAction)
    case final(RoutingAction)
}

public enum RoutingRuleParseError: Error, Equatable, Sendable {
    case emptyInput
    case invalidFieldCount(line: Int, text: String)
    case unsupportedRuleType(line: Int, type: String)
    case unsupportedAction(line: Int, action: String)
    case emptyValue(line: Int)
    case invalidCIDR(line: Int, value: String)
}

public struct RoutingContext: Equatable, Sendable {
    public let host: String?
    public let ipAddress: String?
    public let port: Int

    public init(host: String?, ipAddress: String?, port: Int) {
        self.host = host
        self.ipAddress = ipAddress
        self.port = port
    }
}

public struct RoutingDecision: Equatable, Sendable {
    public let action: RoutingAction
    public let matchedRule: RoutingRule?

    public init(action: RoutingAction, matchedRule: RoutingRule?) {
        self.action = action
        self.matchedRule = matchedRule
    }
}

public enum RoutingRuleParser {
    public static func parseLines(_ lines: [String]) throws -> [RoutingRule] {
        var rules: [RoutingRule] = []

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingRoutingWhitespace()
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingRoutingWhitespace() }
            guard let type = fields.first?.uppercased() else {
                continue
            }

            if type == "FINAL" {
                guard fields.count == 2 else {
                    throw RoutingRuleParseError.invalidFieldCount(line: lineNumber, text: line)
                }
                rules.append(.final(try parseAction(fields[1], line: lineNumber)))
                continue
            }

            guard fields.count == 3 else {
                throw RoutingRuleParseError.invalidFieldCount(line: lineNumber, text: line)
            }
            let value = fields[1]
            guard !value.isEmpty else {
                throw RoutingRuleParseError.emptyValue(line: lineNumber)
            }
            let action = try parseAction(fields[2], line: lineNumber)

            switch type {
            case "DOMAIN":
                rules.append(.domain(value, action))
            case "DOMAIN-SUFFIX":
                rules.append(.domainSuffix(value, action))
            case "DOMAIN-KEYWORD":
                rules.append(.domainKeyword(value, action))
            case "IP-CIDR":
                if value.contains(":") {
                    guard IPv6CIDR(value) != nil else {
                        throw RoutingRuleParseError.invalidCIDR(line: lineNumber, value: value)
                    }
                } else {
                    guard IPv4CIDR(value) != nil else {
                        throw RoutingRuleParseError.invalidCIDR(line: lineNumber, value: value)
                    }
                }
                rules.append(.ipCIDR(value, action))
            default:
                throw RoutingRuleParseError.unsupportedRuleType(line: lineNumber, type: type)
            }
        }

        guard !rules.isEmpty else {
            throw RoutingRuleParseError.emptyInput
        }
        return rules
    }

    private static func parseAction(_ text: String, line: Int) throws -> RoutingAction {
        switch text.uppercased() {
        case "DIRECT":
            return .direct
        case "PROXY":
            return .proxy
        case "REJECT":
            return .reject
        default:
            throw RoutingRuleParseError.unsupportedAction(line: line, action: text)
        }
    }
}

public struct CompiledRoutingRules: Sendable {
    fileprivate let entries: [CompiledRoutingRule]

    public init(rules: [RoutingRule]) throws {
        entries = rules.map { rule in
            switch rule {
            case let .domain(host, action):
                return .domain(rule, host.normalizedRoutingHost(), action)
            case let .domainSuffix(suffix, action):
                return .domainSuffix(rule, suffix.normalizedRoutingHost(), action)
            case let .domainKeyword(keyword, action):
                return .domainKeyword(rule, keyword.lowercased(), action)
            case let .ipCIDR(cidr, action):
                if cidr.contains(":") {
                    return .ip6CIDR(rule, IPv6CIDR(cidr), action)
                } else {
                    return .ipCIDR(rule, IPv4CIDR(cidr), action)
                }
            case let .final(action):
                return .final(rule, action)
            }
        }
    }
}

private enum CompiledRoutingRule: Sendable {
    case domain(RoutingRule, String, RoutingAction)
    case domainSuffix(RoutingRule, String, RoutingAction)
    case domainKeyword(RoutingRule, String, RoutingAction)
    case ipCIDR(RoutingRule, IPv4CIDR?, RoutingAction)
    case ip6CIDR(RoutingRule, IPv6CIDR?, RoutingAction)
    case final(RoutingRule, RoutingAction)
}

public struct RoutingEngine: Sendable {
    private let compiledRules: CompiledRoutingRules
    private let defaultAction: RoutingAction

    public init(rules: [RoutingRule], defaultAction: RoutingAction = .reject) {
        self.compiledRules = (try? CompiledRoutingRules(rules: rules)) ?? CompiledRoutingRules.uncheckedEmpty
        self.defaultAction = defaultAction
    }

    public init(compiledRules: CompiledRoutingRules, defaultAction: RoutingAction = .reject) {
        self.compiledRules = compiledRules
        self.defaultAction = defaultAction
    }

    public func resolve(_ context: RoutingContext) -> RoutingDecision {
        let normalizedHost = context.host?.normalizedRoutingHost()
        let ipAddress = context.ipAddress.flatMap(IPv4Address.init)
        let ip6Address = context.ipAddress.flatMap(IPv6Address.init)

        for entry in compiledRules.entries {
            switch entry {
            case let .domain(rule, host, action):
                if normalizedHost == host {
                    return RoutingDecision(action: action, matchedRule: rule)
                }
            case let .domainSuffix(rule, suffix, action):
                if let host = normalizedHost, host == suffix || host.hasSuffix("." + suffix) {
                    return RoutingDecision(action: action, matchedRule: rule)
                }
            case let .domainKeyword(rule, keyword, action):
                if let host = normalizedHost, host.contains(keyword) {
                    return RoutingDecision(action: action, matchedRule: rule)
                }
            case let .ipCIDR(rule, cidr, action):
                if let cidr, let ipAddress, cidr.contains(ipAddress) {
                    return RoutingDecision(action: action, matchedRule: rule)
                }
            case let .ip6CIDR(rule, cidr, action):
                if let cidr, let ip6Address, cidr.contains(ip6Address) {
                    return RoutingDecision(action: action, matchedRule: rule)
                }
            case let .final(rule, action):
                return RoutingDecision(action: action, matchedRule: rule)
            }
        }

        return RoutingDecision(action: defaultAction, matchedRule: nil)
    }
}

private extension CompiledRoutingRules {
    static let uncheckedEmpty = CompiledRoutingRules(entries: [])

    init(entries: [CompiledRoutingRule]) {
        self.entries = entries
    }
}

private struct IPv4Address: Equatable, Sendable {
    let rawValue: UInt32

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return nil
        }

        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else {
                return nil
            }
            value = (value << 8) | UInt32(octet)
        }
        rawValue = value
    }
}

private struct IPv4CIDR: Sendable {
    let network: IPv4Address
    let prefixLength: Int
    let mask: UInt32

    init?(_ text: String) {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let address = IPv4Address(String(parts[0])),
              let prefixLength = Int(parts[1]),
              (0...32).contains(prefixLength) else {
            return nil
        }

        let mask = prefixLength == 0 ? 0 : UInt32.max << UInt32(32 - prefixLength)
        self.network = IPv4Address(rawValue: address.rawValue & mask)
        self.prefixLength = prefixLength
        self.mask = mask
    }

    func contains(_ address: IPv4Address) -> Bool {
        (address.rawValue & mask) == network.rawValue
    }
}


private struct IPv6Address: Equatable, Sendable {
    let high: UInt64
    let low: UInt64

    init?(_ text: String) {
        var storage = in6_addr()
        guard text.withCString({ inet_pton(AF_INET6, $0, &storage) }) == 1 else { return nil }
        let (h, l) = withUnsafeBytes(of: storage) { bytes -> (UInt64, UInt64) in
            let h = bytes.load(fromByteOffset: 0, as: UInt64.self).bigEndian
            let l = bytes.load(fromByteOffset: 8, as: UInt64.self).bigEndian
            return (h, l)
        }
        self.high = h
        self.low = l
    }
    
    init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }
}

private struct IPv6CIDR: Sendable {
    let network: IPv6Address
    let prefixLength: Int
    let highMask: UInt64
    let lowMask: UInt64

    init?(_ text: String) {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let address = IPv6Address(String(parts[0])),
              let prefixLength = Int(parts[1]),
              (0...128).contains(prefixLength) else {
            return nil
        }
        let hMask: UInt64 = prefixLength == 0 ? 0 : (prefixLength <= 64 ? (prefixLength == 64 ? .max : ~(UInt64.max >> prefixLength)) : .max)
        let lMask: UInt64 = prefixLength <= 64 ? 0 : (prefixLength == 128 ? .max : ~(UInt64.max >> (prefixLength - 64)))
        self.highMask = hMask
        self.lowMask = lMask
        self.network = IPv6Address(high: address.high & hMask, low: address.low & lMask)
        self.prefixLength = prefixLength
    }

    func contains(_ address: IPv6Address) -> Bool {
        (address.high & highMask) == network.high && (address.low & lowMask) == network.low
    }
}

private extension IPv4Address {
    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

private extension String {
    func normalizedRoutingHost() -> String {
        lowercased().trimmingSuffix(".")
    }

    func trimmingRoutingWhitespace() -> String {
        let whitespace: Set<Character> = [" ", "\t", "\n", "\r"]
        let start = firstIndex { !whitespace.contains($0) } ?? endIndex
        let end = self[..<start].isEmpty ? self[start...].lastIndex { !whitespace.contains($0) } : lastIndex { !whitespace.contains($0) }
        guard let end else {
            return ""
        }
        return String(self[start...end])
    }

    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
