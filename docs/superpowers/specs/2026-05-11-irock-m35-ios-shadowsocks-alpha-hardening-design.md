# M35 iOS Shadowsocks Alpha Hardening Design

Date: 2026-05-11

## Goal

Stabilize the first usable iOS Shadowsocks Alpha path by making startup, connected, stopped, and failed runtime states observable through deterministic status and log transitions.

## Current State

- The iOS app can publish runtime snapshots into the shared App Group boundary when local provisioning supports it.
- The Packet Tunnel provider applies runtime settings, validates startup, and launches a cancellable loop runner.
- `TunnelRuntimeController` reports a missing runtime snapshot as a failed status and user log.
- `PacketTunnelRuntime` reports preparing, connected, and packet/proxy failures through `RuntimeStatusStore` and `RuntimeLogStore`.
- Real-device signing, App Group provisioning, and live Shadowsocks node validation remain external local inputs.

## Design

Add a small runtime diagnostics taxonomy inside `IrockTunnelCore` rather than introducing a new logging subsystem. The taxonomy maps known Alpha failure surfaces to stable, user-safe messages:

- missing snapshot: `Runtime snapshot unavailable`
- App Group/runtime store failure: `Runtime store unavailable`
- proxy connection failure: `Proxy adapter failed: ...`
- packet-loop failure: `Packet batch failed`
- stopped provider lifecycle: `Tunnel stopped`

The shared package remains platform-neutral. iOS-specific App Group and Network Extension code stays under `apps/irock-iOS/`, with static tooling tests verifying the provider has a stop-reporting boundary and that manual real-device validation steps mention the M35 diagnostic expectations.

## Scope

In scope:

- Add deterministic diagnostics helpers for runtime store failure and stopped lifecycle reporting.
- Add regression tests for startup/preparing, connected, stopped, missing snapshot, connection failure, packet-loop failure, and reporter/store failure behavior.
- Add a M35 manual Alpha validation note that records real-node/device validation as externally blocked unless local credentials and devices are available.
- Keep SwiftPM tests and unsigned iOS simulator build passing.

Out of scope:

- Adding new protocols or transports.
- macOS parity.
- Storing real Shadowsocks credentials, Apple signing secrets, provisioning profiles, or live-node details in the repository.
- Automating device-only Packet Tunnel validation in this environment.

## Validation

- `swift test --filter IrockTunnelCoreTests` verifies runtime diagnostics and status/log transitions.
- `swift test --filter IrockToolingTests` verifies the iOS scaffold exposes the M35 lifecycle boundaries and documentation.
- Full `swift test` passes.
- Unsigned iOS simulator build passes with `CODE_SIGNING_ALLOWED=NO`.
- Manual real-device Shadowsocks validation is documented as passed only when local credentials/provisioning are available; otherwise it remains an explicit external blocker.
