# irock macOS App

Committed scaffold targets:

- `irockMacApp`: SwiftUI macOS app that hosts shared `IrockAppFeature` UI and app-owned local proxy listeners.
- `irockMacTunnelExtension`: macOS Packet Tunnel extension shell for the shared tunnel runtime path.

## Unsigned local app build

Build a local Debug `.app` without Apple signing:

```sh
apps/irock-macOS/build-unsigned-app.sh
```

The script copies the artifact to `apps/irock-macOS/build/unsigned/irockMacApp.app`.

Unsigned builds support the app UI, Shadowsocks URI import, runtime snapshot publishing, and local proxy mode. After importing an `ss://` node, click `连接（本地代理）`; the app starts loopback listeners at:

- SOCKS5: `127.0.0.1:10808`
- HTTP CONNECT: `127.0.0.1:10809`

The app displays `networksetup` commands for users who want to point macOS system proxy settings at those loopback ports. It does not silently mutate global system proxy settings.

## Signed Packet Tunnel / TUN requirements

Required local capabilities before Packet Tunnel device or distribution validation:

- Apple Developer account with Network Extensions: Packet Tunnel
- App Groups: `group.dev.irock.shared` by default, replace locally for real signing
- Keychain Sharing: node credentials when credential storage is wired into platform targets

Unsigned builds cannot install or start the Network Extension Packet Tunnel. User-mode TUN alternatives require root/admin authorization to create and configure a tun device; when that authorization or signed entitlement is unavailable, use local SOCKS/HTTP proxy mode instead.

Signing files in this directory are placeholders only. Copy `Signing/LocalSigning.xcconfig.example` locally and do not commit real Team IDs, provisioning profiles, certificates, or private keys.
