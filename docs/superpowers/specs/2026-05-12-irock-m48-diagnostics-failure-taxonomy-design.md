# M48 Diagnostics and User-Facing Failure Taxonomy Design

Date: 2026-05-12

## Goal

Add a stable, credential-safe user-facing failure taxonomy across protocol, transport, routing, storage, and tunnel runtime failure paths.

## Current State

- `IrockDiagnostics` currently contains bounded connection log storage only.
- `ProxyProtocolError` and `TransportError` already provide credential-safe descriptions that redact associated strings.
- Routing parse errors and storage errors can currently be interpolated directly into app-facing results/logs.
- Tunnel runtime status/log paths already publish stable generic messages for packet batch, missing snapshot, and runtime store failures.

## Design

Add a small diagnostics taxonomy in `IrockDiagnostics` that returns stable user-facing messages with source categories:

- Protocol adapter failures: use the existing safe protocol error description.
- Transport failures: use the existing safe transport error description.
- Routing failures: map parse failures to stable line-aware messages without copying raw rule text or values.
- Runtime/store failures: expose stable messages for missing runtime snapshot, runtime store unavailable, packet batch failure, status load failure, log load failure, and snapshot publish storage failure.

Wire app-facing snapshot publishing and runtime feedback refresh paths to the taxonomy so UI-visible results and logs do not include raw `String(describing: error)` output.

## Scope

In scope:

- `IrockDiagnostics` taxonomy types and tests.
- App feature routing/status/log/storage failure mapping to stable messages.
- Regression tests ensuring raw secret-like error strings do not appear in user-facing output.
- M48 documentation and implementation plan.

Out of scope:

- Localization catalogs.
- Telemetry upload, crash reporting, or analytics.
- Replacing internal error enums.
- Large UI redesign or user-visible diagnostics screens.
- Changing protocol/transport connection behavior.

## Validation

- `IrockDiagnosticsTests` cover protocol, transport, routing, storage, and runtime taxonomy messages.
- `IrockAppFeatureTests` cover stable user-facing output for routing, storage, status, and log failures.
- Full `swift test` passes.
- Source exposure scan confirms representative secret strings are not emitted through diagnostics messages.
- Signing/credential artifact scan remains clean.
