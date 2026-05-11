# M30 Real Shadowsocks Stream Path Design

Date: 2026-05-11

## Goal

Turn the existing Shadowsocks adapter from transport validation/delegation into a deterministic, testable Alpha stream path that can build the encrypted outbound request prefix for one supported Shadowsocks cipher without requiring live remote nodes.

## Context

M29 added an iOS Packet Tunnel-local TCP dialer behind the shared `TCPDialer` seam. The current `ShadowsocksProxyAdapter` validates a Shadowsocks node, opens the configured TCP/TLS transport, and returns an established proxy connection, but it does not yet produce Shadowsocks request framing or encrypted stream bytes.

## Scope

- Support one secure Alpha cipher path: `aes-256-gcm`.
- Parse Shadowsocks credential material from the existing imported `method:password` account string.
- Encode Shadowsocks target addresses for domain, IPv4, and IPv6 destinations.
- Produce deterministic encrypted stream open bytes for tests by injecting nonce material.
- Attach request-frame metadata to the existing `TransportRequest` so runtime assembly can verify protocol-to-transport semantics without live remote nodes.
- Keep all implementation inside shared Swift packages and preserve platform import boundaries.

## Out of scope

- Live remote Shadowsocks node validation.
- UDP associate.
- Plugin support.
- Additional Shadowsocks ciphers.
- Replacing local credential storage or introducing Keychain reads in shared packages.
- Full streaming read/write socket APIs; this milestone creates the request prefix contract that later packet response work can consume.

## Architecture

`ShadowsocksStreamRequest` is the small protocol unit for M30. It derives a key from the Shadowsocks password, encodes the destination address frame, encrypts that frame with an injectable nonce, and exposes the resulting stream-open bytes plus metadata. `ShadowsocksProxyAdapter` keeps using the existing `TransportAdapterRegistry`, but now validates and emits stream metadata on the `TransportRequest` before opening the transport.

For Alpha, `aes-256-gcm` follows the Shadowsocks AEAD TCP opening structure: EVP_BytesToKey derives the master key from the imported password, HKDF-SHA1 with `ss-subkey` derives a salt-specific subkey, and the stream-open prefix contains the salt plus encrypted length and destination payload chunks. Live interoperability still belongs to later real-node validation, but the bytes produced in this milestone match the protocol shape instead of a project-only placeholder contract.

## Data flow

1. `ProxyOutbound` turns a parsed packet into a `ProxyRequest` with destination metadata.
2. `ShadowsocksProxyAdapter.connect(request:)` validates the node and destination.
3. The adapter builds `ShadowsocksStreamRequest` from `credentialReference.account` and `ProxyDestination`.
4. The stream request produces encrypted open bytes and metadata.
5. The adapter opens the existing TCP/TLS transport with `metadata["shadowsocksStreamOpenHex"]`, `metadata["shadowsocksCipher"]`, and destination metadata.
6. The adapter returns the existing `EstablishedProxyConnection` semantics.

## Error behavior

Invalid method, missing password, invalid destination host, invalid destination port, invalid IPv4/IPv6 literals, and nonce-size errors map to `ProxyProtocolError.invalidConfiguration(...)` before any transport open. Transport failures still map through the existing transport-to-protocol error translation.

## Testing strategy

- Unit tests for credential parsing and method rejection.
- Unit tests for domain, IPv4, and IPv6 address-frame encoding.
- Unit tests for deterministic encrypted stream-open bytes and metadata injection into `TransportRequest`.
- Regression tests for existing transport selection behavior.
- Full `swift test`, Xcode unsigned build where relevant, and platform-import boundary scans.

## Acceptance criteria

- `aes-256-gcm:password` credentials build deterministic stream-open metadata for a host destination.
- IPv4 and IPv6 destinations produce the correct address-frame type markers.
- Unsupported Shadowsocks methods fail before opening transport.
- The existing adapter still opens the configured TCP/TLS transport and returns proxy connection semantics.
- Shared package platform import scans remain clean.
