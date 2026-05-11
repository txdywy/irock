# M51 Cross-Protocol Real Node Validation Design

## Goal

Define a credential-safe validation surface for the Alpha protocol matrix across Shadowsocks, VMess, VLESS, Trojan, Hysteria2, and TUIC without committing real node credentials or requiring embedded third-party proxy cores.

## Scope

- Add a sanitized Alpha protocol matrix that records which protocol/transport combinations are represented by repository tests and which require external real-node validation.
- Add a real-node validation runbook that lists required inputs, expected observations, redaction rules, and blockers for each Alpha protocol.
- Keep real secrets, endpoint material, certificates, provisioning profiles, and device-specific signing artifacts out of the repository.
- Treat real-device and real-node execution as externally blocked unless Apple Developer signing, App Groups, physical iOS or macOS device access, and reachable nodes are available.

## Out of Scope

- Shipping real credentials or sample production node URIs.
- Embedding sing-box, xray, clash, or other full proxy cores in the app runtime.
- Replacing existing protocol adapters or transport foundations.
- Adding analytics, telemetry, or backend reporting.

## Acceptance

- M51 spec and plan exist.
- Sanitized protocol matrix covers Shadowsocks, VMess, VLESS, Trojan, Hysteria2, and TUIC across TCP, TLS, WebSocket, HTTP/2, gRPC, QUIC, and Reality where applicable.
- Real-node runbook documents required inputs, expected observations, redaction rules, external blockers, and do-not-commit guidance.
- SwiftPM tests and credential/signing scans pass without real credentials.
