# M53 Shadowsocks 2022 Blake3 Support Design

Date: 2026-05-12

## Goal

Add real local-proxy support for common Shadowsocks 2022 Blake3 methods so imported `2022-blake3-*` nodes can connect through the macOS unsigned app instead of being rejected after SOCKS negotiation.

## Context

The current Alpha Shadowsocks stream path supports legacy `aes-256-gcm` only. URI import can parse `2022-blake3-*` credentials, and the macOS unsigned app now exposes a working POSIX socket listener for local SOCKS/HTTP proxy mode. However, the protocol codec rejects SS2022 methods before stream framing, so a 2022 node either fails at connection time or produces a SOCKS failure during the first proxied request.

The approved scope is to support these methods without adding an external BLAKE3 dependency:

- `2022-blake3-aes-128-gcm`
- `2022-blake3-aes-256-gcm`
- `2022-blake3-chacha20-poly1305`

## Scope

- Implement an internal BLAKE3 module inside `IrockProtocols`.
- Validate the BLAKE3 implementation with official test vectors before using it for SS2022 keys.
- Add a Shadowsocks cipher registry that separates legacy AEAD from SS2022 methods.
- Implement SS2022 client stream-open and streaming chunk encryption/decryption for the three approved methods.
- Update `ShadowsocksStreamRequest`, `ShadowsocksAEADStreamEncoder`, `ShadowsocksAEADStreamDecoder`, and macOS local proxy relay to support approved SS2022 credentials.
- Keep unknown methods rejected with explicit, user-visible errors.
- Keep implementation self-contained in repository source.

## Out of scope

- External SwiftPM BLAKE3 dependencies.
- UDP relay or SIP003 plugin support.
- Non-Blake3 Shadowsocks 2022 variants.
- Blindly accepting every `2022-blake3-*` method name.
- Real-node credentials in tests, logs, docs, or committed fixtures.
- Packet Tunnel entitlement/signing validation.

## Architecture

### Internal BLAKE3 unit

Add a small internal BLAKE3 implementation in `IrockProtocols`. It should expose only package-internal functions needed by the codec, such as keyed derivation output for a requested byte count. Tests must cover official BLAKE3 vectors for empty input, short input, and multi-block input before SS2022 tests rely on it.

### Cipher registry

Introduce a protocol-level cipher descriptor that can answer:

- canonical method name
- salt length
- key length
- AEAD algorithm family
- whether the method is legacy AEAD or SS2022

Legacy `aes-256-gcm` keeps its existing EVP_BytesToKey + HKDF-SHA1 behavior. SS2022 methods use BLAKE3-based key derivation and method-specific AEAD settings.

### Stream codec

`ShadowsocksStreamRequest` remains the stream-open builder, but delegates method-specific key derivation and sealing/opening to the cipher descriptor. `ShadowsocksAEADStreamEncoder` and `ShadowsocksAEADStreamDecoder` should share the same descriptor path so the macOS local proxy can relay post-open data with the same client salt and nonce sequence.

### macOS local proxy

The macOS POSIX listener remains the local socket boundary. After SS2022 support lands, `AppViewModel` should allow the three approved SS2022 credentials through `supportsCredential`. Unknown methods still fail before starting the local proxy so the UI does not show a false success.

## Data flow

1. User imports an `ss://` URI whose credential decodes to an approved SS2022 method.
2. `URIImport` stores the canonical `method:secret` credential in the app view model credential map.
3. `AppViewModel.connect()` validates the method through `ShadowsocksStreamRequest.supportsCredential`.
4. The macOS local proxy starts SOCKS/HTTP listeners.
5. On the first SOCKS or HTTP CONNECT request, `ShadowsocksStreamRequest` builds the SS2022 stream-open bytes for the requested destination.
6. The local proxy writes the open bytes to the remote Shadowsocks server.
7. Local-to-remote payloads use the matching SS2022 encoder and client salt continuation.
8. Remote-to-local payloads initialize the decoder from the server salt and stream decrypted payloads back to the local client.

## Error behavior

- Unsupported methods fail before local proxy startup with a stable user-facing message.
- Invalid credentials fail before network I/O.
- Invalid salt sizes, unsupported AEAD families, malformed chunks, and authentication failures map to `ProxyProtocolError.invalidConfiguration(...)` in protocol code.
- The macOS local proxy maps protocol failures to SOCKS/HTTP connection failure without logging credentials.
- UI logs must never include node passwords, raw URIs, keys, salts, or encrypted payloads.

## Testing strategy

- BLAKE3 unit tests against official vectors.
- Cipher registry tests for the three approved SS2022 methods and rejection of unknown methods.
- Deterministic stream-open tests for SS2022 host, IPv4, and IPv6 destinations with fixed salts.
- Encoder/decoder round-trip tests for each approved method.
- Regression tests proving legacy `aes-256-gcm` still passes unchanged.
- App feature tests proving approved SS2022 methods pass `supportsCredential`, while unknown methods fail before listener startup.
- macOS scaffold tests proving local proxy uses POSIX listener and SS2022-aware protocol primitives.
- Full `swift test` and unsigned macOS app build.

## Acceptance criteria

- The three approved SS2022 methods are accepted by `supportsCredential`.
- Unknown `2022-blake3-*` methods remain rejected.
- SS2022 stream-open bytes and payload frames are deterministic with fixed salts and pass codec round-trip tests.
- Legacy `aes-256-gcm` tests continue to pass.
- macOS unsigned app can start local proxy for an approved SS2022 node.
- No external BLAKE3 dependency is added.
- No credentials or real node material are committed.
