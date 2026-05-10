# irock M7 Runtime Rule Manifest Design

日期：2026-05-10

## 1. 目标

M7 将 M6 的本地规则解析结果接入 `RuntimeSnapshot`，让主 App 发布运行快照时可以携带规则 manifest，Tunnel 侧可以从同一个不可变快照读取规则边界。

本阶段仍保持 SwiftPM 可测试，不实现规则 UI、不解析远程规则、不改变 Packet Tunnel packet 热路径，也不把 `IrockCore` 反向依赖 `IrockRouting`。

## 2. 范围

M7 实现：

- 在 `IrockCore` 新增可编码的规则快照模型：
  - `RuntimeRoutingRule`
  - `RuntimeRoutingRuleKind`
  - `RuntimeRoutingRuleManifest`
- `RuntimeSnapshot` 新增 `routingRuleManifest` 字段。
- `RuntimeSnapshot` initializer 为 `routingRuleManifest` 提供默认空 manifest，保持现有调用点源码兼容。
- `RuntimeSnapshot` JSON 编码包含规则 manifest，且仍不包含原始凭据明文。
- `RuntimeSnapshotPublisher.publish(...)` 增加可选 `routingRuleManifest` 参数并写入 snapshot。
- `AppViewModel.publishRuntimeSnapshot()` 继续使用默认空 manifest。
- `TunnelRuntimeConfiguration` 暴露 `routingRuleManifest` 只读属性。

M7 不实现：

- `RuntimeRoutingRule` 和 `IrockRouting.RoutingRule` 的自动转换。
- 规则文本解析入口接入 AppFeature。
- 规则 UI。
- 远程规则缓存。
- RuntimeSnapshot store 文件迁移。
- Tunnel 根据 manifest 自动创建 `RoutingEngine`。

## 3. 架构

`IrockCore` 不能依赖 `IrockRouting`，因此运行快照使用 core-local manifest 类型表达规则：

```text
RuntimeRoutingRuleManifest
  rules: [RuntimeRoutingRule]
  version: Int
```

```text
RuntimeRoutingRule
  kind: RuntimeRoutingRuleKind
  value: String?
  action: RouteMode-compatible action enum? no — use string action? no
```

M7 采用独立动作枚举 `RuntimeRoutingAction`，避免把 `RoutingAction` 从 `IrockRouting` 泄漏进 `IrockCore`：

```text
RuntimeRoutingAction.direct / proxy / reject
```

后续阶段可以在 `IrockTunnelCore` 或 app feature adapter 中把 manifest 转换为 `IrockRouting.RoutingRule`。M7 只负责让快照能稳定携带 manifest。

## 4. 数据模型

新增类型：

```swift
public enum RuntimeRoutingAction: String, Codable, Sendable {
    case direct
    case proxy
    case reject
}

public enum RuntimeRoutingRuleKind: String, Codable, Sendable {
    case domain
    case domainSuffix
    case domainKeyword
    case ipCIDR
    case finalRule = "final"
}

public struct RuntimeRoutingRule: Equatable, Codable, Sendable {
    public let kind: RuntimeRoutingRuleKind
    public let value: String?
    public let action: RuntimeRoutingAction
}

public struct RuntimeRoutingRuleManifest: Equatable, Codable, Sendable {
    public let version: Int
    public let rules: [RuntimeRoutingRule]
}
```

`RuntimeRoutingRuleManifest.empty` 使用 `version = 1` 和空规则数组。

## 5. 错误策略

M7 不新增错误类型。Manifest 只表达已验证后的运行数据；规则文本解析错误仍由 M6 的 `RoutingRuleParser` 负责。`RuntimeSnapshotPublisher` 保持现有 `missingSelectedNode` 和 `storageFailed` 行为。

## 6. 测试策略

M7 扩展测试覆盖：

1. `RuntimeSnapshot` 默认 initializer 生成空 routing manifest。
2. `RuntimeSnapshot` 编码包含 routing manifest。
3. `RuntimeSnapshot` 编码仍不包含 raw credential material。
4. `RuntimeSnapshotPublisher` 可发布传入的 manifest。
5. `RuntimeSnapshotPublisher` 默认发布空 manifest。
6. `TunnelRuntimeConfiguration` 暴露 snapshot 中的 manifest。
7. 全量 `swift test` 通过。

## 7. 成功标准

M7 完成时：

- `RuntimeSnapshot` 可携带 runtime routing rule manifest。
- 现有 snapshot 调用点不需要强制改参。
- AppFeature publisher 可以传递 manifest。
- Tunnel configuration 可以读取 manifest。
- 不引入 `IrockCore` → `IrockRouting` 依赖。
- README 和 CLAUDE.md 准确说明 M7 runtime rule manifest foundation。
