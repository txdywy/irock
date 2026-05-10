# irock M13 Xcode Targets + App Group Wiring Design

日期：2026-05-10

## 1. 目标

M13 将 irock 从 SwiftPM-only foundation 推进到真实 Apple 平台工程骨架：创建 iOS/macOS App target、Packet Tunnel Extension target、workspace，并接入 App Group runtime snapshot 路径。

本阶段目标是建立可维护、可生成、可审查的平台 target 结构，让现有 shared packages 能被真实 App/Tunnel target 引用。M13 不要求完整 VPN 流量转发成功，也不实现真实协议出站。

## 2. 范围

M13 实现：

- 引入 XcodeGen 作为 Xcode project 生成工具。
- 新增并提交 XcodeGen `project.yml` 配置和生成后的 `.xcodeproj` / `.xcworkspace`。
- 创建 root `irock.xcworkspace`，包含 root Swift package、iOS project、macOS project。
- 创建 iOS targets：
  - `irockApp`
  - `irockTunnelExtension`
- 创建 macOS targets：
  - `irockMacApp`
  - `irockMacTunnelExtension`
- App targets 使用 SwiftUI lifecycle，并挂载 `IrockAppFeature` 的现有 root view。
- Tunnel extension targets subclass `NEPacketTunnelProvider`。
- App/Tunnel 平台层共享 App Group runtime snapshot path helper。
- Tunnel 启动时从 App Group snapshot path 读取 `RuntimeSnapshot`，并构建 `TunnelRuntimeConfiguration`。
- 新增 entitlements 占位文件，包含 App Groups、Network Extension、Keychain Sharing 的项目级占位配置。
- 更新 README、CLAUDE.md、`apps/XCODE_TARGETS.md`，准确说明 Xcode target skeleton 已存在但 signing/team 仍需本地配置。

M13 不实现：

- 真实 Shadowsocks/Trojan/VMess/VLESS/Hysteria2/TUIC 协议 runtime。
- 真实 direct/proxy outbound。
- 真实 `NEPacketTunnelFlow` packet 转发循环。
- VPN 权限 UI 完整流程。
- Keychain credential store。
- UserConfiguration 持久化。
- App Store signing、真实 Team ID、provisioning profile、证书。
- 复杂 UI polish。
- CI 强制通过 signing 相关 `xcodebuild`。

## 3. 目标文件结构

```text
irock.xcworkspace/
apps/
  irock-iOS/
    project.yml
    irock-iOS.xcodeproj/
    Sources/
      irockApp/
        IrockIOSApp.swift
      irockTunnelExtension/
        PacketTunnelProvider.swift
        Info.plist
    Entitlements/
      irockApp.entitlements
      irockTunnelExtension.entitlements
  irock-macOS/
    project.yml
    irock-macOS.xcodeproj/
    Sources/
      irockMacApp/
        IrockMacApp.swift
      irockMacTunnelExtension/
        PacketTunnelProvider.swift
        Info.plist
    Entitlements/
      irockMacApp.entitlements
      irockMacTunnelExtension.entitlements
  Shared/
    IrockPlatformSupport/
      AppGroupRuntimeSnapshotLocation.swift
```

`apps/Shared/IrockPlatformSupport` 是平台 target 共享源码，不作为 SwiftPM target 暴露。它可以依赖 Foundation 和 Apple platform APIs，但不能把 NetworkExtension 依赖引入 shared packages。

## 4. XcodeGen 配置策略

M13 使用 XcodeGen 维护 Xcode project 结构。

每个 platform project 提交：

- `project.yml`：可读、可审查的 target/source/dependency/build setting 配置。
- `.xcodeproj`：由 XcodeGen 生成并提交，方便没有立即安装 XcodeGen 的环境打开工程。

root workspace 提交：

- `irock.xcworkspace`：包含 root Swift package、iOS `.xcodeproj`、macOS `.xcodeproj`。

XcodeGen 版本不锁死到具体 patch 版本，但文档要求使用本机可用的稳定 XcodeGen，并通过 `xcodegen generate --spec ...` 重新生成工程。

## 5. Bundle ID、App Group 与 signing 占位

沿用现有项目文档中的占位 ID：

```text
iOS app bundle ID: com.irock.app.ios
iOS tunnel bundle ID: com.irock.app.ios.tunnel
macOS app bundle ID: com.irock.app.macos
macOS tunnel bundle ID: com.irock.app.macos.tunnel
App Group: group.com.irock.shared
```

M13 不提交真实 Team ID、provisioning profile、证书或私有 signing material。

默认 build settings 采用本地开发可编辑的 signing 配置。若 `xcodebuild` 因 signing/team 缺失失败，该失败不阻塞 M13，只要 workspace/project/scheme 可被发现，且文档说明如何在本地配置 team/signing。

## 6. App target 行为

App target 是薄平台壳：

```text
SwiftUI App entry
  → import IrockAppFeature
  → mount RootView / existing app feature root view
```

App target 不复制节点、规则、URI import、snapshot publishing 的业务逻辑。M13 不要求 App target 已经连接真实 VPN 开关；如果需要展示界面，使用 `IrockAppFeature` 已有状态和 view model。

## 7. Tunnel target 行为

Tunnel target 是最小 Packet Tunnel shell：

```text
PacketTunnelProvider.startTunnel
  → resolve App Group container URL
  → resolve runtime snapshot file URL
  → load RuntimeSnapshot via file-backed snapshot store or equivalent decoding path
  → build TunnelRuntimeConfiguration
  → return success if configuration can be constructed
```

如果 snapshot 缺失或无法解析，provider 返回明确错误。M13 不启动真实 packet read/write loop，不连接 remote proxy，不修改 DNS/route settings 到生产可用程度。

## 8. App Group snapshot path helper

新增平台共享 helper：

```swift
enum AppGroupRuntimeSnapshotLocation {
    static let appGroupID = "group.com.irock.shared"
    static let snapshotFileName = "runtime-snapshot.json"

    static func snapshotURL() throws -> URL
}
```

职责：

- 通过 `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` 找到 App Group container。
- 返回统一 snapshot file URL。
- 当 App Group container 不可用时抛出平台层错误。

该 helper 放在 `apps/Shared`，由 app/tunnel targets 直接编译进 target。它不进入 `IrockCore`，避免 core 层依赖真实 entitlement 环境。

## 9. Entitlements 策略

M13 提交四个 entitlements 文件：

- iOS app
- iOS tunnel
- macOS app
- macOS tunnel

每个文件至少包含：

- `com.apple.security.application-groups`：`group.com.irock.shared`
- Keychain sharing placeholder
- Network Extension capability placeholder where applicable

Entitlements 是项目结构占位，不代表本地 signing 已完成。真实 capability 开启仍需在 Xcode 中选择 Developer Team 并配置 provisioning。

## 10. 验证策略

M13 完成时必须通过：

```bash
swift test
```

如果本机安装 XcodeGen，运行：

```bash
xcodegen generate --spec apps/irock-iOS/project.yml
xcodegen generate --spec apps/irock-macOS/project.yml
```

Xcode workspace 骨架验证：

```bash
xcodebuild -list -workspace irock.xcworkspace
```

尽力验证 generic builds：

```bash
xcodebuild -workspace irock.xcworkspace -scheme irockApp -destination 'generic/platform=iOS' build
xcodebuild -workspace irock.xcworkspace -scheme irockMacApp -destination 'generic/platform=macOS' build
```

若 generic build 因 signing/team/provisioning 失败，记录失败原因并确认失败发生在 signing 层，而不是 source compile、package dependency 或 scheme discovery 层。

## 11. 成功标准

M13 完成时：

- `irock.xcworkspace` 存在并包含 root Swift package、iOS project、macOS project。
- iOS/macOS App targets 存在并 import `IrockAppFeature`。
- iOS/macOS Packet Tunnel targets 存在并 subclass `NEPacketTunnelProvider`。
- App/Tunnel targets 共享同一个 App Group snapshot URL helper。
- Tunnel provider 能从 snapshot path 加载 `RuntimeSnapshot` 并构建 `TunnelRuntimeConfiguration`。
- XcodeGen `project.yml` 与生成产物同步。
- Entitlements 占位文件存在，且不包含真实私密 signing material。
- README、CLAUDE.md、`apps/XCODE_TARGETS.md` 说明当前已存在 Xcode target skeleton，以及本地 signing/team 后续配置要求。
- `swift test` 全量通过。
