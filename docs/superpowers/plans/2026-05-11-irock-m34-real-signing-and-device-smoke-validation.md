# M34 Real Signing and Device Smoke Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add safe local signing configuration templates and a real-device Packet Tunnel smoke runbook while keeping secrets and provisioning artifacts out of the repository.

**Architecture:** Keep the checked-in Xcode project placeholder-only and unsigned-simulator friendly. Add repo-safe templates/runbooks under `apps/irock-iOS/Signing/` and protect them with static tooling tests. Real Team IDs, signing identities, provisioning profiles, and device execution remain local external inputs.

**Tech Stack:** Xcode project scaffold, `.xcconfig` templates, plist entitlements, SwiftPM XCTest static tooling tests, unsigned iOS simulator build.

---

## Files

- Create: `apps/irock-iOS/Signing/LocalSigning.xcconfig.example`
  - Placeholder-only local signing template.
- Create: `apps/irock-iOS/Signing/DEVICE-SMOKE.md`
  - Manual real-device Packet Tunnel smoke validation runbook.
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Adds static tests for signing templates, runbook contents, empty project team placeholders, and absence of committed signing artifacts.
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m34-real-signing-and-device-smoke-validation-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m34-real-signing-and-device-smoke-validation.md`

## Task 1: Signing template and runbook contract

- [x] **Step 1: Write failing static test**

Add this test to `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` after `testEntitlementTemplatesDeclareSharedAppGroupAndPacketTunnelCapability`:

```swift
func testSigningTemplateAndDeviceSmokeRunbookArePlaceholderSafe() throws {
    let signingTemplate = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/Signing/LocalSigning.xcconfig.example"))
    let smokeRunbook = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/Signing/DEVICE-SMOKE.md"))

    XCTAssertTrue(signingTemplate.contains("IROCK_DEVELOPMENT_TEAM = YOUR_TEAM_ID"))
    XCTAssertTrue(signingTemplate.contains("IROCK_APP_BUNDLE_ID = com.example.irock"))
    XCTAssertTrue(signingTemplate.contains("IROCK_TUNNEL_BUNDLE_ID = com.example.irock.tunnel"))
    XCTAssertTrue(signingTemplate.contains("IROCK_APP_GROUP = group.com.example.irock"))
    XCTAssertFalse(signingTemplate.contains("DEVELOPMENT_TEAM = [A-Z0-9]"))

    XCTAssertTrue(smokeRunbook.contains("Apple Developer account"))
    XCTAssertTrue(smokeRunbook.contains("Network Extension"))
    XCTAssertTrue(smokeRunbook.contains("App Groups"))
    XCTAssertTrue(smokeRunbook.contains("Packet Tunnel"))
    XCTAssertTrue(smokeRunbook.contains("Expected result"))
    XCTAssertTrue(smokeRunbook.contains("Do not commit"))
}
```

Also update `requiredScaffoldPaths` to include:

```swift
"apps/irock-iOS/Signing/LocalSigning.xcconfig.example",
"apps/irock-iOS/Signing/DEVICE-SMOKE.md",
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter XcodeScaffoldTests/testSigningTemplateAndDeviceSmokeRunbookArePlaceholderSafe`

Expected: FAIL because the signing template and runbook do not exist.

- [x] **Step 3: Create signing template**

Create `apps/irock-iOS/Signing/LocalSigning.xcconfig.example`:

```text
// Copy this file to LocalSigning.xcconfig outside version control or keep local edits uncommitted.
// Do not commit real Apple Developer Team IDs, profile UUIDs, signing identities, or App Group IDs.

IROCK_DEVELOPMENT_TEAM = YOUR_TEAM_ID
IROCK_APP_BUNDLE_ID = com.example.irock
IROCK_TUNNEL_BUNDLE_ID = com.example.irock.tunnel
IROCK_APP_GROUP = group.com.example.irock

// Optional local values for manual device smoke builds.
// CODE_SIGN_STYLE = Automatic
// PROVISIONING_PROFILE_SPECIFIER =
// CODE_SIGN_IDENTITY = Apple Development
```

- [x] **Step 4: Create device smoke runbook**

Create `apps/irock-iOS/Signing/DEVICE-SMOKE.md`:

```markdown
# irock iOS Packet Tunnel Device Smoke Runbook

## Purpose

Validate that a locally signed iOS build can install the irock Packet Tunnel configuration, start the provider, read the App Group runtime snapshot, and report status/log feedback.

## Required local inputs

- Apple Developer account with Network Extension capability approval.
- Physical iPhone or iPad enrolled for development.
- App ID for the container app.
- App ID for the Packet Tunnel extension.
- Shared App Groups entitlement enabled for both IDs.
- Local bundle identifiers and App Group copied from `LocalSigning.xcconfig.example` into local-only settings.

## Do not commit

Do not commit real Team IDs, provisioning profile UUIDs, signing identities, certificates, `.mobileprovision`, `.p12`, `.cer`, or local `LocalSigning.xcconfig` edits.

## Manual steps

1. Copy `apps/irock-iOS/Signing/LocalSigning.xcconfig.example` to a local uncommitted signing configuration.
2. Replace placeholder values with local Apple Developer Team, bundle IDs, and App Group.
3. In Xcode, apply the local values to `irockApp` and `irockTunnelExtension` targets.
4. Confirm both targets use the same App Groups identifier.
5. Confirm the extension target has the Packet Tunnel Network Extension capability.
6. Build and run `irockApp` on a physical device.
7. Publish or select a Shadowsocks runtime configuration in the app.
8. Install/update the Packet Tunnel configuration from the app.
9. Start the Packet Tunnel from the app or iOS Settings.
10. Observe runtime status and logs in the app.

## Expected result

- The app installs a VPN configuration for the irock Packet Tunnel provider.
- The provider starts without a missing App Group container error.
- If no runtime snapshot exists, the provider reports a failed status and a user log message.
- If a runtime snapshot exists, the provider reads it and begins the packet loop.
- No signing secrets or provisioning artifacts appear in `git status`.
```

- [x] **Step 5: Run test to verify it passes**

Run: `swift test --filter XcodeScaffoldTests/testSigningTemplateAndDeviceSmokeRunbookArePlaceholderSafe`

Expected: PASS.

## Task 2: Signing artifact guardrails

- [x] **Step 1: Write failing/passing guardrail test**

Add this test to `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` after `testSigningTemplateAndDeviceSmokeRunbookArePlaceholderSafe`:

```swift
func testSigningSecretsAndProvisioningArtifactsAreNotCommitted() throws {
    let project = try String(contentsOf: repositoryRoot.appendingPathComponent("apps/irock-iOS/irock.xcodeproj/project.pbxproj"))
    XCTAssertTrue(project.contains("DEVELOPMENT_TEAM = \"\""))
    XCTAssertFalse(project.contains("PROVISIONING_PROFILE_SPECIFIER ="))
    XCTAssertFalse(project.contains("CODE_SIGN_IDENTITY = Apple Development"))

    let forbiddenExtensions = Set(["mobileprovision", "p12", "cer"])
    let appRoot = repositoryRoot.appendingPathComponent("apps/irock-iOS")
    let forbiddenFiles = try allFiles(under: appRoot).filter { forbiddenExtensions.contains($0.pathExtension) }
    XCTAssertEqual(forbiddenFiles, [])
}
```

Add this helper near `swiftFiles(under:)`:

```swift
private func allFiles(under directory: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
        return []
    }
    return enumerator.compactMap { $0 as? URL }
}
```

- [x] **Step 2: Run test to verify it passes**

Run: `swift test --filter XcodeScaffoldTests/testSigningSecretsAndProvisioningArtifactsAreNotCommitted`

Expected: PASS because the current project keeps `DEVELOPMENT_TEAM` empty and has no provisioning artifacts.

## Task 3: Full verification

- [x] **Step 1: Run tooling scaffold tests**

Run: `swift test --filter IrockToolingTests`

Expected: PASS.

- [x] **Step 2: Run full SwiftPM suite**

Run: `swift test`

Expected: PASS.

- [x] **Step 3: Run unsigned iOS simulator build**

Run: `xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

- [x] **Step 4: Run signing artifact scan**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
forbidden_suffixes = {'.mobileprovision', '.p12', '.cer'}
forbidden = [p for p in Path('apps/irock-iOS').rglob('*') if p.suffix in forbidden_suffixes]
if forbidden:
    print('\n'.join(str(p) for p in forbidden))
    raise SystemExit(1)
print('No signing artifacts committed')
PY
```

Expected: `No signing artifacts committed`.

- [x] **Step 5: Update this plan with execution status**

Mark completed checkboxes in this file after each step passes.
