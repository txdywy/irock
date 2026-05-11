# M50 macOS Runtime Integration Design

## Goal

Wire the committed macOS Packet Tunnel scaffold into the shared tunnel runtime path that is already proven by the iOS shell, while keeping macOS-specific code thin and platform APIs outside shared packages.

## Scope

- Replace the M49 macOS placeholder smoke runner with a runtime runner that calls `TunnelRuntimeController.runShadowsocksTCPBatch`.
- Replace the M49 placeholder macOS TCP dialer with a `Network.NWConnection`-backed `TCPDialer` seam equivalent to the iOS platform dialer.
- Preserve App Group runtime snapshot/status/log store boundaries.
- Preserve Packet Tunnel lifecycle behavior: apply settings, validate startup, run cancellable loop, and report stopped lifecycle.
- Add tooling tests that prove macOS uses the shared runtime controller and real platform TCP seam.

## Out of Scope

- Full real-node validation without local credentials, provisioning, and device access.
- Protocol/runtime business logic changes in shared packages.
- UI redesign or subscription import.
- Real signing material, Team IDs, provisioning profiles, certificates, or private keys.

## Acceptance

- M50 spec and plan exist.
- macOS smoke runner calls the shared Shadowsocks TCP batch controller instead of duplicating runtime logic.
- macOS TCP dialer uses `Network.NWConnection` behind the `TCPDialer` protocol seam.
- SwiftPM tests, platform import scan, and signing artifact scan pass.
