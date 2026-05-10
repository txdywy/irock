# irock M6 Local Routing Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parse local Shadowrocket/Clash-style routing rule text into precompiled routing rules that `RoutingEngine` can evaluate.

**Architecture:** M6 keeps all behavior inside `IrockRouting`. `RoutingRuleParser` converts text lines into `RoutingRule`; `CompiledRoutingRules` normalizes and buckets rules; `RoutingEngine` resolves contexts against the compiled rules while preserving the existing `[RoutingRule]` initializer.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, Foundation-free IPv4 parsing using standard Swift string and integer operations.

---

## File Structure

M6 creates and modifies these files:

```text
packages/IrockRouting/Sources/IrockRouting/IrockRouting.swift
packages/IrockRouting/Tests/IrockRoutingTests/IrockRoutingTests.swift
README.md
CLAUDE.md
docs/superpowers/specs/2026-05-10-irock-m6-local-routing-rules-design.md
docs/superpowers/plans/2026-05-10-irock-m6-local-routing-rules.md
```

Responsibilities:

- `IrockRouting.swift`: routing rule model, parser, compiled rule set, IPv4 CIDR matching, and engine resolution.
- `IrockRoutingTests.swift`: parser coverage, routing behavior, error stability, and backward-compatible engine initialization.
- `README.md` and `CLAUDE.md`: update project status to include M6.

---

### Task 1: Add parser and routing behavior tests

**Files:**
- Modify: `packages/IrockRouting/Tests/IrockRoutingTests/IrockRoutingTests.swift`

- [ ] **Step 1: Replace routing tests with M6 coverage**

Replace `packages/IrockRouting/Tests/IrockRoutingTests/IrockRoutingTests.swift` with:

```swift
import XCTest
@testable import IrockRouting

final class IrockRoutingTests: XCTestCase {
    func testParserIgnoresBlankLinesAndComments() throws {
        let rules = try RoutingRuleParser.parseLines([
            "",
            "  # Apple services",
            "DOMAIN-SUFFIX,apple.com,DIRECT",
            "FINAL,PROXY"
        ])

        XCTAssertEqual(rules, [
            .domainSuffix("apple.com", .direct),
            .final(.proxy)
        ])
    }

    func testParserParsesSupportedRuleTypes() throws {
        let rules = try RoutingRuleParser.parseLines([
            "DOMAIN,example.com,DIRECT",
            "DOMAIN-SUFFIX,apple.com,DIRECT",
            "DOMAIN-KEYWORD,google,PROXY",
            "IP-CIDR,10.0.0.0/8,DIRECT",
            "FINAL,REJECT"
        ])

        XCTAssertEqual(rules, [
            .domain("example.com", .direct),
            .domainSuffix("apple.com", .direct),
            .domainKeyword("google", .proxy),
            .ipCIDR("10.0.0.0/8", .direct),
            .final(.reject)
        ])
    }

    func testParserRejectsEmptyInput() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["", "# comment"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .emptyInput)
        }
    }

    func testParserRejectsInvalidFieldCount() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["DOMAIN,example.com"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .invalidFieldCount(line: 1, text: "DOMAIN,example.com"))
        }
    }

    func testParserRejectsUnsupportedRuleType() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["GEOIP,CN,DIRECT"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .unsupportedRuleType(line: 1, type: "GEOIP"))
        }
    }

    func testParserRejectsUnsupportedAction() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["DOMAIN,example.com,DROP"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .unsupportedAction(line: 1, action: "DROP"))
        }
    }

    func testParserRejectsEmptyValue() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["DOMAIN, ,DIRECT"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .emptyValue(line: 1))
        }
    }

    func testParserRejectsInvalidCIDR() {
        XCTAssertThrowsError(try RoutingRuleParser.parseLines(["IP-CIDR,10.0.0.0/33,DIRECT"])) { error in
            XCTAssertEqual(error as? RoutingRuleParseError, .invalidCIDR(line: 1, value: "10.0.0.0/33"))
        }
    }

    func testFinalRuleReturnsProxyDecision() {
        let engine = RoutingEngine(rules: [.final(.proxy)])
        let decision = engine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .proxy)
        XCTAssertEqual(decision.matchedRule, .final(.proxy))
    }

    func testDomainRuleMatchesExactHostOnly() {
        let engine = RoutingEngine(rules: [.domain("example.com", .direct), .final(.proxy)])

        let exact = engine.resolve(RoutingContext(host: "Example.Com.", ipAddress: nil, port: 443))
        let subdomain = engine.resolve(RoutingContext(host: "www.example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(exact.action, .direct)
        XCTAssertEqual(exact.matchedRule, .domain("example.com", .direct))
        XCTAssertEqual(subdomain.action, .proxy)
        XCTAssertEqual(subdomain.matchedRule, .final(.proxy))
    }

    func testDomainSuffixRuleBeatsFinalRule() {
        let engine = RoutingEngine(rules: [.domainSuffix("apple.com", .direct), .final(.proxy)])
        let decision = engine.resolve(RoutingContext(host: "developer.apple.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }

    func testDomainKeywordRuleMatchesNormalizedHost() {
        let engine = RoutingEngine(rules: [.domainKeyword("google", .proxy), .final(.direct)])
        let decision = engine.resolve(RoutingContext(host: "Maps.Googleapis.Com.", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .proxy)
        XCTAssertEqual(decision.matchedRule, .domainKeyword("google", .proxy))
    }

    func testIPCIDRRuleMatchesIPv4Address() {
        let engine = RoutingEngine(rules: [.ipCIDR("10.0.0.0/8", .direct), .final(.proxy)])
        let matched = engine.resolve(RoutingContext(host: nil, ipAddress: "10.42.1.9", port: 443))
        let missed = engine.resolve(RoutingContext(host: nil, ipAddress: "192.168.1.1", port: 443))

        XCTAssertEqual(matched.action, .direct)
        XCTAssertEqual(matched.matchedRule, .ipCIDR("10.0.0.0/8", .direct))
        XCTAssertEqual(missed.action, .proxy)
        XCTAssertEqual(missed.matchedRule, .final(.proxy))
    }

    func testRuleOrderWinsBeforeMoreSpecificLaterRule() {
        let engine = RoutingEngine(rules: [
            .domainSuffix("example.com", .proxy),
            .domain("api.example.com", .direct),
            .final(.reject)
        ])
        let decision = engine.resolve(RoutingContext(host: "api.example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .proxy)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("example.com", .proxy))
    }

    func testNoMatchUsesExplicitDefaultAction() {
        let engine = RoutingEngine(rules: [.domainSuffix("apple.com", .proxy)], defaultAction: .reject)
        let decision = engine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .reject)
        XCTAssertNil(decision.matchedRule)
    }

    func testEngineAcceptsCompiledRules() throws {
        let rules = try RoutingRuleParser.parseLines([
            "DOMAIN-SUFFIX,apple.com,DIRECT",
            "FINAL,PROXY"
        ])
        let engine = RoutingEngine(compiledRules: try CompiledRoutingRules(rules: rules))
        let decision = engine.resolve(RoutingContext(host: "developer.apple.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }
}
```

- [ ] **Step 2: Run routing tests to verify failure**

Run:

```bash
swift test --filter IrockRoutingTests
```

Expected: FAIL with compiler errors for missing `RoutingRuleParser`, `RoutingRuleParseError`, `CompiledRoutingRules`, and new `RoutingRule` cases.

---

### Task 2: Implement local rule parser and compiled routing rules

**Files:**
- Modify: `packages/IrockRouting/Sources/IrockRouting/IrockRouting.swift`

- [ ] **Step 1: Replace routing implementation**

Replace `packages/IrockRouting/Sources/IrockRouting/IrockRouting.swift` with:

```swift
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
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
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
                guard IPv4CIDR(value) != nil else {
                    throw RoutingRuleParseError.invalidCIDR(line: lineNumber, value: value)
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
                return .ipCIDR(rule, IPv4CIDR(cidr), action)
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

private extension IPv4Address {
    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

private extension String {
    func normalizedRoutingHost() -> String {
        lowercased().trimmingSuffix(".")
    }

    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
```

- [ ] **Step 2: Run routing tests**

Run:

```bash
swift test --filter IrockRoutingTests
```

Expected: PASS with all `IrockRoutingTests` passing.

- [ ] **Step 3: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

---

### Task 3: Refresh project guidance for M6

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README current phase**

Replace the current phase paragraph and bullets in `README.md` with:

```markdown
## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, M2 TUN data path core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, and M6 local routing rule parsing foundation:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing/storage behavior, file-backed snapshot persistence, app feature state, runtime snapshot publishing, Shadowsocks URI import, local routing rule parsing, packet parsing, flow tracking, and tunnel runtime processing
- Xcode target creation instructions; Xcode workspace, app targets, and Packet Tunnel targets are not yet committed
```

- [ ] **Step 2: Update README plan list**

Replace the implementation plan list in `README.md` with:

```markdown
## Implementation plans

- M0: `docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md`
- M1: `docs/superpowers/plans/2026-05-10-irock-m1-ui-configuration.md`
- M2: `docs/superpowers/plans/2026-05-10-irock-m2-tun-data-path.md`
- M3: `docs/superpowers/plans/2026-05-10-irock-m3-runtime-snapshot-persistence.md`
- M4: `docs/superpowers/plans/2026-05-10-irock-m4-runtime-snapshot-publishing.md`
- M5: `docs/superpowers/plans/2026-05-10-irock-m5-shadowsocks-uri-import.md`
- M6: `docs/superpowers/plans/2026-05-10-irock-m6-local-routing-rules.md`
```

- [ ] **Step 3: Update CLAUDE.md project status**

Replace the project status paragraph in `CLAUDE.md` with:

```markdown
## Project status

irock has a SwiftPM package graph, M1 app feature configuration scaffolding, M2 tunnel core, M3 runtime snapshot persistence foundation, M4 runtime snapshot publishing foundation, M5 Shadowsocks URI import foundation, and M6 local routing rule parsing foundation in the working tree. The committed product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Implementation plans live under `docs/superpowers/plans/`, including M0 engineering foundation, M1 UI configuration, M2 TUN data path, M3 runtime snapshot persistence, M4 runtime snapshot publishing, M5 Shadowsocks URI import, and M6 local routing rules.

There is not yet an Xcode workspace, app target, or Packet Tunnel target in the working tree. Do not assume `xcodebuild` or app schemes exist until Xcode targets are created.
```

- [ ] **Step 4: Run full test suite**

Run:

```bash
swift test
```

Expected: PASS with all SwiftPM tests passing.

---

## Verification Checklist

After completing all tasks, run:

```bash
git status --short
swift test --filter IrockRoutingTests
swift test
```

Expected final state:

- `git status --short` shows M5 and M6 staged or unstaged changes only; no unrelated source files.
- `swift test --filter IrockRoutingTests` passes.
- `swift test` passes with all SwiftPM tests.
- `RoutingRuleParser.parseLines(_:)` parses supported local rule lines.
- `CompiledRoutingRules` builds from parsed rules.
- `RoutingEngine` resolves DOMAIN, DOMAIN-SUFFIX, DOMAIN-KEYWORD, IP-CIDR, and FINAL rules in order.
- README and CLAUDE.md mention M6 local routing rule parsing.
