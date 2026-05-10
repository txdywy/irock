# irock M10 Runtime Status and Logs Design

Date: 2026-05-10

## Goal

M10 adds the shared runtime feedback boundary between the future main app and Packet Tunnel extension. The app already publishes `RuntimeSnapshot` data for the tunnel to consume; M10 adds the reverse direction: the tunnel can publish its current connection status and bounded user-facing log entries for the app to read.

This milestone stays inside SwiftPM shared packages. It does not create Xcode app targets, Packet Tunnel extension targets, signing configuration, or real Network Extension integration.

## Scope

In scope:

- Define runtime connection status and runtime log entry models in `IrockCore`.
- Add App Group-ready file-backed status and log stores in `IrockStorage`.
- Add in-memory stores for tests and app preview logic.
- Let `IrockTunnelCore` publish status transitions around runtime start, packet processing, stop, and failure paths.
- Let `IrockAppFeature` read runtime status and logs into app-facing view-model state.
- Cover model codability, bounded log behavior, storage round trips, tunnel status publication, and app refresh behavior with SwiftPM tests.

Out of scope:

- Real `NEPacketTunnelProvider` lifecycle integration.
- Actual VPN connect/disconnect controls.
- Protocol-specific handshake logging.
- Per-request traffic logging.
- Persistent debug-level packet traces.
- UI pixel work in platform app targets.

## Current Context

M5-M9 established the routing configuration path:

```text
App local routing text
  -> RoutingRuleParser
  -> RuntimeRoutingRuleManifest
  -> RuntimeSnapshotPublisher
  -> RuntimeSnapshot
  -> TunnelRuntimeConfiguration
  -> RoutingEngine
```

The missing counterpart is runtime feedback:

```text
Tunnel runtime event
  -> RuntimeStatusStore / RuntimeLogStore
  -> AppViewModel refresh
  -> future UI status and logs
```

M10 creates that second path without depending on platform-specific app or extension targets.

## Core Models

`IrockCore` adds `RuntimeConnectionStatus` as the durable status model:

```swift
public enum RuntimeConnectionPhase: String, Codable, Sendable {
    case disconnected
    case preparing
    case connecting
    case connected
    case reconnecting
    case disconnecting
    case failed
}

public struct RuntimeConnectionStatus: Equatable, Codable, Sendable {
    public let phase: RuntimeConnectionPhase
    public let selectedNodeID: NodeID?
    public let selectedNodeName: String?
    public let updatedAt: Date
    public let message: String?
}
```

The app can map these seven phases to the simpler user-facing states from the product design: not connected, connecting, connected, and failed.

`IrockCore` also adds `RuntimeLogEntry`:

```swift
public enum RuntimeLogLevel: String, Codable, Sendable {
    case user
    case debug
}

public struct RuntimeLogEntry: Equatable, Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let level: RuntimeLogLevel
    public let message: String
    public let nodeID: NodeID?
    public let phase: RuntimeConnectionPhase?
}
```

Default tunnel logs use `.user`. Debug logs are allowed by the model, but M10 only records coarse lifecycle and failure events.

## Storage Boundary

`IrockStorage` adds two protocols:

```swift
public protocol RuntimeStatusStore: Sendable {
    func save(_ status: RuntimeConnectionStatus) throws
    func load() throws -> RuntimeConnectionStatus?
}

public protocol RuntimeLogStore: Sendable {
    func append(_ entry: RuntimeLogEntry) throws
    func loadRecent() throws -> [RuntimeLogEntry]
    func clear() throws
}
```

Concrete implementations:

- `InMemoryRuntimeStatusStore`
- `InMemoryRuntimeLogStore`
- `FileRuntimeStatusStore`
- `FileRuntimeLogStore`

The file-backed stores use one JSON file each under a caller-provided directory:

```text
runtime-status.json
runtime-logs.json
```

The log store enforces a fixed maximum entry count at append time and keeps the newest entries. The default maximum is 200 entries, which is enough for user-visible lifecycle history without turning the App Group into a packet/request log sink.

Corrupt JSON should throw to the caller rather than silently reset state. The app-facing layer can turn that into a visible failed refresh or log message later.

## TunnelCore Integration

`IrockTunnelCore` adds a small reporter abstraction around the stores:

```swift
public struct TunnelRuntimeReporter: Sendable {
    public func publishStatus(_ status: RuntimeConnectionStatus) throws
    public func appendLog(_ entry: RuntimeLogEntry) throws
}
```

`PacketTunnelRuntime` accepts an optional reporter. When present, it publishes:

1. `.preparing` before the runtime starts processing a batch.
2. `.connected` after a batch is processed successfully.
3. `.failed` and a user log entry if packet processing throws.
4. `.disconnected` when the runtime is explicitly stopped by future callers.

The existing packet processing tests remain deterministic because M10 will use injected in-memory stores and explicit dates where tests need stable comparisons.

M10 does not log each packet, route decision, or flow. That would violate the product constraint that default logs stay small and user-facing.

## AppFeature Integration

`AppViewModel` gains app-facing runtime feedback state:

```swift
public private(set) var runtimeConnectionStatus: RuntimeConnectionStatus?
public private(set) var runtimeLogs: [RuntimeLogEntry]
```

It also gains a refresh method:

```swift
public func refreshRuntimeFeedback() -> RuntimeFeedbackRefreshResult
```

The result distinguishes success from status/log storage failures. This keeps UI-facing code from pretending stale runtime feedback is fresh.

The view model reads from injected `RuntimeStatusStore` and `RuntimeLogStore`, defaulting to in-memory stores until platform app shells provide real App Group directories.

## Error Handling

Storage-level failures throw from `IrockStorage`. `IrockTunnelCore` should propagate reporter write failures from explicit reporter calls in tests, but packet processing should not fail solely because status/log publication failed. The reporter should be called through a narrow helper that records reporter failure as a debug-level concern when debug logging is enabled in future milestones.

For M10, the app refresh result exposes:

```swift
public enum RuntimeFeedbackRefreshResult: Equatable, Sendable {
    case refreshed
    case statusLoadFailed(String)
    case logLoadFailed(String)
}
```

If both status and logs fail, status failure wins because the homepage status is more important than the log list.

## Testing Strategy

Add SwiftPM tests for:

- `RuntimeConnectionStatus` and `RuntimeLogEntry` Codable round trips.
- In-memory status and log stores.
- File status store save/load/missing/corrupt JSON behavior.
- File log store append/load/bounded newest-entry behavior/clear/corrupt JSON behavior.
- Tunnel reporter writes status and logs into injected stores.
- `PacketTunnelRuntime` publishes preparing and connected around successful processing.
- `PacketTunnelRuntime` publishes failed status when processing fails.
- `AppViewModel.refreshRuntimeFeedback()` loads status and logs from injected stores.

Full acceptance requires `swift test` passing.

## Implementation Boundaries

M10 should keep edits focused on:

```text
packages/IrockCore/Sources/IrockCore/IrockCore.swift
packages/IrockCore/Tests/IrockCoreTests/IrockCoreTests.swift
packages/IrockStorage/Sources/IrockStorage/IrockStorage.swift
packages/IrockStorage/Tests/IrockStorageTests/IrockStorageTests.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/PacketTunnelRuntime.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/TunnelRuntimeReporter.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/PacketTunnelRuntimeTests.swift
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/TunnelRuntimeReporterTests.swift
packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift
packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
```

No new package target is needed.

## Success Criteria

M10 is complete when:

- Runtime status and log models are codable, equatable, and sendable.
- App Group-ready file stores round-trip status and bounded logs.
- Tunnel runtime can publish lifecycle status without knowing about UI code.
- App view model can refresh runtime status and logs without knowing about tunnel internals.
- Default logging remains lifecycle-level, not per-packet or per-request.
- `swift test` passes.
