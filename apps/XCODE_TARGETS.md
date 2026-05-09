# Xcode Targets

M0 establishes the exact Xcode target layout for implementation in the next phase.

## Workspace

Create `irock.xcworkspace` at the repository root.

Add the root Swift package to the workspace so app targets can depend on:

- `IrockCore`
- `IrockProtocols`
- `IrockRouting`
- `IrockTransport`
- `IrockStorage`
- `IrockDiagnostics`
- `IrockPerformanceKit`

## iOS targets

Create an iOS app project under `apps/irock-iOS/` with these targets:

- `irockApp`
- `irockTunnelExtension`

`irockApp` requirements:

- SwiftUI lifecycle
- Minimum iOS 17
- Depends on all shared irock packages
- Capabilities: App Groups, Keychain Sharing, Network Extensions

`irockTunnelExtension` requirements:

- Packet Tunnel Provider extension
- Depends on `IrockCore`, `IrockProtocols`, `IrockRouting`, `IrockTransport`, `IrockStorage`, `IrockDiagnostics`, `IrockPerformanceKit`
- Capabilities: App Groups, Keychain Sharing, Network Extensions

## macOS targets

Create a macOS app project under `apps/irock-macOS/` with these targets:

- `irockMacApp`
- `irockMacTunnelExtension`

`irockMacApp` requirements:

- SwiftUI lifecycle
- Minimum macOS 14
- Depends on all shared irock packages
- Capabilities: App Groups, Keychain Sharing, Network Extensions

`irockMacTunnelExtension` requirements:

- Packet Tunnel Provider extension
- Depends on `IrockCore`, `IrockProtocols`, `IrockRouting`, `IrockTransport`, `IrockStorage`, `IrockDiagnostics`, `IrockPerformanceKit`
- Capabilities: App Groups, Keychain Sharing, Network Extensions

## Signing placeholders

Use these placeholder identifiers until a real developer team is selected:

- Bundle ID: `com.irock.app.ios`
- iOS tunnel Bundle ID: `com.irock.app.ios.tunnel`
- macOS Bundle ID: `com.irock.app.macos`
- macOS tunnel Bundle ID: `com.irock.app.macos.tunnel`
- App Group: `group.com.irock.shared`

Do not commit local provisioning profiles, certificates, or private signing material.
