# M47 Routing Completeness and Performance Pass Design

Date: 2026-05-12

## Goal

Harden local routing semantics and add automatable rule-matching performance evidence suitable for Packet Tunnel hot paths.

## Current State

- `IrockRouting` parses `DOMAIN`, `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD`, `IP-CIDR`, and `FINAL` rules.
- `RoutingEngine` precompiles rules into normalized ordered entries and applies first-match-wins semantics.
- Existing tests cover basic parsing, direct/proxy behavior, default action, and simple precedence.
- `IrockPerformanceKit` stores Alpha-wide throughput, latency, and memory budgets but does not yet record routing lookup budget evidence.

## Design

Expand deterministic routing coverage without changing the public rule language:

- Cover direct, proxy, and reject actions across domain, suffix, keyword, CIDR, final, and default paths.
- Cover precedence explicitly, including earlier reject/proxy/direct before later more specific rules and `FINAL` terminating later rules.
- Cover malformed routing input that matters for config safety: invalid field counts, empty final action, extra final fields, unsupported mixed input, invalid CIDR, and empty values.
- Cover CIDR boundaries including `/0`, `/32`, invalid IP no-match, and root suffix match.

Add performance evidence in `IrockPerformanceKitTests` by running deterministic routing lookups against a generated ruleset and asserting the average lookup time remains below a conservative Alpha hot-path budget. This records a repeatable automated signal while avoiding premature routing data-structure rewrites.

## Scope

In scope:

- Additional `IrockRoutingTests` coverage for completeness, precedence, malformed input, and CIDR boundaries.
- A routing lookup performance budget test that can run in SwiftPM CI.
- Minimal package/test dependency wiring if needed for performance tests.
- M47 documentation and implementation plan.

Out of scope:

- Domain hash sets, suffix reverse tries, keyword Aho-Corasick, or CIDR radix tries unless current tests expose a concrete need.
- GeoIP/geosite databases or remote rule provider integration.
- UI rule editor changes.
- Platform Packet Tunnel integration changes.
- Real traffic benchmarking on devices.

## Validation

- Focused routing completeness tests pass.
- Focused routing performance budget test passes.
- `IrockRoutingTests` pass.
- `IrockPerformanceKitTests` or benchmark-runner checks pass.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
