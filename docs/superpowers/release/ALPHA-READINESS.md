# Alpha Readiness Evidence

This document consolidates irock Alpha technical gate evidence. It is credential-safe: do not add real node URIs, passwords, access tokens, Team IDs, provisioning profiles, certificates, private keys, QR payloads, raw packet captures, or unredacted logs.

## Milestone coverage

- M30: Real Shadowsocks stream path established the first shared runtime proxy data path.
- M31: Packet to proxy response loop connected packet processing results back to Packet Tunnel writes.
- M32: iOS shell gained VPN manager integration boundaries.
- M33: Runtime snapshot to real provider flow connected app configuration to tunnel startup.
- M34: Real signing and device smoke validation documented signing placeholders and external blockers.
- M35: iOS Shadowsocks Alpha hardening added deterministic runtime lifecycle diagnostics.
- M36: VMess TCP/TLS foundation added credential-safe VMess metadata and runtime stack assembly.
- M37: VLESS TCP/TLS foundation added credential-safe VLESS metadata and runtime stack assembly.
- M38: Trojan TCP/TLS foundation added credential-safe Trojan metadata and runtime stack assembly.
- M39: WebSocket transport binding added reusable transport metadata and underlying TCP/TLS routing.
- M40: HTTP/2 transport binding added reusable HTTP/2 transport metadata and underlying TCP/TLS routing.
- M41: gRPC transport binding added reusable gRPC transport metadata and underlying TCP/TLS routing.
- M42: Reality options and VLESS Reality path added the Reality transport seam.
- M43: QUIC transport foundation added a credential-safe QUIC transport seam.
- M44: Hysteria2 foundation added Hysteria2 over QUIC adapter and runtime stack assembly.
- M45: TUIC foundation added TUIC over QUIC adapter and runtime stack assembly.
- M46: UDP forwarding foundation added bounded UDP forwarding decisions in shared tunnel core.
- M47: Routing completeness and performance pass added deterministic routing coverage and a performance budget check.
- M48: Diagnostics and user-facing failure taxonomy added stable credential-safe messages.
- M49: macOS app and Packet Tunnel scaffold added thin platform targets with placeholder signing.
- M50: macOS runtime integration wired macOS Packet Tunnel into the shared runtime path.
- M51: Cross-protocol real-node validation added a sanitized protocol matrix and real-node runbook.
- M52: Alpha release hardening consolidates release readiness evidence and remaining blockers.

## Alpha technical gate areas

### Protocol matrix

The Alpha protocol matrix covers Shadowsocks, VMess, VLESS, Trojan, Hysteria2, and TUIC with TCP, TLS, WebSocket, HTTP/2, gRPC, QUIC, and Reality where applicable. Repository tests validate adapter structure, credential-safe metadata, runtime stack assembly, and transport seams. Real interoperability remains dependent on operator-provided nodes.

### iOS shell

The iOS shell has app group runtime store resolution, VPN manager boundaries, Packet Tunnel provider lifecycle wiring, runtime settings application, packet flow adapter, long-running loop, platform TCP dialer, and stopped/failure diagnostics. Real device validation remains blocked without Apple Developer signing, App Groups, a physical device, and node credentials.

### macOS shell

The macOS shell has a committed app target scaffold, Packet Tunnel extension scaffold, App Group store resolution, runtime settings application, packet flow adapter, long-running loop, platform TCP dialer, and shared runtime integration. Real device validation has the same signing, App Group, physical iOS or macOS device, and node credential blockers.

### Routing

Routing coverage includes direct, proxy, reject, domain, suffix, keyword, CIDR, final, default, precedence, malformed rule, and case-insensitive parsing behavior. Routing precompilation and lookup behavior are covered by deterministic tests suitable for Packet Tunnel hot paths.

### Diagnostics

Diagnostics coverage includes credential-safe user-facing messages for protocol, transport, routing, runtime snapshot, runtime store, packet batch, status load, log load, and snapshot publish failures. Internal associated values stay out of user-facing messages.

### Performance budget

The performance budget evidence includes deterministic routing lookup timing coverage and Alpha target storage in `IrockPerformanceKit`. Performance-sensitive Packet Tunnel paths continue to avoid shared-package platform imports, database access, unbounded logging, and unnecessary allocations where covered by current tests.

### External blocker

Real-node and real-device Alpha validation is externally blocked until Apple Developer signing, Network Extension entitlement, App Groups, a physical iOS or macOS device, and operator-provided Shadowsocks, VMess, VLESS, Trojan, Hysteria2, and TUIC nodes are available. M51 documents the manual process and redaction rules.

## Verification checklist

- full swift test: pass in M52 verification.
- ReleaseReadinessTests: pass in M52 verification.
- protocol matrix and real-node runbook: present and credential-safe.
- iOS shell and macOS shell: platform-specific integration remains under `apps/`; reusable SwiftUI app-feature views remain in shared packages.
- routing: deterministic completeness and performance budget evidence present.
- diagnostics: credential-safe taxonomy evidence present.
- signing artifact scan: pass in M52 verification; no provisioning profiles, certificates, or private keys committed.
- shared package platform import scan: pass in M52 verification.

## Do not commit

Do not commit real credentials, node URIs, subscription URLs, QR payloads, Team IDs, provisioning profiles, certificates, private keys, raw packet captures, or unredacted logs. Keep external validation evidence sanitized and record unavailable dependencies as blocked rather than fabricating pass results.
