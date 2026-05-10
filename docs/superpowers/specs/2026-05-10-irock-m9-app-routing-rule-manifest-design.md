# irock M9 App Routing Rule Manifest Design

日期：2026-05-10

## 1. 目标

M9 将 AppFeature 层的本地规则文本转换为 `RuntimeRoutingRuleManifest`，让主 App 可以把用户可编辑的规则文本发布进 M7/M8 建立的运行快照规则边界。

本阶段仍保持 SwiftPM 可测试，不实现规则 UI、不实现远程规则、不实现文件导入，也不改变 Packet Tunnel packet 处理逻辑。

## 2. 范围

M9 实现：

- 在 `IrockAppFeature` 新增 `RoutingRuleManifestBuilder`。
- Builder 使用 M6 的 `RoutingRuleParser.parseLines(_:)` 解析规则文本。
- Builder 将 `IrockRouting.RoutingRule` 转换为 `IrockCore.RuntimeRoutingRuleManifest`。
- 支持 DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR、FINAL。
- 支持 DIRECT、PROXY、REJECT。
- `AppViewModel` 增加本地规则文本状态和设置方法。
- `AppViewModel.publishRuntimeSnapshot()` 使用当前规则文本构建 manifest 并传给 `RuntimeSnapshotPublisher`。
- 规则解析失败时不保存 snapshot，并追加一条用户可见日志。

M9 不实现：

- SwiftUI 规则编辑界面。
- 远程规则下载、缓存、更新失败保留。
- GEOIP / PROCESS-NAME。
- RuntimeSnapshot store migration。
- Tunnel packet path 变更。

## 3. 架构

M9 位于 `IrockAppFeature`，因为该包已经依赖 `IrockCore`、`IrockRouting`、`IrockStorage` 和 `IrockDiagnostics`：

```text
local rule text
  → RoutingRuleParser.parseLines
  → [RoutingRule]
  → RoutingRuleManifestBuilder
  → RuntimeRoutingRuleManifest
  → RuntimeSnapshotPublisher.publish(... routingRuleManifest:)
```

`IrockCore` 继续不依赖 `IrockRouting`。`IrockTunnelCore` 继续只消费 runtime manifest。AppFeature 是用户编辑态和运行快照之间的转换边界。

## 4. 错误策略

`RoutingRuleManifestBuilder` 直接抛出 M6 的 `RoutingRuleParseError`，不额外包装。`AppViewModel.publishRuntimeSnapshot()` 捕获错误并返回 `.storageFailed(...)`，同时追加 `Routing rules invalid: ...` 日志，不保存新的 snapshot。

这样 UI 层未来可以根据日志展示基础错误，后续再细化错误展示模型。

## 5. 测试策略

M9 扩展测试覆盖：

1. Builder 将本地规则文本转换为 runtime manifest。
2. Builder 保留规则顺序。
3. Builder 透传 parser 错误。
4. AppViewModel 发布 snapshot 时包含规则 manifest。
5. AppViewModel 规则文本为空或只含注释时发布空 manifest。
6. AppViewModel 规则解析失败时不保存 snapshot 并记录日志。
7. 全量 `swift test` 通过。

## 6. 成功标准

M9 完成时：

- AppFeature 可以从本地规则文本构造 `RuntimeRoutingRuleManifest`。
- `AppViewModel.publishRuntimeSnapshot()` 把 manifest 写入 snapshot。
- 解析失败不会覆盖现有 snapshot。
- README 和 CLAUDE.md 准确说明 M9 app routing rule manifest foundation。
