# M21 Tunnel Runtime Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a deterministic bootstrap builder that assembles a fully wired `PacketTunnelRuntime` from snapshot, packet I/O, runtime stores, and plain/TLS transport adapters.

**Architecture:** `TunnelRuntimeBootstrap` lives in `IrockTunnelCore` and delegates stack construction to the M20 `TunnelRuntimeConfiguration.shadowsocksTCP(...)` helper. It creates a `TunnelRuntimeReporter` from runtime stores and returns `PacketTunnelRuntime<Reader, Writer>` without platform-specific dependencies.

**Tech Stack:** Swift Package Manager, XCTest, `IrockCore`, `IrockStorage`, `IrockTransport`, `IrockTunnelCore`.

---

## Files

- Create: `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeBootstrap.swift`
- Create: `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeBootstrapTests.swift`
- Verify: `Package.swift`

## Task 1: Add bootstrap success-path test

- [x] **Step 1: Write failing test**

Create `packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeBootstrapTests.swift` with a test named `testShadowsocksTCPBootstrapBuildsRuntimeWithPlainTransport`.

The test should:

- create `RecordingTransportAdapter` instances for plain and TLS;
- create `InMemoryPacketReader` with one IPv4 TCP packet;
- create `InMemoryPacketWriter`;
- create `InMemoryRuntimeStatusStore` and `InMemoryRuntimeLogStore`;
- call `TunnelRuntimeBootstrap.shadowsocksTCP(...)`;
- run the returned runtime once;
- assert one packet was read/written, one proxy connection happened, plain received one request, TLS received none, and connected status/logs were published.

- [x] **Step 2: Verify RED**

Run:

```bash
swift test --filter 'TunnelRuntimeBootstrapTests/testShadowsocksTCPBootstrapBuildsRuntimeWithPlainTransport'
```

Expected: compile failure because `TunnelRuntimeBootstrap` is not defined.

- [x] **Step 3: Implement minimal bootstrap**

Create `packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeBootstrap.swift`:

```swift
import IrockCore
import IrockStorage
import IrockTransport

public struct TunnelRuntimeBootstrap: Sendable {
    public static func shadowsocksTCP<Reader: PacketReader, Writer: PacketWriter, Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        reader: Reader,
        writer: Writer,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<Reader, Writer> {
        let configuration = try TunnelRuntimeConfiguration.shadowsocksTCP(
            snapshot: snapshot,
            plain: plain,
            tls: tls,
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        return PacketTunnelRuntime(reader: reader, writer: writer, configuration: configuration, reporter: reporter)
    }
}
```

- [x] **Step 4: Verify GREEN**

Run:

```bash
swift test --filter 'TunnelRuntimeBootstrapTests/testShadowsocksTCPBootstrapBuildsRuntimeWithPlainTransport'
```

Expected: PASS.

## Task 2: Cover configuration and failure behavior

- [x] **Step 1: Add invalid routing manifest test**

Add `testShadowsocksTCPBootstrapPropagatesInvalidRoutingManifest`.

The test should pass a snapshot whose `routingRuleManifest` contains an invalid rule shape already rejected by `RuntimeRoutingRuleAdapter`, call the bootstrap method, and assert it throws the existing routing adapter error.

- [x] **Step 2: Verify focused test**

Run:

```bash
swift test --filter 'TunnelRuntimeBootstrapTests/testShadowsocksTCPBootstrapPropagatesInvalidRoutingManifest'
```

Expected: PASS after the Task 1 implementation.

- [x] **Step 3: Add TLS failure reporting test**

Add `testShadowsocksTCPBootstrapPublishesFailureWhenTLSChildFails`.

The test should build a TLS-enabled snapshot, use a failing TLS child, run the bootstrapped runtime, assert the mapped `ProxyProtocolError.tlsHandshakeFailed("transport tls handshake failed")`, assert plain received no request, writer wrote no results, and status/log stores contain safe failure messages.

- [x] **Step 4: Verify focused test**

Run:

```bash
swift test --filter 'TunnelRuntimeBootstrapTests/testShadowsocksTCPBootstrapPublishesFailureWhenTLSChildFails'
```

Expected: PASS.

## Task 3: Full verification

- [x] **Step 1: Run tunnel core tests**

```bash
swift test --filter IrockTunnelCoreTests
```

Expected: PASS.

- [x] **Step 2: Run full package tests**

```bash
swift test
```

Expected: PASS.

- [x] **Step 3: Scan forbidden platform imports**

```bash
grep -R "import Network\|import Security\|import NetworkExtension" -n packages/IrockTunnelCore packages/IrockProtocols packages/IrockTransport Package.swift || true
```

Expected: no output.
