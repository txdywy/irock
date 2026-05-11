# M41 gRPC Transport Binding Design

Date: 2026-05-11

## Goal

Add a gRPC transport foundation so protocols can request `TransportType.grpc` and open through the existing TCP/TLS transport seam with deterministic, credential-safe gRPC metadata.

## Current State

- `TransportType.grpc` already exists in `IrockCore`.
- `IrockTransport` has TCP, TLS, TCP/TLS selector, WebSocket, and HTTP/2 foundation adapters.
- VMess, VLESS, and Trojan foundations can use TCP/TLS, WebSocket, and HTTP/2 transport paths.
- gRPC requests currently fall back to unsupported transport.

## Design

Add a `GRPCTransportAdapter` in `IrockTransport`. It supports `.grpc`, validates host, port, service path, authority, and optional protocol metadata, then opens an underlying request as `.tcp`. TLS options are preserved so the existing TCP/TLS selector can route secure gRPC to TLS where configured.

The foundation builds deterministic, non-secret metadata and synthetic initial bytes. It does not implement real gRPC framing, HTTP/2 stream lifecycle, protobuf serialization, HPACK, flow control, or response validation. Those belong in later deepening milestones. The synthetic opener marker contains authority/service/protocol only, and it appends any upstream protocol opener bytes after the marker.

Metadata keys:

- `grpcAuthority`
- `grpcService`
- `grpcProtocol` when provided
- `grpcUpgrade` set to `true`

Input metadata:

- `grpcService` defaults to `/TunService/Connect`
- `grpcAuthority` defaults to the trimmed request host
- `grpcProtocol` is optional

## Scope

In scope:

- gRPC transport adapter validation.
- gRPC metadata normalization.
- Synthetic gRPC opener bytes that preserve existing protocol initial payload bytes.
- Registry selection for `.grpc`.
- VMess, VLESS, and Trojan foundation adapters accepting `.grpc` transport.
- Tests for validation, metadata, payload preservation, TLS preservation, and protocol adapter routing.

Out of scope:

- Full gRPC protocol compatibility.
- Protobuf message encoding/decoding.
- HTTP/2 stream lifecycle, HPACK, flow control, and response validation.
- UI/subscription import changes.
- Real-node gRPC validation without external credentials and reachable nodes.

## Validation

- `swift test --filter IrockTransportTests` passes and covers gRPC validation and underlying routing.
- `swift test --filter IrockProtocolsTests` passes and covers applicable protocol foundation adapters routing `.grpc`.
- Full `swift test` passes.
- Shared packages remain platform-neutral with no Network/NetworkExtension/UIKit/AppKit/Security imports.
- No credential-like fixture values are introduced into source gRPC metadata or synthetic opener payload construction.
