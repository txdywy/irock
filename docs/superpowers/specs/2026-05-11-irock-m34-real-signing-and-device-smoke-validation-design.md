# M34 Real Signing and Device Smoke Validation Design

Date: 2026-05-11

## Goal

Bridge the gap between the unsigned simulator build and a real signed iOS Packet Tunnel smoke run by adding safe local configuration templates and an exact manual validation runbook, without committing Apple Developer secrets or provisioning artifacts.

## Current State

- The Xcode project uses placeholder bundle identifiers: `dev.irock.app` and `dev.irock.app.tunnel`.
- `DEVELOPMENT_TEAM` is intentionally empty in both app and tunnel target build settings.
- App and extension entitlements use placeholder App Group `group.dev.irock.shared`.
- The Packet Tunnel extension declares the `packet-tunnel-provider` entitlement.
- Unsigned simulator builds pass with `CODE_SIGNING_ALLOWED=NO`.
- Real device validation still requires a local Apple Developer Team, provisioning profiles, and App Group capability that cannot be provided by repo code.

## Design

Add repo-safe signing guidance:

- A checked-in local `.xcconfig` template with placeholder keys for developer team, bundle identifiers, and App Group.
- A checked-in M34 device smoke runbook that documents exact manual steps and expected observations.
- Tooling tests that enforce the template remains placeholder-only and that no secrets/provisioning artifacts are committed.

Do not mutate the main Xcode project to contain real team IDs. The project remains buildable unsigned. Developers can copy the template locally and apply signing settings in Xcode or through local build settings outside the repo.

## Scope

In scope:

- Add signing `.xcconfig` template with placeholder values only.
- Add device smoke validation runbook with exact steps for local Apple Developer setup.
- Add static tests to detect committed signing secrets/provisioning artifacts and verify templates remain placeholders.
- Keep unsigned simulator build and SwiftPM tests passing.

Out of scope:

- Creating Apple Developer accounts.
- Installing certificates or profiles.
- Committing real Team IDs, profile UUIDs, signing identities, or entitlements tied to a real account.
- Running device-only validation in this automation environment.

## Validation

- Tooling tests verify placeholder signing template and smoke runbook exist.
- Tooling tests verify Xcode project still has empty `DEVELOPMENT_TEAM` placeholders.
- Tooling tests verify no `.mobileprovision`, `.p12`, `.cer`, or real profile files are present under app directories.
- Full `swift test` passes.
- Unsigned iOS simulator build passes.
- Manual device smoke remains documented as externally blocked until local credentials/device are available.
