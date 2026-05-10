# irock

irock is a personal iOS/macOS network proxy client inspired by Shadowrocket's information architecture. The project uses Swift, SwiftUI, Network Extension, and shared Swift packages for protocol, routing, storage, diagnostics, and performance modules.

## Current phase

The repository currently contains the M0 SwiftPM engineering foundation, M1 UI configuration scaffolding, M2 TUN data path core, M3 runtime snapshot persistence foundation, and M4 runtime snapshot publishing foundation:

- Shared package graph with core, protocol, routing, storage, diagnostics, performance, app feature, and tunnel core modules
- XCTest coverage for package boundaries, runtime snapshots, routing/storage behavior, file-backed snapshot persistence, app feature state, runtime snapshot publishing, packet parsing, flow tracking, and tunnel runtime processing
- Xcode target creation instructions; Xcode workspace, app targets, and Packet Tunnel targets are not yet committed

## Design

See `docs/superpowers/specs/2026-05-09-irock-design.md`.

## Implementation plans

- M0: `docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md`
- M1: `docs/superpowers/plans/2026-05-10-irock-m1-ui-configuration.md`
- M2: `docs/superpowers/plans/2026-05-10-irock-m2-tun-data-path.md`
- M3: `docs/superpowers/plans/2026-05-10-irock-m3-runtime-snapshot-persistence.md`
- M4: `docs/superpowers/plans/2026-05-10-irock-m4-runtime-snapshot-publishing.md`

## Xcode targets

See `apps/XCODE_TARGETS.md` for the required iOS/macOS app and Packet Tunnel target layout.
