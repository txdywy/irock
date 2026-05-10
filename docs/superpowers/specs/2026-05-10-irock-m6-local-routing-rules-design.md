# irock M6 Local Routing Rules Design

日期：2026-05-10

## 1. 目标

M6 将现有 `IrockRouting` 从“手写 `RoutingRule` 数组”推进到可解析本地规则文本，并生成可复用的预编译规则集。目标是让 App 后续可以保存 Shadowrocket/Clash 风格的本地规则文本，Tunnel 只消费已经规范化的规则数据。

本阶段保持 SwiftPM 可测试，不接 UI、不接远程规则、不接 GEOIP 数据库、不改 Packet Tunnel 热路径。

## 2. 范围

M6 实现：

- 支持解析本地规则行：
  - `DOMAIN,example.com,DIRECT`
  - `DOMAIN-SUFFIX,apple.com,DIRECT`
  - `DOMAIN-KEYWORD,google,PROXY`
  - `IP-CIDR,10.0.0.0/8,DIRECT`
  - `FINAL,PROXY`
- 支持空行和 `#` 注释。
- 将规则动作解析为现有 `RoutingAction`：`DIRECT`、`PROXY`、`REJECT`。
- 扩展 `RoutingRule` 以表达 `DOMAIN`、`DOMAIN-KEYWORD`、`IP-CIDR`。
- 新增 `RoutingRuleParser.parseLines(_:)`，返回规则数组。
- 新增 `CompiledRoutingRules`，在初始化时规范化域名、关键字和 CIDR 文本。
- `RoutingEngine` 接受 `CompiledRoutingRules`，并保持现有 `[RoutingRule]` 初始化方式兼容。
- 路由决策支持：精确域名、域名后缀、域名关键字、IPv4 CIDR、FINAL。

M6 不实现：

- GEOIP 数据库或 geosite 规则。
- PROCESS-NAME 规则。
- 远程规则下载、缓存和更新失败保留策略。
- 规则 UI。
- RuntimeSnapshot 编码变更。
- Packet Tunnel 集成变更。
- IPv6 CIDR。

## 3. 架构

M6 保持规则系统边界在 `IrockRouting` 包内：

```text
routing text
  → RoutingRuleParser.parseLines
  → [RoutingRule]
  → CompiledRoutingRules
  → RoutingEngine.resolve
```

`RoutingRuleParser` 只负责文本到规则模型，不做路由判断。`CompiledRoutingRules` 负责规范化和分桶，避免 `RoutingEngine.resolve(_:)` 每次都重复 lowercased / trimming 操作。`RoutingEngine` 继续输出现有 `RoutingDecision`，让 `IrockTunnelCore` 不需要改变调用方式。

## 4. 规则语义

### 4.1 DOMAIN

`DOMAIN,example.com,DIRECT` 只匹配 `example.com`，大小写不敏感，忽略 host 末尾的点。不匹配 `www.example.com`。

### 4.2 DOMAIN-SUFFIX

`DOMAIN-SUFFIX,apple.com,DIRECT` 匹配 `apple.com` 和 `developer.apple.com`，大小写不敏感，忽略 host 末尾的点。

### 4.3 DOMAIN-KEYWORD

`DOMAIN-KEYWORD,google,PROXY` 匹配规范化 host 中包含 `google` 的请求。

### 4.4 IP-CIDR

`IP-CIDR,10.0.0.0/8,DIRECT` 匹配 IPv4 字符串地址。M6 只支持 IPv4 CIDR；非法 IPv4、非法 prefix、IPv6 输入都返回解析错误或不匹配。

### 4.5 FINAL

`FINAL,PROXY` 是兜底规则。解析后仍保留在规则顺序中；路由时遇到即返回对应动作。

## 5. 错误策略

新增 `RoutingRuleParseError: Error, Equatable, Sendable`：

```swift
case emptyInput
case invalidFieldCount(line: Int, text: String)
case unsupportedRuleType(line: Int, type: String)
case unsupportedAction(line: Int, action: String)
case emptyValue(line: Int)
case invalidCIDR(line: Int, value: String)
```

行为：

- 输入所有有效行为空时返回 `.emptyInput`。
- 非 `FINAL` 规则必须有 3 个字段。
- `FINAL` 必须有 2 个字段。
- 未支持的规则类型返回 `.unsupportedRuleType`。
- 未支持的动作返回 `.unsupportedAction`。
- 空 value 返回 `.emptyValue`。
- `IP-CIDR` 的 IPv4 或 prefix 非法返回 `.invalidCIDR`。

## 6. 测试策略

M6 扩展 `IrockRoutingTests`，覆盖：

1. 解析空行和注释后得到有效规则。
2. 解析 `DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD`、`IP-CIDR`、`FINAL`。
3. 不支持规则类型、动作、字段数、空输入、非法 CIDR 的错误稳定。
4. `RoutingEngine` 匹配精确域名。
5. `RoutingEngine` 匹配域名后缀。
6. `RoutingEngine` 匹配域名关键字。
7. `RoutingEngine` 匹配 IPv4 CIDR。
8. 规则顺序优先于后续规则。
9. 没有命中时使用显式 default action。
10. 旧的 `[RoutingRule]` 初始化方式继续可用。

## 7. 成功标准

M6 完成时：

- `RoutingRuleParser.parseLines(_:)` 可解析本地规则文本。
- `CompiledRoutingRules` 可从规则数组构建。
- `RoutingEngine` 可消费编译规则并支持 DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR、FINAL。
- 现有 routing 测试继续通过。
- `swift test --filter IrockRoutingTests` 和全量 `swift test` 通过。
- README 和 CLAUDE.md 准确说明 M6 本地规则解析与预编译基础。
