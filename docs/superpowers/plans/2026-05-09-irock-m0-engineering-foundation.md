# irock M0 Engineering Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the initial irock engineering foundation: repository hygiene, shared Swift packages, core domain models, and documented Xcode target creation steps for iOS/macOS apps and Packet Tunnel extensions.

**Architecture:** M0 creates a SwiftPM-first core so the project has testable code before Xcode app targets exist. Shared packages define the stable language for later App, Tunnel, protocol, routing, storage, diagnostics, and performance work. Xcode workspace and Network Extension targets are documented and stubbed in this plan because they require Xcode project generation/signing decisions that should be done intentionally on macOS with a developer team.

**Tech Stack:** Swift 5.10+ or Swift 6 compatible syntax, Swift Package Manager, XCTest, SwiftUI, NetworkExtension, App Groups, Xcode workspace/project targets.

---

## File Structure

M0 creates and owns these files:

```text
.gitignore
Package.swift
README.md
docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md
apps/README.md
apps/irock-iOS/README.md
apps/irock-macOS/README.md
packages/IrockCore/Sources/IrockCore/IrockCore.swift
packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift
packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift
packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
packages/IrockRouting/Sources/IrockRouting/IrockRouting.swift
packages/IrockRouting/Tests/IrockRoutingTests/IrockRoutingTests.swift
packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift
packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift
packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift
packages/IrockDiagnostics/Sources/IrockDiagnostics/IrockDiagnostics.swift
packages/IrockDiagnostics/Tests/IrockDiagnosticsTests/IrockDiagnosticsTests.swift
packages/IrockPerformanceKit/Sources/IrockPerformanceKit/IrockPerformanceKit.swift
packages/IrockPerformanceKit/Tests/IrockPerformanceKitTests/IrockPerformanceKitTests.swift
tools/protocol-lab/README.md
tools/benchmark-runner/README.md
tools/config-fixtures/README.md
tests/protocol-fixtures/README.md
tests/routing-fixtures/README.md
tests/performance-baselines/README.md
```

Later plans create these Xcode artifacts after M0's SwiftPM foundation passes:

```text
irock.xcworkspace
apps/irock-iOS/irockApp.xcodeproj
apps/irock-iOS/irockTunnelExtension/
apps/irock-macOS/irockMacApp.xcodeproj
apps/irock-macOS/irockMacTunnelExtension/
```

The Xcode artifacts are intentionally deferred from code generation in M0 because Network Extension entitlements and App Group identifiers depend on the local Apple Developer Team ID.

---

### Task 1: Repository hygiene and directory skeleton

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `apps/README.md`
- Create: `apps/irock-iOS/README.md`
- Create: `apps/irock-macOS/README.md`
- Create: `tools/protocol-lab/README.md`
- Create: `tools/benchmark-runner/README.md`
- Create: `tools/config-fixtures/README.md`
- Create: `tests/protocol-fixtures/README.md`
- Create: `tests/routing-fixtures/README.md`
- Create: `tests/performance-baselines/README.md`

- [ ] **Step 1: Create repository ignore rules**

Create `.gitignore` with this content:

```gitignore
# macOS
.DS_Store

# Xcode
DerivedData/
build/
*.xcuserstate
*.xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
*.xcworkspace/xcuserdata/

# Swift Package Manager
.build/
.swiftpm/

# Planning/runtime scratch state
.omc/
.superpowers/

# Secrets and local signing
*.mobileprovision
*.p12
*.cer
.env
.env.*
```

- [ ] **Step 2: Create project README**

Create `README.md` with this content:

```markdown
# irock

irock is a personal iOS/macOS network proxy client inspired by Shadowrocket's information architecture. The project uses Swift, SwiftUI, Network Extension, and shared Swift packages for protocol, routing, storage, diagnostics, and performance modules.

## Current phase

M0 builds the engineering foundation:

- SwiftPM package graph
- Core domain models
- Module boundaries
- XCTest baseline
- Xcode target creation instructions

## Design

See `docs/superpowers/specs/2026-05-09-irock-design.md`.
```

- [ ] **Step 3: Create app directory notes**

Create `apps/README.md` with this content:

```markdown
# Apps

This directory contains platform app targets and Packet Tunnel extensions.

M0 keeps app targets as documented placeholders. The actual Xcode projects are created after shared Swift packages compile and tests pass.
```

Create `apps/irock-iOS/README.md` with this content:

```markdown
# irock iOS App

Planned targets:

- `irockApp`: SwiftUI iOS container app
- `irockTunnelExtension`: iOS Packet Tunnel extension

Required capabilities when the Xcode project is created:

- Network Extensions: Packet Tunnel
- App Groups: shared runtime snapshot storage
- Keychain Sharing: node credentials
```

Create `apps/irock-macOS/README.md` with this content:

```markdown
# irock macOS App

Planned targets:

- `irockMacApp`: SwiftUI macOS container app
- `irockMacTunnelExtension`: macOS Packet Tunnel extension

Required capabilities when the Xcode project is created:

- Network Extensions: Packet Tunnel
- App Groups: shared runtime snapshot storage
- Keychain Sharing: node credentials
```

- [ ] **Step 4: Create tools and fixture notes**

Create `tools/protocol-lab/README.md` with this content:

```markdown
# Protocol Lab

Development-only protocol comparison tools live here. Later phases use this area to compare irock protocol behavior against sing-box, xray, or clash without embedding those engines into the app runtime.
```

Create `tools/benchmark-runner/README.md` with this content:

```markdown
# Benchmark Runner

Performance benchmark tooling lives here. Later phases measure throughput, latency, memory, tunnel startup time, protocol handshake time, and rule matching cost.
```

Create `tools/config-fixtures/README.md` with this content:

```markdown
# Config Fixtures

Sample node and rule configurations live here. Do not commit real server credentials.
```

Create `tests/protocol-fixtures/README.md` with this content:

```markdown
# Protocol Fixtures

Protocol fixture data lives here. Use sanitized, non-secret examples only.
```

Create `tests/routing-fixtures/README.md` with this content:

```markdown
# Routing Fixtures

Rule parsing and routing decision fixtures live here.
```

Create `tests/performance-baselines/README.md` with this content:

```markdown
# Performance Baselines

Performance baseline reports live here. Baselines must name device, OS version, network, protocol, transport, and build configuration.
```

- [ ] **Step 5: Verify directory skeleton**

Run:

```bash
find . -maxdepth 3 -type f | sort
```

Expected: output includes all README files above, `.gitignore`, the committed design spec, and this plan file.

- [ ] **Step 6: Commit repository hygiene**

Run:

```bash
git add .gitignore README.md apps tools tests
git commit -m "chore: add repository skeleton"
```

Expected: commit succeeds and does not include `.omc/` or `.superpowers/`.

---

### Task 2: SwiftPM package graph

**Files:**
- Create: `Package.swift`
- Create: empty source/test directories for all package targets listed below

- [ ] **Step 1: Write the package manifest**

Create `Package.swift` with this content:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "irock",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "IrockCore", targets: ["IrockCore"]),
        .library(name: "IrockProtocols", targets: ["IrockProtocols"]),
        .library(name: "IrockRouting", targets: ["IrockRouting"]),
        .library(name: "IrockTransport", targets: ["IrockTransport"]),
        .library(name: "IrockStorage", targets: ["IrockStorage"]),
        .library(name: "IrockDiagnostics", targets: ["IrockDiagnostics"]),
        .library(name: "IrockPerformanceKit", targets: ["IrockPerformanceKit"])
    ],
    targets: [
        .target(
            name: "IrockCore",
            path: "packages/IrockCore/Sources/IrockCore"
        ),
        .testTarget(
            name: "IrockCoreTests",
            dependencies: ["IrockCore"],
            path: "packages/IrockCore/Tests/IrockCoreTests"
        ),
        .target(
            name: "IrockTransport",
            dependencies: ["IrockCore"],
            path: "packages/IrockTransport/Sources/IrockTransport"
        ),
        .testTarget(
            name: "IrockTransportTests",
            dependencies: ["IrockTransport"],
            path: "packages/IrockTransport/Tests/IrockTransportTests"
        ),
        .target(
            name: "IrockProtocols",
            dependencies: ["IrockCore", "IrockTransport"],
            path: "packages/IrockProtocols/Sources/IrockProtocols"
        ),
        .testTarget(
            name: "IrockProtocolsTests",
            dependencies: ["IrockProtocols"],
            path: "packages/IrockProtocols/Tests/IrockProtocolsTests"
        ),
        .target(
            name: "IrockRouting",
            dependencies: ["IrockCore"],
            path: "packages/IrockRouting/Sources/IrockRouting"
        ),
        .testTarget(
            name: "IrockRoutingTests",
            dependencies: ["IrockRouting"],
            path: "packages/IrockRouting/Tests/IrockRoutingTests"
        ),
        .target(
            name: "IrockStorage",
            dependencies: ["IrockCore"],
            path: "packages/IrockStorage/Sources/IrockStorage"
        ),
        .testTarget(
            name: "IrockStorageTests",
            dependencies: ["IrockStorage"],
            path: "packages/IrockStorage/Tests/IrockStorageTests"
        ),
        .target(
            name: "IrockDiagnostics",
            dependencies: ["IrockCore"],
            path: "packages/IrockDiagnostics/Sources/IrockDiagnostics"
        ),
        .testTarget(
            name: "IrockDiagnosticsTests",
            dependencies: ["IrockDiagnostics"],
            path: "packages/IrockDiagnostics/Tests/IrockDiagnosticsTests"
        ),
        .target(
            name: "IrockPerformanceKit",
            dependencies: ["IrockCore"],
            path: "packages/IrockPerformanceKit/Sources/IrockPerformanceKit"
        ),
        .testTarget(
            name: "IrockPerformanceKitTests",
            dependencies: ["IrockPerformanceKit"],
            path: "packages/IrockPerformanceKit/Tests/IrockPerformanceKitTests"
        )
    ]
)
```

- [ ] **Step 2: Create minimal source files**

Create `packages/IrockCore/Sources/IrockCore/IrockCore.swift` with this content:

```swift
public enum IrockCoreModule {
    public static let name = "IrockCore"
}
```

Create `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift` with this content:

```swift
import IrockCore

public enum IrockTransportModule {
    public static let name = "IrockTransport"
    public static let coreName = IrockCoreModule.name
}
```

Create `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift` with this content:

```swift
import IrockCore
import IrockTransport

public enum IrockProtocolsModule {
    public static let name = "IrockProtocols"
    public static let coreName = IrockCoreModule.name
    public static let transportName = IrockTransportModule.name
}
```

Create `packages/IrockRouting/Sources/IrockRouting/IrockRouting.swift` with this content:

```swift
import IrockCore

public enum IrockRoutingModule {
    public static let name = "IrockRouting"
    public static let coreName = IrockCoreModule.name
}
```

Create `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift` with this content:

```swift
import IrockCore

public enum IrockStorageModule {
    public static let name = "IrockStorage"
    public static let coreName = IrockCoreModule.name
}
```

Create `packages/IrockDiagnostics/Sources/IrockDiagnostics/IrockDiagnostics.swift` with this content:

```swift
import IrockCore

public enum IrockDiagnosticsModule {
    public static let name = "IrockDiagnostics"
    public static let coreName = IrockCoreModule.name
}
```

Create `packages/IrockPerformanceKit/Sources/IrockPerformanceKit/IrockPerformanceKit.swift` with this content:

```swift
import IrockCore

public enum IrockPerformanceKitModule {
    public static let name = "IrockPerformanceKit"
    public static let coreName = IrockCoreModule.name
}
```

- [ ] **Step 3: Create package smoke tests**

Create `packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift` with this content:

```swift
import XCTest
@testable import IrockCore

final class IrockCoreTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(IrockCoreModule.name, "IrockCore")
    }
}
```

Create `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift` with this content:

```swift
import XCTest
@testable import IrockTransport

final class IrockTransportTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockTransportModule.name, "IrockTransport")
        XCTAssertEqual(IrockTransportModule.coreName, "IrockCore")
    }
}
```

Create `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` with this content:

```swift
import XCTest
@testable import IrockProtocols

final class IrockProtocolsTests: XCTestCase {
    func testModuleNameAndDependencies() {
        XCTAssertEqual(IrockProtocolsModule.name, "IrockProtocols")
        XCTAssertEqual(IrockProtocolsModule.coreName, "IrockCore")
        XCTAssertEqual(IrockProtocolsModule.transportName, "IrockTransport")
    }
}
```

Create `packages/IrockRouting/Tests/IrockRoutingTests/IrockRoutingTests.swift` with this content:

```swift
import XCTest
@testable import IrockRouting

final class IrockRoutingTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockRoutingModule.name, "IrockRouting")
        XCTAssertEqual(IrockRoutingModule.coreName, "IrockCore")
    }
}
```

Create `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift` with this content:

```swift
import XCTest
@testable import IrockStorage

final class IrockStorageTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockStorageModule.name, "IrockStorage")
        XCTAssertEqual(IrockStorageModule.coreName, "IrockCore")
    }
}
```

Create `packages/IrockDiagnostics/Tests/IrockDiagnosticsTests/IrockDiagnosticsTests.swift` with this content:

```swift
import XCTest
@testable import IrockDiagnostics

final class IrockDiagnosticsTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockDiagnosticsModule.name, "IrockDiagnostics")
        XCTAssertEqual(IrockDiagnosticsModule.coreName, "IrockCore")
    }
}
```

Create `packages/IrockPerformanceKit/Tests/IrockPerformanceKitTests/IrockPerformanceKitTests.swift` with this content:

```swift
import XCTest
@testable import IrockPerformanceKit

final class IrockPerformanceKitTests: XCTestCase {
    func testModuleNameAndDependency() {
        XCTAssertEqual(IrockPerformanceKitModule.name, "IrockPerformanceKit")
        XCTAssertEqual(IrockPerformanceKitModule.coreName, "IrockCore")
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
swift test
```

Expected: all 7 test suites pass.

- [ ] **Step 5: Commit package graph**

Run:

```bash
git add Package.swift packages
git commit -m "chore: add Swift package graph"
```

Expected: commit succeeds.

---

### Task 3: Core domain model baseline

**Files:**
- Modify: `packages/IrockCore/Sources/IrockCore/IrockCore.swift`
- Modify: `packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift`

- [ ] **Step 1: Replace the core smoke test with domain model tests**

Replace `packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift` with this content:

```swift
import XCTest
@testable import IrockCore

final class IrockCoreTests: XCTestCase {
    func testProxyNodeStoresProtocolTransportAndEndpoint() {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo VLESS",
            protocolType: .vless,
            serverHost: "example.com",
            serverPort: 443,
            credentials: .uuid("00000000-0000-0000-0000-000000000000"),
            transport: .grpc,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: nil),
            udpPolicy: .enabled
        )

        XCTAssertEqual(node.id.rawValue, "node-1")
        XCTAssertEqual(node.name, "Demo VLESS")
        XCTAssertEqual(node.protocolType, .vless)
        XCTAssertEqual(node.serverHost, "example.com")
        XCTAssertEqual(node.serverPort, 443)
        XCTAssertEqual(node.transport, .grpc)
        XCTAssertEqual(node.tls.alpn, ["h2"])
        XCTAssertEqual(node.udpPolicy, .enabled)
    }

    func testRuntimeSnapshotFreezesSelectedNodeAndRouteMode() {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo SS",
            protocolType: .shadowsocks,
            serverHost: "127.0.0.1",
            serverPort: 8388,
            credentials: .password("secret"),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )

        let snapshot = RuntimeSnapshot(
            id: SnapshotID(rawValue: "snapshot-1"),
            selectedNode: node,
            routeMode: .ruleBased,
            logLevel: .user
        )

        XCTAssertEqual(snapshot.selectedNode.id.rawValue, "node-1")
        XCTAssertEqual(snapshot.routeMode, .ruleBased)
        XCTAssertEqual(snapshot.logLevel, .user)
    }
}
```

- [ ] **Step 2: Run core tests to verify failure**

Run:

```bash
swift test --filter IrockCoreTests
```

Expected: FAIL because `ProxyNode`, `NodeID`, `TLSOptions`, `RuntimeSnapshot`, and related enums are not defined.

- [ ] **Step 3: Implement core domain models**

Replace `packages/IrockCore/Sources/IrockCore/IrockCore.swift` with this content. Keep `IrockCoreModule` because Task 2 module smoke tests still use it:

```swift
public enum IrockCoreModule {
    public static let name = "IrockCore"
}

public struct NodeID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct SnapshotID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ProxyProtocolType: String, Codable, Sendable {
    case shadowsocks
    case vmess
    case vless
    case trojan
    case hysteria2
    case tuic
}

public enum TransportType: String, Codable, Sendable {
    case tcp
    case webSocket
    case http2
    case grpc
    case quic
}

public enum ProxyCredentials: Equatable, Codable, Sendable {
    case password(String)
    case uuid(String)
    case token(String)
}

public struct RealityOptions: Equatable, Codable, Sendable {
    public let publicKey: String
    public let shortID: String?
    public let spiderX: String?

    public init(publicKey: String, shortID: String?, spiderX: String?) {
        self.publicKey = publicKey
        self.shortID = shortID
        self.spiderX = spiderX
    }
}

public struct TLSOptions: Equatable, Codable, Sendable {
    public let enabled: Bool
    public let serverName: String?
    public let allowInsecure: Bool
    public let alpn: [String]
    public let fingerprint: String?
    public let reality: RealityOptions?

    public static let disabled = TLSOptions(
        enabled: false,
        serverName: nil,
        allowInsecure: false,
        alpn: [],
        fingerprint: nil,
        reality: nil
    )

    public init(enabled: Bool, serverName: String?, allowInsecure: Bool, alpn: [String], fingerprint: String?, reality: RealityOptions?) {
        self.enabled = enabled
        self.serverName = serverName
        self.allowInsecure = allowInsecure
        self.alpn = alpn
        self.fingerprint = fingerprint
        self.reality = reality
    }
}

public enum UDPPolicy: String, Codable, Sendable {
    case disabled
    case enabled
}

public struct ProxyNode: Equatable, Codable, Sendable {
    public let id: NodeID
    public let name: String
    public let protocolType: ProxyProtocolType
    public let serverHost: String
    public let serverPort: Int
    public let credentials: ProxyCredentials
    public let transport: TransportType
    public let tls: TLSOptions
    public let udpPolicy: UDPPolicy

    public init(
        id: NodeID,
        name: String,
        protocolType: ProxyProtocolType,
        serverHost: String,
        serverPort: Int,
        credentials: ProxyCredentials,
        transport: TransportType,
        tls: TLSOptions,
        udpPolicy: UDPPolicy
    ) {
        self.id = id
        self.name = name
        self.protocolType = protocolType
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.credentials = credentials
        self.transport = transport
        self.tls = tls
        self.udpPolicy = udpPolicy
    }
}

public enum RouteMode: String, Codable, Sendable {
    case globalProxy
    case ruleBased
    case direct
}

public enum IrockLogLevel: String, Codable, Sendable {
    case off
    case user
    case debug
}

public struct RuntimeSnapshot: Equatable, Codable, Sendable {
    public let id: SnapshotID
    public let selectedNode: ProxyNode
    public let routeMode: RouteMode
    public let logLevel: IrockLogLevel

    public init(id: SnapshotID, selectedNode: ProxyNode, routeMode: RouteMode, logLevel: IrockLogLevel) {
        self.id = id
        self.selectedNode = selectedNode
        self.routeMode = routeMode
        self.logLevel = logLevel
    }
}
```

- [ ] **Step 4: Run core tests**

Run:

```bash
swift test --filter IrockCoreTests
```

Expected: PASS.

- [ ] **Step 5: Run all tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit core domain models**

Run:

```bash
git add packages/IrockCore
git commit -m "feat: add core domain models"
```

Expected: commit succeeds.

---

### Task 4: Protocol and transport interface baseline

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Write transport interface tests**

Replace `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift` with this content:

```swift
import XCTest
import IrockCore
@testable import IrockTransport

final class IrockTransportTests: XCTestCase {
    func testTransportRequestStoresEndpointAndKind() {
        let request = TransportRequest(host: "example.com", port: 443, transport: .grpc)

        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 443)
        XCTAssertEqual(request.transport, .grpc)
    }

    func testNoopTransportFailsWithUnsupportedTransport() async {
        let transport = NoopTransportAdapter()
        let request = TransportRequest(host: "example.com", port: 443, transport: .quic)

        do {
            _ = try await transport.open(request)
            XCTFail("Expected unsupported transport")
        } catch let error as TransportError {
            XCTAssertEqual(error, .unsupportedTransport(.quic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Write protocol interface tests**

Replace `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift` with this content:

```swift
import XCTest
import IrockCore
@testable import IrockProtocols

final class IrockProtocolsTests: XCTestCase {
    func testProxyRequestStoresNodeAndDestination() {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo Trojan",
            protocolType: .trojan,
            serverHost: "example.com",
            serverPort: 443,
            credentials: .password("secret"),
            transport: .tcp,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: .disabled
        )
        let request = ProxyRequest(node: node, destinationHost: "apple.com", destinationPort: 443)

        XCTAssertEqual(request.node.protocolType, .trojan)
        XCTAssertEqual(request.destinationHost, "apple.com")
        XCTAssertEqual(request.destinationPort, 443)
    }

    func testNoopProxyAdapterFailsWithUnsupportedProtocol() async {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo TUIC",
            protocolType: .tuic,
            serverHost: "example.com",
            serverPort: 443,
            credentials: .token("token"),
            transport: .quic,
            tls: TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
            udpPolicy: .enabled
        )
        let adapter = NoopProxyAdapter()
        let request = ProxyRequest(node: node, destinationHost: "apple.com", destinationPort: 443)

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProtocolAdapterError {
            XCTAssertEqual(error, .unsupportedProtocol(.tuic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

- [ ] **Step 3: Run interface tests to verify failure**

Run:

```bash
swift test --filter 'IrockTransportTests|IrockProtocolsTests'
```

Expected: FAIL because request types and adapters are not defined.

- [ ] **Step 4: Implement transport interfaces**

Replace `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift` with this content:

```swift
import IrockCore

public struct TransportRequest: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let transport: TransportType

    public init(host: String, port: Int, transport: TransportType) {
        self.host = host
        self.port = port
        self.transport = transport
    }
}

public struct TransportConnection: Sendable {
    public init() {}
}

public enum TransportError: Error, Equatable, Sendable {
    case unsupportedTransport(TransportType)
}

public protocol TransportAdapter: Sendable {
    func open(_ request: TransportRequest) async throws -> TransportConnection
}

public struct NoopTransportAdapter: TransportAdapter {
    public init() {}

    public func open(_ request: TransportRequest) async throws -> TransportConnection {
        throw TransportError.unsupportedTransport(request.transport)
    }
}
```

- [ ] **Step 5: Implement protocol interfaces**

Replace `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift` with this content:

```swift
import IrockCore
import IrockTransport

public struct ProxyRequest: Equatable, Sendable {
    public let node: ProxyNode
    public let destinationHost: String
    public let destinationPort: Int

    public init(node: ProxyNode, destinationHost: String, destinationPort: Int) {
        self.node = node
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
    }
}

public struct ProxyConnection: Sendable {
    public init() {}
}

public enum ProtocolAdapterError: Error, Equatable, Sendable {
    case unsupportedProtocol(ProxyProtocolType)
}

public protocol ProxyAdapter: Sendable {
    func connect(request: ProxyRequest) async throws -> ProxyConnection
}

public struct NoopProxyAdapter: ProxyAdapter {
    public init() {}

    public func connect(request: ProxyRequest) async throws -> ProxyConnection {
        throw ProtocolAdapterError.unsupportedProtocol(request.node.protocolType)
    }
}
```

- [ ] **Step 6: Run interface tests**

Run:

```bash
swift test --filter 'IrockTransportTests|IrockProtocolsTests'
```

Expected: PASS.

- [ ] **Step 7: Run all tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 8: Commit interfaces**

Run:

```bash
git add packages/IrockTransport packages/IrockProtocols
git commit -m "feat: add protocol and transport interfaces"
```

Expected: commit succeeds.

---

### Task 5: Routing, storage, diagnostics, and performance baselines

**Files:**
- Modify: `packages/IrockRouting/Sources/IrockRouting/IrockRouting.swift`
- Modify: `packages/IrockRouting/Tests/IrockRoutingTests/IrockRoutingTests.swift`
- Modify: `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift`
- Modify: `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift`
- Modify: `packages/IrockDiagnostics/Sources/IrockDiagnostics/IrockDiagnostics.swift`
- Modify: `packages/IrockDiagnostics/Tests/IrockDiagnosticsTests/IrockDiagnosticsTests.swift`
- Modify: `packages/IrockPerformanceKit/Sources/IrockPerformanceKit/IrockPerformanceKit.swift`
- Modify: `packages/IrockPerformanceKit/Tests/IrockPerformanceKitTests/IrockPerformanceKitTests.swift`

- [ ] **Step 1: Write routing tests**

Replace `packages/IrockRouting/Tests/IrockRoutingTests/IrockRoutingTests.swift` with this content:

```swift
import XCTest
@testable import IrockRouting

final class IrockRoutingTests: XCTestCase {
    func testFinalRuleReturnsProxyDecision() {
        let engine = RoutingEngine(rules: [.final(.proxy)])
        let decision = engine.resolve(RoutingContext(host: "example.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .proxy)
        XCTAssertEqual(decision.matchedRule, .final(.proxy))
    }

    func testDomainSuffixRuleBeatsFinalRule() {
        let engine = RoutingEngine(rules: [.domainSuffix("apple.com", .direct), .final(.proxy)])
        let decision = engine.resolve(RoutingContext(host: "developer.apple.com", ipAddress: nil, port: 443))

        XCTAssertEqual(decision.action, .direct)
        XCTAssertEqual(decision.matchedRule, .domainSuffix("apple.com", .direct))
    }
}
```

- [ ] **Step 2: Write storage tests**

Replace `packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift` with this content:

```swift
import XCTest
import IrockCore
@testable import IrockStorage

final class IrockStorageTests: XCTestCase {
    func testSnapshotStoreRoundTripsRuntimeSnapshotInMemory() throws {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo SS",
            protocolType: .shadowsocks,
            serverHost: "127.0.0.1",
            serverPort: 8388,
            credentials: .password("secret"),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
        let snapshot = RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: node, routeMode: .globalProxy, logLevel: .user)
        let store = InMemoryRuntimeSnapshotStore()

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
    }
}
```

- [ ] **Step 3: Write diagnostics tests**

Replace `packages/IrockDiagnostics/Tests/IrockDiagnosticsTests/IrockDiagnosticsTests.swift` with this content:

```swift
import XCTest
@testable import IrockDiagnostics

final class IrockDiagnosticsTests: XCTestCase {
    func testRingLogKeepsNewestEntries() {
        var log = RingConnectionLog(capacity: 2)
        log.append(ConnectionLogEntry(message: "first"))
        log.append(ConnectionLogEntry(message: "second"))
        log.append(ConnectionLogEntry(message: "third"))

        XCTAssertEqual(log.entries.map(\.message), ["second", "third"])
    }
}
```

- [ ] **Step 4: Write performance tests**

Replace `packages/IrockPerformanceKit/Tests/IrockPerformanceKitTests/IrockPerformanceKitTests.swift` with this content:

```swift
import XCTest
@testable import IrockPerformanceKit

final class IrockPerformanceKitTests: XCTestCase {
    func testPerformanceBudgetStoresAlphaTargets() {
        let budget = PerformanceBudget.alphaFlagship

        XCTAssertEqual(budget.minimumThroughputMbps, 600)
        XCTAssertEqual(budget.maximumAddedLatencyMs, 10)
        XCTAssertEqual(budget.maximumTunnelMemoryMB, 50)
    }
}
```

- [ ] **Step 5: Run baseline tests to verify failure**

Run:

```bash
swift test --filter 'IrockRoutingTests|IrockStorageTests|IrockDiagnosticsTests|IrockPerformanceKitTests'
```

Expected: FAIL because baseline types are not implemented.

- [ ] **Step 6: Implement routing baseline**

Replace `packages/IrockRouting/Sources/IrockRouting/IrockRouting.swift` with this content:

```swift
public enum RoutingAction: Equatable, Sendable {
    case direct
    case proxy
    case reject
}

public enum RoutingRule: Equatable, Sendable {
    case domainSuffix(String, RoutingAction)
    case final(RoutingAction)
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

public struct RoutingEngine: Sendable {
    private let rules: [RoutingRule]

    public init(rules: [RoutingRule]) {
        self.rules = rules
    }

    public func resolve(_ context: RoutingContext) -> RoutingDecision {
        for rule in rules {
            switch rule {
            case let .domainSuffix(suffix, action):
                if let host = context.host, host == suffix || host.hasSuffix("." + suffix) {
                    return RoutingDecision(action: action, matchedRule: rule)
                }
            case let .final(action):
                return RoutingDecision(action: action, matchedRule: rule)
            }
        }

        return RoutingDecision(action: .direct, matchedRule: nil)
    }
}
```

- [ ] **Step 7: Implement storage baseline**

Replace `packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift` with this content:

```swift
import IrockCore

public protocol RuntimeSnapshotStore {
    func save(_ snapshot: RuntimeSnapshot) throws
    func load() throws -> RuntimeSnapshot?
}

public final class InMemoryRuntimeSnapshotStore: RuntimeSnapshotStore {
    private var snapshot: RuntimeSnapshot?

    public init() {}

    public func save(_ snapshot: RuntimeSnapshot) throws {
        self.snapshot = snapshot
    }

    public func load() throws -> RuntimeSnapshot? {
        snapshot
    }
}
```

- [ ] **Step 8: Implement diagnostics baseline**

Replace `packages/IrockDiagnostics/Sources/IrockDiagnostics/IrockDiagnostics.swift` with this content:

```swift
public struct ConnectionLogEntry: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct RingConnectionLog: Equatable, Sendable {
    public private(set) var entries: [ConnectionLogEntry]
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.entries = []
    }

    public mutating func append(_ entry: ConnectionLogEntry) {
        guard capacity > 0 else { return }
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }
}
```

- [ ] **Step 9: Implement performance baseline**

Replace `packages/IrockPerformanceKit/Sources/IrockPerformanceKit/IrockPerformanceKit.swift` with this content:

```swift
public struct PerformanceBudget: Equatable, Sendable {
    public let minimumThroughputMbps: Int
    public let maximumAddedLatencyMs: Int
    public let maximumTunnelMemoryMB: Int

    public static let alphaFlagship = PerformanceBudget(
        minimumThroughputMbps: 600,
        maximumAddedLatencyMs: 10,
        maximumTunnelMemoryMB: 50
    )

    public init(minimumThroughputMbps: Int, maximumAddedLatencyMs: Int, maximumTunnelMemoryMB: Int) {
        self.minimumThroughputMbps = minimumThroughputMbps
        self.maximumAddedLatencyMs = maximumAddedLatencyMs
        self.maximumTunnelMemoryMB = maximumTunnelMemoryMB
    }
}
```

- [ ] **Step 10: Run baseline tests**

Run:

```bash
swift test --filter 'IrockRoutingTests|IrockStorageTests|IrockDiagnosticsTests|IrockPerformanceKitTests'
```

Expected: PASS.

- [ ] **Step 11: Run all tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 12: Commit baselines**

Run:

```bash
git add packages/IrockRouting packages/IrockStorage packages/IrockDiagnostics packages/IrockPerformanceKit
git commit -m "feat: add routing storage diagnostics and performance baselines"
```

Expected: commit succeeds.

---

### Task 6: Xcode workspace and Network Extension creation guide

**Files:**
- Create: `apps/XCODE_TARGETS.md`
- Modify: `README.md`

- [ ] **Step 1: Create Xcode target guide**

Create `apps/XCODE_TARGETS.md` with this content:

```markdown
# Xcode Targets

M0 establishes the exact Xcode target layout for implementation in the next phase.

## Workspace

Create `irock.xcworkspace` at the repository root.

Add the root Swift package to the workspace so app targets can depend on:

- `IrockCore`
- `IrockProtocols`
- `IrockRouting`
- `IrockTransport`
- `IrockStorage`
- `IrockDiagnostics`
- `IrockPerformanceKit`

## iOS targets

Create an iOS app project under `apps/irock-iOS/` with these targets:

- `irockApp`
- `irockTunnelExtension`

`irockApp` requirements:

- SwiftUI lifecycle
- Minimum iOS 17
- Depends on all shared irock packages
- Capabilities: App Groups, Keychain Sharing, Network Extensions

`irockTunnelExtension` requirements:

- Packet Tunnel Provider extension
- Depends on `IrockCore`, `IrockProtocols`, `IrockRouting`, `IrockTransport`, `IrockStorage`, `IrockDiagnostics`, `IrockPerformanceKit`
- Capabilities: App Groups, Keychain Sharing, Network Extensions

## macOS targets

Create a macOS app project under `apps/irock-macOS/` with these targets:

- `irockMacApp`
- `irockMacTunnelExtension`

`irockMacApp` requirements:

- SwiftUI lifecycle
- Minimum macOS 14
- Depends on all shared irock packages
- Capabilities: App Groups, Keychain Sharing, Network Extensions

`irockMacTunnelExtension` requirements:

- Packet Tunnel Provider extension
- Depends on `IrockCore`, `IrockProtocols`, `IrockRouting`, `IrockTransport`, `IrockStorage`, `IrockDiagnostics`, `IrockPerformanceKit`
- Capabilities: App Groups, Keychain Sharing, Network Extensions

## Signing placeholders

Use these placeholder identifiers until a real developer team is selected:

- Bundle ID: `com.irock.app.ios`
- iOS tunnel Bundle ID: `com.irock.app.ios.tunnel`
- macOS Bundle ID: `com.irock.app.macos`
- macOS tunnel Bundle ID: `com.irock.app.macos.tunnel`
- App Group: `group.com.irock.shared`

Do not commit local provisioning profiles, certificates, or private signing material.
```

- [ ] **Step 2: Link Xcode guide from README**

Replace `README.md` with this content:

```markdown
# irock

irock is a personal iOS/macOS network proxy client inspired by Shadowrocket's information architecture. The project uses Swift, SwiftUI, Network Extension, and shared Swift packages for protocol, routing, storage, diagnostics, and performance modules.

## Current phase

M0 builds the engineering foundation:

- SwiftPM package graph
- Core domain models
- Module boundaries
- XCTest baseline
- Xcode target creation instructions

## Design

See `docs/superpowers/specs/2026-05-09-irock-design.md`.

## Implementation plans

- M0: `docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md`

## Xcode targets

See `apps/XCODE_TARGETS.md` for the required iOS/macOS app and Packet Tunnel target layout.
```

- [ ] **Step 3: Run tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 4: Commit Xcode target guide**

Run:

```bash
git add README.md apps/XCODE_TARGETS.md
git commit -m "docs: define Xcode target layout"
```

Expected: commit succeeds.

---

### Task 7: M0 final verification

**Files:**
- No code changes expected unless verification reveals an issue.

- [ ] **Step 1: Run full Swift test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Confirm ignored planning/runtime scratch directories are not staged**

Run:

```bash
git status --short
```

Expected: `.omc/` and `.superpowers/` do not appear once `.gitignore` exists. If they still appear because they were staged accidentally, run:

```bash
git restore --staged .omc .superpowers
```

Expected: only intentional source/documentation changes remain.

- [ ] **Step 3: Inspect commit history**

Run:

```bash
git log --oneline --max-count=8
```

Expected: recent commits include:

```text
docs: define Xcode target layout
feat: add routing storage diagnostics and performance baselines
feat: add protocol and transport interfaces
feat: add core domain models
chore: add Swift package graph
chore: add repository skeleton
Add irock alpha design spec
```

- [ ] **Step 4: Record M0 completion status**

Run:

```bash
git status --short
```

Expected: clean working tree, except any untracked local-only scratch files ignored by `.gitignore`.

- [ ] **Step 5: Do not create a PR yet**

Do not create a PR for M0 unless explicitly requested. The next planning step is M1:基础 UI 与配置.
```

## Self-Review

Spec coverage for M0:

- Workspace/app target layout: covered by Task 6.
- Shared package boundaries: covered by Task 2.
- Core model language for nodes and runtime snapshots: covered by Task 3.
- Protocol/transport adapter seams: covered by Task 4.
- Routing/storage/diagnostics/performance baseline seams: covered by Task 5.
- Repository hygiene and scratch directory handling: covered by Task 1 and Task 7.

Known intentional deferrals:

- Actual Xcode target creation is deferred to the next executable phase because signing, App Group, and Network Extension capabilities require local Developer Team choices.
- Real Packet Tunnel code, SwiftUI screens, URI parsing, protocol implementations, and benchmark runners are outside M0 and belong to M1+.

Placeholder scan: no placeholder markers or unspecified implementation steps are required for M0 execution.

Type consistency check: `ProxyNode`, `RuntimeSnapshot`, `ProxyAdapter`, `TransportAdapter`, `RoutingEngine`, `InMemoryRuntimeSnapshotStore`, `RingConnectionLog`, and `PerformanceBudget` are introduced before later tests depend on them.
