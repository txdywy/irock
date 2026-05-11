# M49 macOS App and Packet Tunnel Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for production code changes and verify each RED/GREEN step.

**Goal:** Add a committed macOS app and Packet Tunnel scaffold without moving shared runtime business logic into platform code.

## Files

- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
- Modify: `apps/irock-macOS/README.md`
- Create: `apps/irock-macOS/irock-macOS.xcodeproj/project.pbxproj`
- Create: `apps/irock-macOS/Signing/LocalSigning.xcconfig.example`
- Create: `apps/irock-macOS/Signing/DEVICE-SMOKE.md`
- Create: `apps/irock-macOS/irockMacApp/*`
- Create: `apps/irock-macOS/irockMacTunnelExtension/*`
- Create: this plan and the paired M49 design spec.

## Task 1: Test scaffold contract

- [ ] Write failing tooling tests for macOS required files, Packet Tunnel Info.plist, entitlements, signing placeholders, and Xcode project shape.
- [ ] Run focused RED tests and confirm failures are missing macOS scaffold artifacts.

## Task 2: Add minimal scaffold

- [ ] Create macOS app shell that hosts shared `IrockRootView`.
- [ ] Create macOS VPN manager and App Group resolver seams.
- [ ] Create macOS Packet Tunnel extension shell using shared runtime seams.
- [ ] Create placeholder signing files, entitlements, plists, and Xcode project scaffold.
- [ ] Run focused tests to GREEN.

## Task 3: Verification

- [ ] Run `swift test --filter XcodeScaffoldTests`.
- [ ] Run full `swift test`.
- [ ] Run shared-package platform import scan.
- [ ] Run signing/credential artifact scan.
- [ ] Request independent review.
- [ ] Run bounded deslop on M49 files only.
- [ ] Re-run post-deslop tests/scans.
- [ ] Commit and push M49.

## Self-review

- macOS platform APIs stay in `apps/irock-macOS`.
- Shared packages are not given AppKit/Network/NetworkExtension imports.
- Signing files are placeholders only.
- M50 runtime integration is not pulled into M49 beyond thin scaffold seams.
