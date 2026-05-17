# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`irock` is a Swift-first iOS/macOS network proxy client inspired by Shadowrocket's information architecture. The runtime is built from this repository's own Swift packages plus small native bindings; do not embed sing-box, xray, clash, or other full proxy cores in the app runtime. Those projects may be used only as development-time protocol comparison references.

The product/architecture spec is `docs/superpowers/specs/2026-05-09-irock-design.md`. Historical implementation plans live under `docs/superpowers/plans/`; treat them as background unless the user points to an active plan.

## Common commands

Native QUIC/Hysteria2 support depends on Homebrew system libraries used by SwiftPM and the app packaging script:

```sh
brew install libngtcp2 libnghttp3 openssl@3
```

SwiftPM from the repository root:

```sh
swift test
swift test --filter IrockCoreTests
swift test --filter IrockAppFeatureTests
swift test --filter IrockTunnelCoreTests
swift test --filter IrockProtocolsTests
swift test --filter IrockTransportTests
swift test --filter IrockToolingTests
swift test --filter XcodeScaffoldTests
```

Performance evidence from the repository root:

```sh
swift run irock-benchmark-runner packet-processor
swift run irock-benchmark-runner runtime-packet-batch
swift run irock-benchmark-runner routing-lookup
```

Platform builds:

```sh
apps/irock-macOS/build-unsigned-app.sh
xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios-simulator-derived-data CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

CI packaging is defined in `.github/workflows/package.yml`; it runs `swift test`, builds the unsigned macOS app, builds the iOS simulator app, and uploads zipped app artifacts under `build/artifacts/`.

No SwiftLint, SwiftFormat, Makefile, Cursor rules, or Copilot instructions are currently configured in this repository.

## High-level architecture

The root `Package.swift` is the shared package graph. Platform app projects under `apps/` consume these packages rather than owning reusable business logic.

- `IrockCore`: canonical domain models for proxy nodes, protocol/transport configuration, runtime snapshots, routing manifests, connection status, and log entries.
- `IrockTransport`: byte-stream and datagram abstractions plus TCP/TLS, WebSocket, HTTP/2, gRPC, QUIC, and Reality transport helpers.
- `IrockProtocols`: protocol adapters and handshakes for Shadowsocks, VMess, VLESS, Trojan, Hysteria2, TUIC, TrustTunnel, and related UDP/datagram behavior.
- `IrockRouting`: Clash-like local rule parsing, precompilation, and routing decisions.
- `IrockStorage`: in-memory and file-backed configuration/runtime stores, including App Group-ready runtime snapshot, status, and log persistence.
- `IrockDiagnostics`: user-facing diagnostics assembled from core, protocol, routing, and transport errors.
- `IrockPerformanceKit`: throughput, latency, memory, handshake, and rule-matching measurement primitives.
- `IrockAppFeature`: shared SwiftUI app state, views, URI import, node selection, runtime snapshot publishing, local proxy mode, and user-mode TUN state.
- `IrockTunnelCore`: packet parsing/processing, flow tracking, runtime routing adaptation, proxy outbound execution, tunnel controllers, and packet batch runtime.
- `IrockTooling`: readiness checks and benchmark scenarios used by `irock-benchmark-runner` and scaffold tests.
- `IrockNativeHysteria2`: Swift/C wrappers around ngtcp2, nghttp3, and OpenSSL for native QUIC/Hysteria2 support.

The main data boundary is `RuntimeSnapshot`: app-facing configuration is edited and published by `IrockAppFeature`/platform apps, persisted through `IrockStorage`, then loaded by `IrockTunnelCore` and platform Packet Tunnel runners. Keep platform-specific APIs such as NetworkExtension, Network, AppKit/UIKit, TUN device management, and signing concerns inside `apps/irock-iOS` or `apps/irock-macOS`.

## Platform app layout

`apps/irock-macOS` contains the committed macOS Xcode project:

- `irockMacApp`: SwiftUI shell hosting shared `IrockAppFeature` UI plus macOS local proxy, VPN manager, user-mode TUN, App Group store resolution, and platform TLS/TCP glue.
- `irockMacTunnelExtension`: Packet Tunnel extension shell that wires NetworkExtension packet flow into `IrockTunnelCore` with macOS TCP/UDP adapters.
- `build-unsigned-app.sh`: local Debug unsigned app build that copies required Homebrew dylibs into the app bundle and ad-hoc signs it.

Unsigned macOS builds support UI, Shadowsocks URI import, runtime snapshot publishing, and local proxy mode. Local proxy listeners are SOCKS5 `127.0.0.1:10808` and HTTP CONNECT `127.0.0.1:10809`; the app shows `networksetup` commands but does not silently mutate system proxy settings. Unsigned builds cannot install/start the Packet Tunnel extension, and user-mode TUN requires administrator authorization.

`apps/irock-iOS` contains the committed iOS Xcode project:

- `irockApp`: SwiftUI shell hosting shared `IrockAppFeature` UI plus iOS VPN manager and App Group store resolution.
- `irockTunnelExtension`: Packet Tunnel extension shell that wires NetworkExtension packet flow into `IrockTunnelCore` with iOS platform TCP glue.

Signing files and identifiers in app directories are placeholders. Do not commit real Team IDs, provisioning profiles, certificates, private keys, or real server credentials in fixtures.

## Repository-specific guidance

- Keep platform app code thin; reusable protocol, routing, storage, diagnostics, performance, and runtime behavior belongs in shared packages.
- Treat Packet Tunnel hot paths as performance-sensitive: avoid database access, unbounded logging, and unnecessary allocations in packet processing.
- Use `RuntimeSnapshot` as the boundary between editable app configuration and tunnel runtime state.
- Keep `.omc/`, `.superpowers/`, and `.serena/` out of commits; they are local planning/runtime state.
- Keep Shadowrocket similarity at the information-architecture level; do not copy proprietary assets, exact visuals, or product identity.
