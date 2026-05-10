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
- M1: `docs/superpowers/plans/2026-05-10-irock-m1-ui-configuration.md`

## Xcode targets

See `apps/XCODE_TARGETS.md` for the required iOS/macOS app and Packet Tunnel target layout.
