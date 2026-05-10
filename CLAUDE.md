# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

irock has a SwiftPM package graph and M1 app feature configuration scaffolding in the working tree. The committed product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Implementation plans live under `docs/superpowers/plans/`, including M0 engineering foundation and M1 UI configuration.

There is not yet an Xcode workspace, app target, or Packet Tunnel target in the working tree. Do not assume `xcodebuild` or app schemes exist until Xcode targets are created.

## Intended architecture

The project is planned as a Swift-first iOS/macOS network proxy client with:

- Thin iOS/macOS SwiftUI app shells.
- iOS/macOS Packet Tunnel extensions for system-level TUN VPN.
- Shared Swift packages for core models, protocols, transport, routing, storage, diagnostics, and performance.
- App Group runtime snapshots between the main app and tunnel extension.
- Local-first storage; no iCloud, account system, or backend in the Alpha scope.

Planned package boundaries:

- `IrockCore`: shared domain types such as nodes, runtime snapshots, connection state, and errors.
- `IrockProtocols`: protocol adapters for Shadowsocks, VMess, VLESS, Trojan, Hysteria2, TUIC, and Reality-related behavior.
- `IrockTransport`: TCP, TLS, WebSocket, HTTP/2, gRPC, and QUIC transport abstractions.
- `IrockRouting`: rule parsing, rule precompilation, and routing decisions.
- `IrockStorage`: local configuration, App Group snapshots, credentials, and basic logs.
- `IrockDiagnostics`: user-facing logs, debug logs, and error presentation.
- `IrockPerformanceKit`: throughput, latency, memory, handshake, and rule-matching measurements.

The app runtime must not embed sing-box, xray, clash, or other full proxy cores. They may be used only as development-time protocol comparison references.

## Planned repository structure

M0 is expected to create this structure:

```text
Package.swift
apps/
  irock-iOS/
  irock-macOS/
packages/
  IrockCore/
  IrockProtocols/
  IrockRouting/
  IrockTransport/
  IrockStorage/
  IrockDiagnostics/
  IrockPerformanceKit/
tools/
  protocol-lab/
  benchmark-runner/
  config-fixtures/
tests/
  protocol-fixtures/
  routing-fixtures/
  performance-baselines/
```

Xcode workspace and Network Extension targets are planned after the SwiftPM foundation is in place because signing, App Groups, and Network Extension capabilities depend on local Apple Developer Team choices.

## Commands

Current state:

- Inspect git state: `git status --short`
- Review the design spec: `less docs/superpowers/specs/2026-05-09-irock-design.md`
- Review the M0 plan: `less docs/superpowers/plans/2026-05-09-irock-m0-engineering-foundation.md`

After M0 creates `Package.swift`:

- Run all SwiftPM tests: `swift test`
- Run a single test target: `swift test --filter IrockCoreTests`
- Run app feature tests: `swift test --filter IrockAppFeatureTests`

After Xcode targets exist, add concrete `xcodebuild` commands here based on the actual workspace, schemes, and signing setup.

## Development guidance specific to this repo

- Follow the M0 plan before starting app or protocol implementation.
- Keep `.omc/` and `.superpowers/` out of commits; they are planning/runtime scratch state.
- Keep platform app code thin and put reusable logic in shared Swift packages.
- Treat Packet Tunnel hot paths as performance-sensitive: avoid database access, unbounded logging, and unnecessary allocations in packet processing.
- Use `RuntimeSnapshot` as the boundary between editable app configuration and tunnel runtime state.
- Keep Shadowrocket similarity at the information-architecture level; do not copy proprietary assets, exact visuals, or product identity.
