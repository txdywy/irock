# irock macOS App

Committed scaffold targets:

- `irockMacApp`: thin SwiftUI macOS container app that hosts shared `IrockAppFeature` UI.
- `irockMacTunnelExtension`: macOS Packet Tunnel extension shell for the shared tunnel runtime path.

Required local capabilities before device or distribution validation:

- Network Extensions: Packet Tunnel
- App Groups: `group.dev.irock.shared` by default, replace locally for real signing
- Keychain Sharing: node credentials when credential storage is wired into platform targets

Signing files in this directory are placeholders only. Copy `Signing/LocalSigning.xcconfig.example` locally and do not commit real Team IDs, provisioning profiles, certificates, or private keys.
