# M29 Platform TCP Dialer Design

## Goal

Add the first platform-local TCP dialer for the iOS Packet Tunnel extension behind the existing `TCPDialer` seam, so the tunnel runtime can use a real TCP transport adapter without moving platform networking into shared packages.

## Context

M28 made the Packet Tunnel provider long-running, but the smoke/runtime path still passes `UnsupportedTransportAdapter(transport: .tcp)` into `TunnelRuntimeController.runShadowsocksTCPBatch`. Earlier transport milestones already introduced `TCPDialer` and `TCPTransportAdapter` in `IrockTransport`; those shared types deliberately model the transport boundary without importing Apple's `Network` framework.

M29 fills the platform side of that boundary. The implementation belongs in `apps/irock-iOS/irockTunnelExtension` because it can import `Network`, compile in the app extension target, and stay out of SwiftPM shared package hot paths.

## Scope

- Add an iOS Packet Tunnel extension-local `IOSPlatformTCPDialer`.
- Implement `TCPDialer.open(host:port:)` with `NWConnection` for `.tcp` endpoints.
- Bound connection establishment with a timeout so the packet loop cannot hang forever on a dial attempt.
- Preserve shared package import boundaries: no `Network`, `NetworkExtension`, `UIKit`, `AppKit`, or `Security` imports in `packages/`.
- Wire `IOSPacketTunnelSmokeRunner` to pass `TCPTransportAdapter(dialer: IOSPlatformTCPDialer())` as the plain TCP adapter.
- Keep TLS adapter unsupported for this milestone.
- Extend static scaffold tests and Xcode project membership checks.

## Out of scope

- TLS socket wrapping.
- Shadowsocks encryption or remote proxy byte exchange.
- Connection object retention in shared transport abstractions.
- WebSocket, HTTP/2, gRPC, QUIC, UDP, or DNS strategy.
- Live remote-node validation.

## Architecture

`IOSPlatformTCPDialer` is extension-local and conforms to `IrockTransport.TCPDialer`. It creates an `NWConnection` using `NWEndpoint.Host` and `NWEndpoint.Port`, starts it on a private queue, waits for `.ready`, maps failures to `TransportError.tcpConnectFailed`, cancels the connection after readiness, and returns the existing `TCPDialResult` value.

The current shared transport connection type is still metadata-oriented; it does not carry a live socket. That means M29 proves the platform dial seam and compile/runtime integration without expanding the shared `TransportConnection` model. Later response-loop milestones can evolve the shared connection abstraction when bytes need to move through the socket.

## Data flow

```text
IOSPacketTunnelSmokeRunner.runOnce
  -> TCPTransportAdapter(dialer: IOSPlatformTCPDialer())
  -> TunnelRuntimeController.runShadowsocksTCPBatch(... plain: tcpAdapter ...)
      -> RuntimeProxyStack / Shadowsocks adapter requests TCP transport
          -> IOSPlatformTCPDialer.open(host:port:)
              -> NWConnection(host:port:using: .tcp)
              -> wait for ready / failed / timeout
              -> TCPDialResult(host: normalizedHost, port: port)
```

## Error and cancellation behavior

The dialer uses `withTaskCancellationHandler` so cancelled tunnel work resumes the pending dial with `CancellationError` and then cancels the `NWConnection`. Timeout resumes the same completion gate with `TransportError.tcpConnectFailed("tcp dial timed out")` instead of depending on `NWConnection` to emit a cancellation callback. `.waiting` is treated as non-terminal so temporary path unavailability can either become `.ready`, `.failed`, explicit cancellation, or timeout. Invalid ports are already rejected by `TCPTransportAdapter` before the dialer is called, and the platform dialer also defensively rejects empty hosts and invalid ports.

## Testing strategy

Static scaffold tests verify:

- `IOSPlatformTCPDialer.swift` exists.
- The Xcode project includes the file in the tunnel extension sources.
- The file imports `Network` and `IrockTransport`, conforms to `TCPDialer`, creates `NWConnection`, uses `NWEndpoint.Host`, uses `NWEndpoint.Port`, starts the connection, handles `.ready`, `.failed`, `.waiting`, cancellation, timeout, and returns `TCPDialResult`.
- `IOSPacketTunnelSmokeRunner` uses `TCPTransportAdapter(dialer: IOSPlatformTCPDialer())` for plain TCP and still keeps TLS unsupported.
- Platform imports remain outside shared packages and app shell.

Build validation remains:

- `swift test`
- `swift test --filter XcodeScaffoldTests`
- `xcodebuild -list -project apps/irock-iOS/irock.xcodeproj`
- Unsigned iOS Simulator build with `CODE_SIGNING_ALLOWED=NO`
- Import-boundary scans proving platform imports stay out of shared packages.

## Acceptance criteria

- The iOS Packet Tunnel extension target contains a platform TCP dialer source file.
- The platform TCP dialer conforms to `TCPDialer` and uses `NWConnection`.
- The tunnel smoke/runtime path uses `TCPTransportAdapter` with the platform dialer for plain TCP.
- TLS remains unsupported until a later milestone.
- Shared Swift packages remain platform-neutral.
- SwiftPM tests and unsigned Xcode build pass.
