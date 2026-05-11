# M33 Runtime Snapshot to Real Provider Flow Design

Date: 2026-05-11

## Goal

Connect app-side runtime snapshot publishing to the Packet Tunnel provider startup path through a shared App Group-backed runtime store, with basic status/log feedback visible to app-facing state.

## Current State

- `AppViewModel` can publish a `RuntimeSnapshot` through any injected `RuntimeSnapshotStore`.
- `IOSVPNManager` can install/start/stop/query the Packet Tunnel configuration but does not publish snapshots.
- The Packet Tunnel extension resolves `group.dev.irock.shared` through `PacketTunnelAppGroupStoreResolver` and reads a snapshot before startup.
- `RuntimeStoreBundle.fileBacked` already creates snapshot, status, and log stores rooted at `Runtime/` under a container URL.
- The iOS app target does not yet resolve the App Group runtime store or inject it into the shared `AppViewModel`.

## Design

Add an iOS app-local App Group runtime store resolver mirroring the extension-side resolver:

- `IOSAppGroupRuntimeStoreResolver` resolves `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
- It returns `RuntimeStoreBundle` using `AppGroupRuntimeStoreDirectory`.
- It uses the same placeholder App Group identifier as the extension: `group.dev.irock.shared`.

Wire `ContentView` through a small factory method:

- Try to create `AppViewModel` backed by App Group file stores.
- If the App Group container cannot be resolved in unsigned/simulator contexts, fall back to the existing in-memory stores so the UI still builds and previews.
- Keep the fallback in the app shell only; shared packages remain platform-neutral.

Strengthen extension tests so the provider path is explicitly tied to the same App Group identifier and to `RuntimeStoreBundle` status/log/snapshot stores. M33 remains automatable without real provisioning by validating the shared file-store boundary statically and through existing storage tests.

## Scope

In scope:

- Add app-side App Group runtime store resolver.
- Inject App Group-backed stores into `AppViewModel` from the iOS container app shell.
- Preserve fallback behavior for unsigned simulator builds.
- Verify the provider reads snapshot/status/log stores from the same App Group boundary.
- Verify UI-facing state can refresh status/logs through shared `AppViewModel` tests already in place.

Out of scope:

- Real device VPN startup.
- Apple Developer Team, provisioning profile, or entitlement replacement.
- Subscription/profile UI.
- Secrets or credential storage.
- Full start/stop UI controls beyond the manager seam established in M32.

## Validation

- Static scaffold tests assert app and extension use the same App Group identifier and `RuntimeStoreBundle` boundary.
- Static scaffold tests assert `ContentView` injects App Group-backed stores and keeps an in-memory fallback.
- Existing AppFeature tests continue to verify runtime feedback state mapping.
- Existing Storage tests continue to verify file-backed runtime bundle round trips.
- Full `swift test` passes.
- Unsigned iOS simulator build passes.
- Platform import boundary scan remains clean.
