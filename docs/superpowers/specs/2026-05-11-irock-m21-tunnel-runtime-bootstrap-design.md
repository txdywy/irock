# M21 Tunnel Runtime Bootstrap Design

## Goal

Add a deterministic tunnel runtime bootstrap boundary that assembles `PacketTunnelRuntime` from system-edge dependencies without introducing `NetworkExtension`, real packet flow I/O, sockets, or TLS handshakes.

## Context

M20 added `RuntimeProxyStack.shadowsocksTCP(plain:tls:)` and `TunnelRuntimeConfiguration.shadowsocksTCP(...)`, which compose protocol and transport registries for Shadowsocks over TCP/TLS. Callers still need to manually wire `TunnelRuntimeConfiguration`, `TunnelRuntimeReporter`, `PacketReader`, `PacketWriter`, and transport adapters before they can run a packet batch.

M21 closes that gap by adding a small builder that future app or Packet Tunnel targets can call after they have a `RuntimeSnapshot` and platform-specific packet I/O adapters.

## Scope

In scope:

- Add a public `TunnelRuntimeBootstrap` assembly type in `IrockTunnelCore`.
- Build `PacketTunnelRuntime` with:
  - `RuntimeSnapshot`
  - `PacketReader`
  - `PacketWriter`
  - `RuntimeStatusStore`
  - `RuntimeLogStore`
  - plain TCP `TransportAdapter`
  - TLS TCP `TransportAdapter`
  - `batchLimit`
  - `flowLimit`
- Use the existing `TunnelRuntimeConfiguration.shadowsocksTCP(...)` helper so routing rules come from the snapshot manifest.
- Attach a `TunnelRuntimeReporter` so status/log publication is present by default.
- Keep tests deterministic with in-memory packet I/O, in-memory stores, and recording/failing transport adapters.

Out of scope:

- `NetworkExtension` imports.
- Xcode app or extension targets.
- Real packetFlow adapters.
- Real sockets or TLS handshakes.
- Credential retrieval or decryption.
- Multi-protocol default selection beyond the existing Shadowsocks TCP stack.

## API

```swift
public struct TunnelRuntimeBootstrap: Sendable {
    public static func shadowsocksTCP<Reader: PacketReader, Writer: PacketWriter, Plain: TransportAdapter, TLS: TransportAdapter>(
        snapshot: RuntimeSnapshot,
        reader: Reader,
        writer: Writer,
        statusStore: RuntimeStatusStore,
        logStore: RuntimeLogStore,
        plain: Plain,
        tls: TLS,
        batchLimit: Int,
        flowLimit: Int
    ) throws -> PacketTunnelRuntime<Reader, Writer>
}
```

The method returns a fully wired `PacketTunnelRuntime`. It throws only when the snapshot routing manifest cannot be converted into runtime routing rules by `TunnelRuntimeConfiguration.shadowsocksTCP(...)`.

## Data flow

```text
TunnelRuntimeBootstrap.shadowsocksTCP(...)
  -> TunnelRuntimeConfiguration.shadowsocksTCP(snapshot:plain:tls:batchLimit:flowLimit:)
  -> TunnelRuntimeReporter(statusStore:logStore:)
  -> PacketTunnelRuntime(reader:writer:configuration:reporter:)
  -> runOnce()
  -> PacketProcessor + ProxyOutbound + RuntimeProxyStack
```

## Error handling

Bootstrap does not swallow configuration errors. Runtime execution keeps the existing behavior:

- reporter failures are ignored by `PacketTunnelRuntime`;
- packet reader/writer failures publish generic safe failure messages;
- proxy adapter failures publish redacted protocol-level failure messages;
- transport failures are mapped by protocol adapters before reaching the runtime.

## Testing strategy

Add `TunnelRuntimeBootstrapTests` in `IrockTunnelCoreTests`.

Required tests:

1. Builder returns a runtime that processes one proxy TCP packet and routes TLS-disabled Shadowsocks traffic to the plain transport child.
2. Builder attaches a reporter so successful `runOnce()` writes connected status and runtime logs.
3. Builder propagates invalid routing manifest errors before returning a runtime.
4. Builder preserves existing failure reporting when the TLS child fails.

Run focused tests first, then `swift test`, and scan for forbidden platform imports in `IrockTunnelCore`, `IrockProtocols`, `IrockTransport`, and `Package.swift`.
