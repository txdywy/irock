# macOS Packet Tunnel Device Smoke Runbook

External prerequisites:

- Apple Developer account with Network Extension capability.
- macOS development device enrolled for the selected Team ID.
- App Groups enabled for the app and Packet Tunnel extension.
- Local signing xcconfig copied from `LocalSigning.xcconfig.example` with real local-only values.

Steps:

1. Open the macOS Xcode project.
2. Apply local signing settings for `irockMacApp` and `irockMacTunnelExtension`.
3. Build and run the container app on a macOS device.
4. Install or update the Packet Tunnel configuration from the app shell.
5. Start the tunnel and confirm Packet Tunnel permission prompts appear.
6. Expected result: the app can install/start/stop the Packet Tunnel shell, and runtime failures appear through shared status/log stores.

Do not commit provisioning profiles, signing certificates, private keys, or real credentials.
