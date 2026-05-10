# irock M4 Runtime Snapshot Publishing Design

日期：2026-05-10

## 1. 目标

M4 打通 M1 AppFeature 状态、M3 Storage 持久化和 M2 TunnelCore runtime 配置之间的应用侧发布边界：AppFeature 能从当前 UI/configuration state 生成冻结的 `RuntimeSnapshot`，并通过 `RuntimeSnapshotStore` 发布给未来 Packet Tunnel shell 读取。

本阶段仍保持 SwiftPM 可测试，不创建 Xcode workspace、app target、Packet Tunnel target，不接真实 App Group entitlement，也不启动真实 VPN。

## 2. 范围

M4 实现：

- 在 `IrockAppFeature` 中新增 runtime snapshot publishing 组件。
- 从选中节点、路由模式、日志级别生成 `RuntimeSnapshot`。
- 通过注入的 `RuntimeSnapshotStore` 保存 snapshot。
- 用明确结果类型表达发布成功、未选择节点、存储失败。
- 扩展 `AppViewModel` 的状态和动作，使它可以更新 route mode、debug logging，并触发 snapshot 发布。
- 用 XCTest 覆盖成功发布、未选节点、route mode/log level 映射、存储失败传播。

M4 不实现：

- App Group container URL 获取。
- NetworkExtension / VPN permission flow。
- App 启动时自动读取 snapshot。
- 多节点策略组、测速、自动择优。
- credential 明文保存；继续只使用 `CredentialReference`。
- 真实协议连接、真实 packet tunnel 启动。

## 3. 架构

新增 `RuntimeSnapshotPublisher`，位于 `IrockAppFeature`，依赖现有 `IrockCore` 和 `IrockStorage` 类型。

```text
IrockAppFeature
  AppViewModel
    ├─ holds OverviewState / NodeListState / SettingsState
    ├─ updates selected node / route mode / debug logging
    └─ calls RuntimeSnapshotPublisher

  RuntimeSnapshotPublisher
    ├─ builds RuntimeSnapshot from selected node + route mode + log level
    └─ saves through RuntimeSnapshotStore

IrockStorage
  RuntimeSnapshotStore
    ├─ InMemoryRuntimeSnapshotStore
    └─ FileRuntimeSnapshotStore
```

`RuntimeSnapshotPublisher` 负责应用层语义：当前配置是否足以发布 tunnel runtime snapshot。`RuntimeSnapshotStore` 继续只负责持久化。

## 4. 数据模型

新增发布结果：

```swift
public enum RuntimeSnapshotPublishResult: Equatable, Sendable {
    case published(SnapshotID)
    case missingSelectedNode
    case storageFailed(String)
}
```

`storageFailed` 保存面向 UI/log 的简短错误文本，避免把任意 `Error` 放入 Equatable/Sendable 结果中。

新增 publisher：

```swift
public struct RuntimeSnapshotPublisher: Sendable {
    public init(store: RuntimeSnapshotStore)
    public func publish(selectedNode: ProxyNode?, routeMode: RouteMode, logLevel: IrockLogLevel) -> RuntimeSnapshotPublishResult
}
```

Snapshot ID 由 publisher 生成，格式为稳定前缀加 UUID：

```text
snapshot-<UUID>
```

测试只断言 ID 非空并带 `snapshot-` 前缀，不依赖固定 UUID。

## 5. AppViewModel 行为

`AppViewModel` 新增能力：

- 初始化可注入 `RuntimeSnapshotStore`，默认使用 `InMemoryRuntimeSnapshotStore`。
- `setRouteMode(_:)` 更新 overview state 中的 route mode。
- `setDebugLoggingEnabled(_:)` 更新 settings state。
- `publishRuntimeSnapshot()` 调用 publisher：
  - selected node 来自 `overviewState.selectedNode`。
  - route mode 来自 `overviewState.routeMode`。
  - log level 映射：debug enabled → `.debug`，否则 `.user`。
  - 成功时追加用户日志：`运行配置已发布`。
  - 未选节点时追加用户日志：`请选择节点后再启动`。
  - 存储失败时追加用户日志：`运行配置发布失败`。

`publishRuntimeSnapshot()` 返回 `RuntimeSnapshotPublishResult`，让未来 SwiftUI 层可以决定是否继续请求 VPN 启动。

## 6. 数据流

```text
User selects node
  → AppViewModel.selectNode(id:)

User chooses route mode / debug logging
  → AppViewModel.setRouteMode(_:)
  → AppViewModel.setDebugLoggingEnabled(_:)

User taps future connect button
  → AppViewModel.publishRuntimeSnapshot()
  → RuntimeSnapshotPublisher.publish(...)
  → RuntimeSnapshotStore.save(snapshot)
  → runtime-snapshot.json or in-memory store
  → result + user-facing log
```

M4 不启动 tunnel。发布 snapshot 是 future connect flow 的前置步骤。

## 7. 错误策略

- 未选择节点：不创建 snapshot，不调用 store，返回 `.missingSelectedNode`。
- 存储失败：捕获 store 抛出的错误，返回 `.storageFailed(String(describing: error))`，并让 `AppViewModel` 写入普通用户日志。
- 成功发布：返回 `.published(snapshot.id)`。
- 不生成默认节点，不吞掉存储失败，不把失败伪装成 disconnected 状态。

## 8. 测试策略

新增或扩展 `IrockAppFeatureTests`，覆盖：

1. Publisher 在选中节点存在时保存 `RuntimeSnapshot` 并返回 `.published`。
2. Publisher 未选节点时返回 `.missingSelectedNode` 且 store 中没有 snapshot。
3. Publisher 将 route mode 和 log level 写入 snapshot。
4. Publisher 在 store 抛错时返回 `.storageFailed`。
5. AppViewModel 发布前可更新 route mode。
6. AppViewModel debug logging enabled 时发布 `.debug` snapshot。
7. AppViewModel 未选节点发布时追加用户日志。

测试使用 in-memory store 和测试专用 failing store，不依赖文件系统、App Group、Xcode target 或 NetworkExtension。

## 9. 成功标准

M4 完成时：

- `IrockAppFeature` 能从当前 app state 发布 tunnel runtime snapshot。
- 发布逻辑通过 `RuntimeSnapshotStore` 抽象连接到 M3 storage。
- `AppViewModel` 具备 future connect button 所需的 snapshot publishing 前置动作。
- 失败路径有明确结果和用户日志。
- `swift test` 全量通过。
- README 和 CLAUDE.md 能准确说明 M0-M4 当前状态。
