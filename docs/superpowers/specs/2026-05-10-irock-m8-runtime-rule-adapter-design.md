# irock M8 Runtime Rule Adapter Design

日期：2026-05-10

## 1. 目标

M8 将 M7 的 `RuntimeRoutingRuleManifest` 转换为 M6 的 `IrockRouting.RoutingRule`，让 Tunnel 层可以从运行快照里的规则 manifest 构建 routing engine 输入。

本阶段继续保持 SwiftPM 可测试，不引入规则 UI、远程规则、GEOIP、PROCESS-NAME、自动下载或 Packet Tunnel 网络行为。

## 2. 范围

M8 实现：

- 在 `IrockTunnelCore` 新增 adapter：`RuntimeRoutingRuleAdapter`。
- 支持将以下 runtime rule kind 转换为 `RoutingRule`：
  - `.domain` → `.domain`
  - `.domainSuffix` → `.domainSuffix`
  - `.domainKeyword` → `.domainKeyword`
  - `.ipCIDR` → `.ipCIDR`
  - `.finalRule` → `.final`
- 支持将 `RuntimeRoutingAction` 转换为 `RoutingAction`。
- 对非 FINAL 规则缺少 value 的情况返回稳定错误。
- 新增 `TunnelRuntimeConfiguration` convenience initializer，从 `RuntimeSnapshot.routingRuleManifest` 构建 `RoutingEngine`。
- 保留现有显式传入 `RoutingEngine` 的 initializer，方便测试和未来自定义引擎。

M8 不实现：

- `IrockCore` 依赖 `IrockRouting`。
- AppFeature 中规则文本解析到 manifest 的流程。
- Tunnel 自动下载或刷新远程规则。
- GEOIP / PROCESS-NAME。
- IPv6 CIDR。
- Packet 处理逻辑变更。

## 3. 架构

Adapter 位于 `IrockTunnelCore`，因为该包已经同时依赖 `IrockCore` 和 `IrockRouting`：

```text
RuntimeSnapshot.routingRuleManifest
  → RuntimeRoutingRuleAdapter.routingRules(from:)
  → [RoutingRule]
  → RoutingEngine(rules:)
  → TunnelRuntimeConfiguration
```

这样 `IrockCore` 保持依赖无关，只定义可编码运行数据；`IrockRouting` 继续只理解自己的规则模型；`IrockTunnelCore` 负责运行时连接两者。

## 4. 错误策略

新增 `RuntimeRoutingRuleAdapterError: Error, Equatable, Sendable`：

```swift
case missingValue(kind: RuntimeRoutingRuleKind)
```

行为：

- `.finalRule` 忽略 value。
- `.domain`、`.domainSuffix`、`.domainKeyword`、`.ipCIDR` 必须有非空 value。
- M8 不重新校验 CIDR 文本；CIDR 语义仍由 `IrockRouting` 的 parser/engine 负责。

## 5. 测试策略

M8 扩展 `IrockTunnelCoreTests`，覆盖：

1. adapter 转换所有 runtime rule kinds。
2. adapter 转换所有 runtime actions。
3. adapter 对非 FINAL 缺少 value 返回 `.missingValue`。
4. `TunnelRuntimeConfiguration(snapshot:batchLimit:flowLimit:)` 从 manifest 创建 routing engine。
5. 空 manifest 下 rule-based routing 使用 routing engine default reject 行为。
6. 显式传入 routing engine 的 initializer 继续可用。
7. 全量 `swift test` 通过。

## 6. 成功标准

M8 完成时：

- `RuntimeRoutingRuleManifest` 可以转换成 `[RoutingRule]`。
- `TunnelRuntimeConfiguration` 可以从 snapshot manifest 创建 routing engine。
- 现有显式 `RoutingEngine` initializer 仍工作。
- 不引入 `IrockCore` → `IrockRouting` 依赖。
- README 和 CLAUDE.md 准确说明 M8 runtime rule adapter foundation。
