# M50 macOS Runtime Integration Plan

## Tasks

1. Add RED tooling coverage for macOS runtime integration.
   - Assert the macOS smoke runner calls `TunnelRuntimeController.runShadowsocksTCPBatch`.
   - Assert it wires `NEPacketTunnelFlowPacketFlowIO`, `MacOSPlatformTCPDialer`, unsupported TLS adapter, and missing credential resolver through the shared controller.
   - Assert the macOS TCP dialer imports `Network`, uses `NWConnection`, handles cancellation, timeout, initial payload, and returns `TCPDialResult`.

2. Implement minimal GREEN changes.
   - Restore macOS smoke runner runtime execution through shared tunnel core only.
   - Implement macOS `TCPDialer` with `NWConnection` in the platform target only.
   - Do not modify shared protocol/runtime business logic.

3. Verify and review.
   - Run focused M50 test and full `XcodeScaffoldTests`.
   - Run full `swift test`.
   - Scan shared packages for platform imports.
   - Scan app folders for signing/provisioning artifacts.
   - Request independent review for runtime boundary, platform isolation, and signing safety.
   - Run bounded deslop on M50 changed files only, then re-run verification.

4. Commit and push.
   - Update local Ralph state for M50 after verification.
   - Commit only M50 files, excluding `.omc/`, `.serena/`, and other local tool state.
