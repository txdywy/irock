# M31 Packet to Proxy Response Loop Design

Date: 2026-05-11

## Goal

Complete the first safe packet response write-back loop from runtime processing to `NEPacketTunnelFlow` without pretending the Alpha has a full bidirectional TCP stream implementation.

## Current State

- `PacketTunnelRuntime.runOnce()` reads packets, processes them, opens proxy connections for proxy actions, and writes `PacketProcessingResult` values through `PacketWriter`.
- `NEPacketTunnelFlowPacketFlowIO.writePackets(_:)` currently writes the original packet bytes back for `.direct` and `.proxy` actions.
- `ProxyConnection` only exposes connection metadata, not a stream read/write API.
- `TransportConnection` only exposes host/port/transport metadata, not a stream read/write API.

## Problem

Writing the original inbound packet back to `NEPacketTunnelFlow` is unsafe as a response-loop model. The tunnel should write only bytes that are explicitly produced as outbound response payloads. Until transport/proxy connections expose real remote-read semantics, the runtime needs a narrow response envelope that can be tested and safely ignored when no response bytes exist.

## Design

Add an optional response payload to `PacketProcessingResult`:

- `responsePacketBytes: [UInt8]?`
- Existing packet classification remains unchanged.
- Direct/proxy/reject/drop actions can exist without response bytes.
- Packet writers must only write results with non-empty `responsePacketBytes`.

Extend `ProxyConnection` with an optional initial response payload:

- `initialResponseBytes: [UInt8]?`
- Existing established connections default to `nil`.
- Test doubles can return deterministic response bytes.

Update `PacketTunnelRuntime` so proxy connection results enrich matching flow results with the connection's initial response bytes before calling the writer. This gives M31 a real write-back seam while preserving the current transport limitation.

## Scope

In scope:

- Model explicit write-back payloads in shared tunnel/protocol abstractions.
- Ensure shared `PacketWriter` receives response-enriched results.
- Ensure `NEPacketTunnelFlowPacketFlowIO` writes only explicit response bytes.
- Preserve flow identity by applying one proxy connection response to results for the same `FlowKey`.
- Keep failure handling bounded through existing runtime failure status/log behavior.

Out of scope:

- Full TCP stream state machine.
- Remote socket read loops.
- TCP ACK/sequence synthesis.
- UDP forwarding completeness.
- Congestion control or high-throughput flow-table tuning.

## Validation

- SwiftPM tunnel-core tests cover explicit response payload modeling and runtime enrichment.
- Tooling tests verify the iOS flow adapter no longer writes original packet bytes for direct/proxy results.
- Full `swift test` passes.
- iOS unsigned simulator build passes.
- Platform import scan confirms shared packages remain platform-neutral.
