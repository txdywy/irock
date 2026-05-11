# M35 iOS Shadowsocks Alpha Smoke Validation

## Purpose

Validate that a locally signed iOS build reports deterministic status and log transitions for the first Shadowsocks Alpha path.

## Required local inputs

- Apple Developer account with Network Extension and App Groups enabled.
- Physical iOS device provisioned for the container app and Packet Tunnel extension.
- Shared App Group configured identically for both targets.
- One reachable Shadowsocks TCP or TCP/TLS node with local-only credentials.

## Do not commit

Do not commit real Shadowsocks credentials, server addresses, Apple Team IDs, provisioning profiles, certificates, `.mobileprovision`, `.p12`, `.cer`, or local signing files.

## Expected diagnostics

- Missing runtime snapshot reports `Runtime snapshot unavailable`.
- App Group or runtime store failure reports `Runtime store unavailable` when the shared status/log store is reachable.
- Proxy connection failure reports a `Proxy adapter failed` message without leaking credential material.
- Packet read/write loop failure reports `Packet batch failed`.
- Manual stop reports `Tunnel stopped`.
- Successful startup reaches `Packet batch processed` and logs `Tunnel runtime connected`.

## External blocker

If local signing, App Group provisioning, a physical device, or a real Shadowsocks node is unavailable, real-device validation is blocked outside the repository. In that case, record the blocker and rely on SwiftPM tests plus unsigned simulator build evidence for automation.
