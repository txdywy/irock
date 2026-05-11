# M46 UDP Forwarding Foundation Design

Date: 2026-05-12

## Goal

Add a bounded UDP forwarding foundation in shared tunnel logic so UDP packets have explicit direct, proxy, reject, drop, and unsupported decisions before later milestones add real UDP relay sockets or protocol-specific datagram forwarding.

## Current State

- `PacketParser` already parses IPv4 UDP endpoint fields and marks UDP/53 packets as DNS candidates.
- `FlowKey` already includes `TransportProtocol`, so UDP and TCP flows are distinct.
- `PacketProcessor` already routes UDP packets through direct/proxy/reject decisions using the same routing engine path as TCP.
- `ProxyOutbound` already blocks proxied UDP when the selected node has `udpPolicy == .disabled`.
- The runtime can publish failed status/logs when proxy connection setup throws.

## Design

Add a small tunnel-core UDP decision model that derives a bounded forwarding decision from `PacketProcessingResult` plus the selected node's `UDPPolicy`:

- `.direct(flowKey)` for UDP direct results.
- `.proxy(flowKey)` for UDP proxy results when node UDP is enabled.
- `.unsupported(flowKey)` for UDP proxy results when node UDP is disabled.
- `.reject(flowKey)` for UDP reject results.
- `.drop(reason)` for UDP parser/drop results.
- `nil` for non-UDP results.

This keeps M46 in shared Swift package logic and avoids pretending to support full UDP relay before protocol and platform datagram seams exist.

Extend regression coverage so:

- UDP direct/proxy/reject/drop/unsupported decisions are deterministic and bounded.
- UDP-enabled proxy outbound requests reach the selected protocol adapter with `transportProtocol: udp` metadata.
- Runtime failure reporting covers the UDP unsupported path when a UDP packet is proxied through a node with UDP disabled.

## Scope

In scope:

- Shared UDP forwarding decision model in `IrockTunnelCore`.
- Tests for UDP forwarding decisions across direct, proxy, reject, drop, and unsupported cases.
- Proxy outbound test for UDP enabled request construction.
- Runtime failure/status test for UDP unsupported proxy path.
- M46 documentation and plan.

Out of scope:

- Real UDP sockets or Network framework datagram I/O.
- Shadowsocks UDP associate, TUIC/Hysteria2 datagram forwarding, DNS proxy completeness, or response packet synthesis.
- IPv6 packet parsing expansion.
- Platform `NEPacketTunnelFlow` UDP writeback beyond existing `responsePacketBytes` behavior.
- UI/subscription import changes.
- Real-node UDP validation without external credentials/devices.

## Validation

- Focused UDP decision, proxy outbound, and runtime tests pass.
- `swift test --filter IrockTunnelCoreTests` passes.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
