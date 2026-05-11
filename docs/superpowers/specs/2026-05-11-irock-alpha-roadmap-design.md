# irock Alpha Roadmap Design

Date: 2026-05-11

## Goal

Define the remaining milestone sequence from the current M26 baseline to a usable iOS Shadowsocks Alpha, then to the broader technical Alpha described in the original project design.

## Current Baseline

Completed through M26:

- SwiftPM package graph and shared boundaries exist.
- App configuration, runtime snapshot persistence, publishing, status, logs, routing manifests, and rule adapters exist.
- Protocol, transport, Shadowsocks, TCP/TLS, and runtime proxy stack seams exist.
- Packet-flow runtime boundary, tunnel runtime controller, App Group runtime store boundary, and iOS Xcode Packet Tunnel scaffold exist.
- The iOS Packet Tunnel extension now has a smoke path that compiles unsigned for iOS Simulator and connects the provider to the App Group/runtime controller seams.

The project is not yet a live VPN client. The remaining work starts at real Packet Tunnel settings, live packet loop, platform networking, and end-to-end Shadowsocks connectivity.

## Execution Mode

Use a continuous autonomous loop for each milestone:

1. Design the next milestone with explicit scope and out-of-scope boundaries.
2. Write a TDD/static-validation implementation plan.
3. Execute the plan with focused commits.
4. Verify with SwiftPM tests, Xcode checks, import-boundary scans, and milestone-specific validation.
5. Use an independent review pass where practical.
6. Push, create PR, squash merge, delete remote branch, and clean local branches/worktrees.
7. Continue to the next milestone without asking for routine confirmation.

Stop only for external blockers such as Apple Developer account access, signing identities, real App Group provisioning, device-only Network Extension limitations, paid service credentials, destructive git actions that are not already covered by the project authorization, or failures that require product direction rather than engineering judgment.

## Phase 1: Usable iOS Shadowsocks Alpha

Target: one manually configured Shadowsocks node can be connected from the iOS app through the Packet Tunnel extension on a real signed environment, with basic status and logs.

### M27 Packet Tunnel Runtime Settings

Add the first real `NEPacketTunnelNetworkSettings` construction path for the extension.

Scope:

- Configure IPv4 tunnel address, included routes, DNS servers, and MTU defaults.
- Keep values deterministic and configurable through extension-local code.
- Validate through Xcode build and static tests.

Out of scope:

- Full routing policy UI.
- Production DNS strategy.
- Per-app VPN or advanced route exclusions.

### M28 Packet Tunnel Long-Running Packet Loop

Replace one-shot smoke execution with a cancellable provider lifecycle loop.

Scope:

- Start settings first, then run repeated packet batches.
- Stop cleanly on `stopTunnel(with:)`.
- Avoid unbounded tasks and logs.

Out of scope:

- High-throughput optimization.
- UDP proxy completeness.

### M29 Platform TCP Dialer

Add an iOS/macOS platform-local TCP dialer implementation behind the existing `TCPDialer` seam.

Scope:

- Use platform code outside shared packages or behind a platform target boundary.
- Preserve shared package import boundaries.
- Build in Xcode without requiring live remote nodes.

Out of scope:

- TLS socket wrapping beyond existing TLS adapter semantics.
- WebSocket, HTTP/2, gRPC, or QUIC.

### M30 Real Shadowsocks Stream Path

Turn the Shadowsocks adapter from validation/delegation into a real encrypted outbound stream path for Alpha-supported ciphers.

Scope:

- Implement one secure Alpha cipher path first.
- Add fixtures for request framing and encrypted payload shape.
- Connect protocol adapter to transport connection semantics.

Out of scope:

- Shadowsocks plugin ecosystem.
- UDP associate completeness unless required for the first Alpha path.

### M31 Packet to Proxy Response Loop

Complete the minimal response path from packet processing to remote proxy and back to `NEPacketTunnelFlow`.

Scope:

- Maintain flow identity.
- Write direct/proxy results back only when packet semantics are valid.
- Add bounded failure reporting.

Out of scope:

- Advanced congestion control.
- Large-scale flow table tuning.

### M32 Container App VPN Manager Integration

Let the iOS app install/update/start/stop the Packet Tunnel configuration.

Scope:

- Add `NETunnelProviderManager` integration in iOS app code.
- Keep app UI thin and use existing app feature state where possible.
- Preserve placeholder identifiers until real signing configuration is supplied.

Out of scope:

- App Store distribution readiness.
- Account/cloud sync.

### M33 Runtime Snapshot to Real Provider Flow

Connect app-side node selection and runtime snapshot publishing to the provider’s real startup path.

Scope:

- App writes runtime snapshot into App Group storage.
- Provider reads snapshot and reports status/logs back.
- UI shows basic connected/failed state.

Out of scope:

- Subscription management.
- Multi-profile advanced UX.

### M34 Real Signing and Device Smoke Validation

Bridge the remaining environment-dependent gap.

Scope:

- Replace placeholder team/App Group values with local configuration guidance or templates.
- Run at least one real-device tunnel startup smoke test when credentials are available.
- Document exact manual signing steps if automation cannot perform them.

Out of scope:

- Storing secrets in repo.
- Bypassing Apple capability requirements.

### M35 iOS Shadowsocks Alpha Hardening

Stabilize the first usable Alpha path.

Scope:

- Improve diagnostics for missing snapshot, App Group failure, connection failure, and packet-loop failure.
- Add regression tests around status/log transitions.
- Validate one real Shadowsocks TCP/TLS node if environment permits.

Out of scope:

- Multi-protocol expansion.
- macOS parity.

## Phase 2: Broader Technical Alpha

Target: expand from iOS Shadowsocks Alpha toward the original technical Alpha matrix.

### M36 VMess TCP/TLS Foundation

Implement VMess configuration validation, request framing, and TCP/TLS transport integration.

### M37 VLESS TCP/TLS Foundation

Implement VLESS configuration validation, request framing, and TCP/TLS transport integration.

### M38 Trojan TCP/TLS Foundation

Implement Trojan configuration validation, request framing, and TCP/TLS transport integration.

### M39 WebSocket Transport Binding

Add WebSocket transport support for VMess, VLESS, Trojan, and Shadowsocks where applicable.

### M40 HTTP/2 Transport Binding

Add HTTP/2 transport support for protocols in the Alpha matrix.

### M41 gRPC Transport Binding

Add gRPC transport support for protocols in the Alpha matrix.

### M42 Reality Options and VLESS Reality Path

Model Reality separately from standard TLS and wire the VLESS Reality path.

### M43 QUIC Transport Foundation

Add QUIC transport abstractions and platform implementation strategy.

### M44 Hysteria2 Foundation

Implement Hysteria2 configuration, handshake, and QUIC-backed runtime path.

### M45 TUIC Foundation

Implement TUIC configuration, handshake, and QUIC-backed runtime path.

### M46 UDP Forwarding Foundation

Add UDP packet handling and runtime forwarding required for QUIC-oriented protocols and DNS behavior.

### M47 Routing Completeness and Performance Pass

Harden direct/proxy/reject rule behavior and validate routing performance budgets.

### M48 Diagnostics and User-Facing Failure Taxonomy

Unify user-visible error messages, logs, and debug details across protocols and transports.

### M49 macOS App and Packet Tunnel Scaffold

Add macOS target scaffold after the iOS path proves the runtime architecture.

### M50 macOS Runtime Integration

Port the proven iOS Packet Tunnel runtime path to macOS-specific shell code.

### M51 Cross-Protocol Real Node Validation

Run and document real-node validation for the Alpha protocol/transport matrix.

### M52 Alpha Release Hardening

Perform final stability, cleanup, performance, and documentation pass for the technical Alpha.

## Success Gates

### iOS Shadowsocks Alpha Gate

Pass when:

- iOS app can install/start/stop the Packet Tunnel profile in a signed environment.
- One Shadowsocks node can be selected manually and used through the tunnel.
- Runtime status and logs reflect startup, connected, stopped, and failed states.
- Shared packages remain platform-neutral.
- SwiftPM tests and Xcode unsigned builds pass.

### Technical Alpha Gate

Pass when:

- The protocol/transport matrix from the original design has real-node validation evidence for required Alpha entries.
- iOS and macOS shells both use shared package logic rather than duplicating protocol/runtime code.
- Routing, diagnostics, and performance budgets have automated or documented validation.
- No signing secrets, credentials, or provisioning artifacts are committed.
