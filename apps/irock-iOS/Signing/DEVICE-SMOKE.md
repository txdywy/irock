# irock iOS Packet Tunnel Device Smoke Runbook

## Purpose

Validate that a locally signed iOS build can install the irock Packet Tunnel configuration, start the provider, read the App Group runtime snapshot, and report status/log feedback.

## Required local inputs

- Apple Developer account with Network Extension capability approval.
- Physical iPhone or iPad enrolled for development.
- App ID for the container app.
- App ID for the Packet Tunnel extension.
- Shared App Groups entitlement enabled for both IDs.
- Local bundle identifiers and App Group copied from `LocalSigning.xcconfig.example` into local-only settings.

## Do not commit

Do not commit real Team IDs, provisioning profile UUIDs, signing identities, certificates, `.mobileprovision`, `.p12`, `.cer`, or local `LocalSigning.xcconfig` edits.

## Manual steps

1. Copy `apps/irock-iOS/Signing/LocalSigning.xcconfig.example` to a local uncommitted signing configuration.
2. Replace placeholder values with local Apple Developer Team, bundle IDs, and App Group.
3. In Xcode, apply the local values to `irockApp` and `irockTunnelExtension` targets.
4. Confirm both targets use the same App Groups identifier.
5. Confirm the extension target has the Packet Tunnel Network Extension capability.
6. Build and run `irockApp` on a physical device.
7. Publish or select a Shadowsocks runtime configuration in the app.
8. Install/update the Packet Tunnel configuration from the app.
9. Start the Packet Tunnel from the app or iOS Settings.
10. Observe runtime status and logs in the app.

## Expected result

- The app installs a VPN configuration for the irock Packet Tunnel provider.
- The provider starts without a missing App Group container error.
- If no runtime snapshot exists, the provider reports a failed status and a user log message.
- If a runtime snapshot exists, the provider reads it and begins the packet loop.
- No signing secrets or provisioning artifacts appear in `git status`.
