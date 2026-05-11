# M52 Alpha Release Hardening Design

## Goal

Consolidate Alpha technical readiness evidence across the completed roadmap so the release state is reviewable, credential-safe, and repeatable without hiding remaining external blockers.

## Scope

- Create a release readiness evidence document covering M30 through M52.
- Summarize protocol matrix, iOS shell, macOS shell, routing, diagnostics, performance budget, real-node validation, signing, and device blockers.
- Preserve credential and signing safety: no real node credentials, Team IDs, provisioning profiles, certificates, private keys, QR payloads, or raw logs.
- Keep final hardening focused on documentation and verification evidence; no new protocol/runtime feature work.

## Out of Scope

- Publishing an App Store or TestFlight build.
- Bypassing Apple Developer signing requirements.
- Claiming real-node validation passed without operator-provided nodes and devices.
- Adding telemetry, backend services, or UI redesign.

## Acceptance

- M52 spec and plan exist.
- `docs/superpowers/release/ALPHA-READINESS.md` covers M30 through M52 and the Alpha technical gate areas.
- Release readiness evidence records external blockers honestly.
- SwiftPM tests, platform import scan, signing artifact scan, and release readiness review pass.
