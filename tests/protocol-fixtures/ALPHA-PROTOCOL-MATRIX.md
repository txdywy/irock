# Alpha Protocol Matrix

This matrix is a sanitized fixture index for M51 cross-protocol validation. It uses sanitized fixture names only and contains no real credentials, production hosts, private keys, account IDs, or node URIs.

| Protocol | Alpha transport coverage | Repository validation | Real-node validation |
| --- | --- | --- | --- |
| Shadowsocks | TCP, TLS | Shared runtime tests cover Shadowsocks TCP/TLS packet-to-proxy path with sanitized fixture inputs. | Requires an operator-provided Shadowsocks node. |
| VMess | TCP, TLS, WebSocket, HTTP/2, gRPC | Foundation adapter tests cover credential-safe UUID handling and transport binding metadata. | Requires an operator-provided VMess node for compatibility confirmation. |
| VLESS | TCP, TLS, WebSocket, HTTP/2, gRPC, Reality | Foundation adapter tests cover credential-safe UUID handling, transport binding metadata, and VLESS Reality routing seam. | Requires operator-provided VLESS and VLESS Reality nodes. |
| Trojan | TCP, TLS, WebSocket, HTTP/2, gRPC | Foundation adapter tests cover credential-safe password presence metadata and transport binding metadata. | Requires an operator-provided Trojan node. |
| Hysteria2 | QUIC | Foundation adapter tests cover credential-safe Hysteria2 metadata and QUIC transport seam. | Requires an operator-provided Hysteria2 node. |
| TUIC | QUIC | Foundation adapter tests cover credential-safe UUID/password metadata and QUIC transport seam. | Requires an operator-provided TUIC node. |

## Sanitized fixture rules

- Use sanitized fixture labels such as `sanitized fixture shadowsocks-tcp`, `sanitized fixture vmess-websocket`, and `sanitized fixture tuic-quic`.
- Use `example.invalid`, `198.51.100.0/24`, or local test doubles when a host or address label is needed.
- Record credential presence flags only, such as `credentialPresent`, `uuidPresent`, or `passwordPresent`.
- There are no real credentials in this matrix.
- Do not paste subscription URLs, access tokens, passwords, private keys, certificates, real server names, or real node QR payloads.

## Automation status

Repository automation validates structure, adapter routing, metadata redaction, transport selection, runtime assembly, and platform import boundaries. Live interoperability requires external nodes and device signing, so the manual runbook records those blockers separately.
