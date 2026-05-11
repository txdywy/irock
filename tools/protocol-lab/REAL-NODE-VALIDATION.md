# Real Node Validation Runbook

This runbook records how to validate Alpha protocols against operator-provided nodes without committing secrets. Development-time comparison tools may reference sing-box, xray, or clash outside the app runtime, but those engines must not be embedded in irock.

## Required inputs

For each protocol, collect inputs outside the repository:

- Shadowsocks: server host, port, method, password, and optional plugin settings.
- VMess: server host, port, user ID, security options, and transport-specific path or authority settings.
- VLESS: server host, port, user ID, TLS settings, and optional Reality public key, short ID, and server name.
- Trojan: server host, port, password, TLS settings, and transport-specific path or authority settings.
- Hysteria2: server host, port, authentication material, SNI, ALPN, and obfuscation settings if used.
- TUIC: server host, port, UUID, password, SNI, ALPN, and congestion-control settings if used.
- Apple Developer signing with Network Extension and App Groups enabled.
- A physical iOS or macOS device capable of installing and starting the Packet Tunnel target.

## Expected observations

For each Shadowsocks, VMess, VLESS, Trojan, Hysteria2, and TUIC run:

1. Import or configure the node locally without committing the node URI or credentials.
2. Publish a runtime snapshot through the app shell.
3. Start the Packet Tunnel on the physical iOS or macOS device.
4. Confirm status transitions through preparing, connecting or connected, and stopped or failed.
5. Confirm user-facing diagnostics remain credential-safe if the node fails.
6. Confirm packet flow attempts reach the expected protocol and transport seam.
7. Record only pass, fail, or blocked status plus sanitized fixture labels.

## Redaction rules

- Do not commit real hosts, usernames, UUIDs, passwords, access tokens, shared secrets, private keys, certificate files, QR payloads, or subscription URLs.
- Replace server names with `example.invalid` or a sanitized fixture label before writing notes.
- Replace credential values with presence markers such as `credential present` or `uuid present`.
- Remove IP addresses unless they are documentation ranges such as `198.51.100.0/24`.
- Keep raw third-party tool logs outside the repository unless they are manually redacted.

## External blocker

Real-node validation is externally blocked until all of the following are available:

- Apple Developer signing for Network Extension.
- App Groups configured consistently for the app and Packet Tunnel targets.
- A physical iOS or macOS device.
- Operator-provided Shadowsocks, VMess, VLESS, Trojan, Hysteria2, and TUIC nodes.
- Permission to test those nodes from the local network environment.

## Do not commit

Do not commit provisioning profiles, certificates, private keys, node credentials, subscription URLs, QR payloads, raw packet captures, or unredacted logs. Store those inputs locally or in the operator's approved secret manager only.

## Result template

| Protocol | Node label | Platform | Result | Notes |
| --- | --- | --- | --- | --- |
| Shadowsocks | sanitized fixture shadowsocks-tcp | iOS or macOS | Passed / Failed / Blocked | Sanitized observations only. |
| VMess | sanitized fixture vmess-websocket | iOS or macOS | Passed / Failed / Blocked | Sanitized observations only. |
| VLESS | sanitized fixture vless-reality | iOS or macOS | Passed / Failed / Blocked | Sanitized observations only. |
| Trojan | sanitized fixture trojan-grpc | iOS or macOS | Passed / Failed / Blocked | Sanitized observations only. |
| Hysteria2 | sanitized fixture hysteria2-quic | iOS or macOS | Passed / Failed / Blocked | Sanitized observations only. |
| TUIC | sanitized fixture tuic-quic | iOS or macOS | Passed / Failed / Blocked | Sanitized observations only. |
