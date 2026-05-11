# M24 App Group Runtime Store Boundary Design

Date: 2026-05-11

## Goal

M24 adds a platform-neutral runtime store boundary that lets future app and Packet Tunnel targets share the same file-backed runtime snapshot, status, and logs through a single container directory convention.

The boundary remains SwiftPM-testable and does not import `NetworkExtension`, `Network`, `Security`, UIKit, AppKit, or entitlement-specific APIs.

## Context

M3 introduced `RuntimeSnapshotStore`, `RuntimeStatusStore`, and `RuntimeLogStore` with in-memory and file-backed implementations in `IrockStorage`.

M22 introduced `PacketFlowIO` and `PacketFlowRuntimeIO`, allowing a future platform packet flow to feed the runtime without importing platform networking frameworks into `IrockTunnelCore`.

M23 introduced `TunnelRuntimeController.runShadowsocksTCPBatch(...)`, which needs injected runtime stores plus packet flow and transport adapters. A future app target will publish a `RuntimeSnapshot`, while a future Packet Tunnel extension will load it and publish status/log updates. Both sides need a shared storage convention before real App Group APIs, Xcode targets, signing, and entitlements are introduced.

## Scope

In scope:

- Add a small runtime store bundle type in `IrockStorage` that groups snapshot, status, and log stores.
- Add a platform-neutral App Group runtime directory convention that derives the runtime subdirectory from a caller-provided container URL.
- Provide a file-backed bundle factory that composes the existing `FileRuntimeSnapshotStore`, `FileRuntimeStatusStore`, and `FileRuntimeLogStore`.
- Preserve existing file names and file store behavior:
  - `runtime-snapshot.json`
  - `runtime-status.json`
  - `runtime-logs.json`
- Allow tests to simulate app/tunnel sharing by creating two bundles pointing at the same temporary container directory.
- Cover shared snapshot/status/log round trips, missing values, log limit behavior, and deterministic directory derivation.

Out of scope:

- Calling `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` or any other real App Group API.
- Xcode workspace, app targets, Packet Tunnel extension targets, signing, entitlements, provisioning profiles, or App Group identifiers.
- File coordination, cross-process locking, Darwin notifications, live refresh watchers, migrations, encryption, or credential storage.
- Changing the existing runtime store protocols or file formats.
- Changing `TunnelRuntimeController` or packet runtime behavior.

## Component Design

### RuntimeStoreBundle

Add `RuntimeStoreBundle` to `IrockStorage`:

```swift
public struct RuntimeStoreBundle: Sendable {
    public let snapshotStore: any RuntimeSnapshotStore
    public let statusStore: any RuntimeStatusStore
    public let logStore: any RuntimeLogStore

    public init(
        snapshotStore: any RuntimeSnapshotStore,
        statusStore: any RuntimeStatusStore,
        logStore: any RuntimeLogStore
    )

    public static func fileBacked(
        directoryURL: URL,
        logLimit: Int = 200,
        fileManager: FileManager = .default
    ) -> RuntimeStoreBundle
}
```

Behavior:

1. The initializer stores the three injected store instances without wrapping or changing their behavior.
2. `fileBacked(directoryURL:logLimit:fileManager:)` returns a bundle whose stores all point to the same runtime directory.
3. The snapshot and status stores use existing default encoders/decoders.
4. The log store receives the supplied `logLimit`.
5. Store errors keep their existing behavior because the bundle only composes stores.

This gives future app and tunnel shell code a single dependency to pass around when they want the complete runtime storage surface.

### AppGroupRuntimeStoreDirectory

Add `AppGroupRuntimeStoreDirectory` to `IrockStorage`:

```swift
public struct AppGroupRuntimeStoreDirectory: Equatable, Sendable {
    public let containerURL: URL
    public var runtimeDirectoryURL: URL { get }

    public init(containerURL: URL)

    public func makeRuntimeStoreBundle(
        logLimit: Int = 200,
        fileManager: FileManager = .default
    ) -> RuntimeStoreBundle
}
```

Behavior:

1. The type accepts a caller-provided container URL. In production this URL can come from a platform target that has entitlement access. In tests it can be a temporary directory.
2. `runtimeDirectoryURL` appends `Runtime` to the container URL as a directory.
3. `makeRuntimeStoreBundle(logLimit:fileManager:)` returns `RuntimeStoreBundle.fileBacked(directoryURL: runtimeDirectoryURL, logLimit: logLimit, fileManager: fileManager)`.

The type intentionally does not accept an App Group identifier string. Resolving an identifier into a container URL is platform shell work and belongs outside shared SwiftPM packages.

## Data Flow

Future app-side snapshot publication:

```text
Platform app target
  -> resolves App Group container URL using platform API
  -> AppGroupRuntimeStoreDirectory(containerURL: containerURL)
  -> makeRuntimeStoreBundle()
  -> snapshotStore.save(runtimeSnapshot)
```

Future tunnel-side startup:

```text
Packet Tunnel target
  -> resolves same App Group container URL using platform API
  -> AppGroupRuntimeStoreDirectory(containerURL: containerURL)
  -> makeRuntimeStoreBundle()
  -> TunnelRuntimeController.runShadowsocksTCPBatch(snapshotStore: bundle.snapshotStore, ...)
```

SwiftPM test simulation:

```text
Temporary directory
  -> AppGroupRuntimeStoreDirectory(containerURL: temp)
  -> app bundle saves snapshot
  -> second AppGroupRuntimeStoreDirectory(containerURL: temp)
  -> tunnel bundle loads same snapshot
```

## Error Handling

M24 introduces no new error type.

- Missing snapshot/status values keep the existing file store behavior: load returns `nil` when the corresponding file is absent.
- Corrupt JSON, directory creation failures, file read failures, file write failures, and decode failures propagate from the existing file stores unchanged.
- `RuntimeStoreBundle` does not catch or translate errors.
- `AppGroupRuntimeStoreDirectory` does not create directories by itself; existing file stores create the runtime directory when saving or clearing.

## Testing Strategy

Add tests in `IrockStorageTests`.

Required tests:

1. `AppGroupRuntimeStoreDirectory` derives `<container>/Runtime` deterministically.
2. `makeRuntimeStoreBundle(...)` can round-trip snapshot, status, and logs through one temporary container directory.
3. Two bundles created from the same container URL share state, simulating app and tunnel targets using the same App Group container.
4. File-backed bundles return `nil` for missing snapshot and status values and `[]` for missing logs.
5. The bundle respects the supplied log limit.
6. The direct `RuntimeStoreBundle` initializer preserves explicitly injected store instances.

Full acceptance requires:

```bash
swift test --filter IrockStorageTests
swift test
grep -R "import Network\|import Security\|import NetworkExtension\|import UIKit\|import AppKit" -n packages/IrockStorage packages/IrockTunnelCore packages/IrockProtocols packages/IrockTransport Package.swift || true
```

## Success Criteria

M24 is complete when:

- Future platform shells have one platform-neutral way to construct the snapshot/status/log stores for a shared runtime directory.
- Existing file-backed store behavior and formats remain unchanged.
- App/tunnel sharing can be simulated through two bundles pointed at the same temporary container directory.
- Shared SwiftPM packages still avoid platform networking, App Group, signing, and entitlement APIs.
- `swift test` passes.
