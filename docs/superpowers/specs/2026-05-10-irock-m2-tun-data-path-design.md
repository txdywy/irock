# irock M2 TUN 数据路径设计规格

日期：2026-05-10

## 1. 目标

M2 建立 irock 的可测试 TUN 数据路径核心，但不创建真实 Xcode app target、Packet Tunnel target，也不直接依赖 `NetworkExtension`。

M2 的交付重点是新增 `IrockTunnelCore` SwiftPM 包，用 mock packet reader/writer 在 `swift test` 中跑通：

```text
packet batch → parse → flow table → route decision → packet action → writer
```

未来真实 `PacketTunnelProvider` 只负责把 Apple 的 `packetFlow` 适配成 M2 定义的 reader/writer 协议，然后调用 `PacketTunnelRuntime`。

## 2. 非目标

M2 不做以下内容：

- 不创建 `irock.xcworkspace`、app target 或 Packet Tunnel extension target。
- 不配置 `NEPacketTunnelNetworkSettings`。
- 不调用真实 `packetFlow.readPackets` / `packetFlow.writePackets`。
- 不实现 TCP stream reconstruction。
- 不实现 UDP relay。
- 不做真实 DNS 查询、缓存或劫持。
- 不调用协议 adapter 或 transport adapter 建立出站连接。
- 不实现吞吐/延迟 benchmark。
- 不引入 sing-box、xray、clash 或其他完整代理内核。

## 3. 包边界

新增 SwiftPM product/target：

```text
IrockTunnelCore
```

依赖关系：

```text
IrockTunnelCore
  → IrockCore
  → IrockRouting
```

`IrockTunnelCore` 不依赖：

- `IrockProtocols`
- `IrockTransport`
- `IrockStorage`
- `IrockDiagnostics`
- `NetworkExtension`

原因：M2 只负责 packet 数据路径决策，不负责真实出站连接、持久化、UI 状态或系统 extension 生命周期。

## 4. 核心组件

### 4.1 PacketTunnelRuntime

`PacketTunnelRuntime` 是未来 Packet Tunnel extension 的调用边界。它负责：

1. 从 `PacketReader` 读取 packet batch。
2. 调用 `PacketProcessor` 处理 batch。
3. 将处理结果交给 `PacketWriter`。
4. 返回可测试的 runtime summary，例如处理数量、写出数量、drop 数量。

M2 中 runtime 只处理有限 batch 或单次 run，不实现长期循环、取消、后台生命周期、重连或系统 VPN 状态管理。

### 4.2 PacketReader / PacketWriter

`PacketReader` 抽象 packet 输入：

```swift
protocol PacketReader {
    func readBatch() async throws -> [Packet]
}
```

`PacketWriter` 抽象 packet 输出或处理结果记录：

```swift
protocol PacketWriter {
    func write(_ results: [PacketProcessingResult]) async throws
}
```

M2 提供 in-memory/mock 实现，供 XCTest 构造 packet batch 并检查写出结果。真实 `packetFlow` 适配器留给 Xcode/NetworkExtension 阶段。

### 4.3 PacketParser

`PacketParser` 解析 enough-to-route 的最小 packet 信息：

- IP version
- source IP
- destination IP
- transport protocol
- source port
- destination port
- DNS candidate 标记

M2 优先支持 IPv4 TCP/UDP。IPv6 可以保留类型空间，但不作为 M2 必须解析范围。

### 4.4 FlowTable

`FlowTable` 把 parsed packet 映射到稳定 `FlowKey`：

```text
source IP + source port + destination IP + destination port + protocol
```

FlowTable 维护最小状态：

- flow key
- packet count
- last seen sequence 或 timestamp-like counter

FlowTable 必须有容量上限。容量超限行为在 M2 中必须明确且可测：优先采用移除最旧 flow 的策略，而不是无界增长。

### 4.5 PacketProcessor

`PacketProcessor` 串联数据路径：

```text
PacketParser
  → FlowTable
  → routing decision
  → PacketProcessingResult
```

它不执行 direct/proxy 的真实 I/O。它只返回 action，供后续阶段把 action 绑定到 direct outbound、proxy outbound 或 reject 行为。

### 4.6 TunnelRuntimeConfiguration

`TunnelRuntimeConfiguration` 是 runtime 的冻结输入，包含：

- `RuntimeSnapshot`
- route mode
- routing rules 或 routing engine
- batch limit
- flow limit

M2 runtime 不从 UI、storage、database、Keychain 读取状态。所有运行输入必须在配置对象中显式传入。

## 5. 数据流

M2 标准数据流：

```text
PacketReader.readBatch()
  → PacketParser.parse(packet)
  → FlowTable.record(parsedPacket)
  → RouteResolver / route mode decision
  → PacketProcessor returns PacketProcessingResult
  → PacketWriter.write(results)
```

route mode 行为：

- `.globalProxy`：所有可路由 TCP/UDP flow 返回 `.proxy`。
- `.direct`：所有可路由 TCP/UDP flow 返回 `.direct`。
- `.ruleBased`：调用 `IrockRouting.RoutingEngine`，根据目标 host/ip/port 返回 `.direct`、`.proxy` 或 `.reject`。

无法解析或暂不支持的 packet 返回 `.drop`，并携带原因码。

DNS 行为：M2 只识别 UDP/53 为 DNS candidate，不做真实 DNS 查询、缓存或响应生成。

ICMP 行为：M2 返回 `.drop(.unsupportedProtocol)`，不实现 ping 转发。

## 6. 结果与错误模型

M2 使用强类型结果，不用字符串日志表达控制流。

```swift
enum PacketParseError: Equatable, Sendable {
    case tooShort
    case unsupportedIPVersion
    case unsupportedTransportProtocol
    case truncatedHeader
}

enum PacketDropReason: Equatable, Sendable {
    case parseFailed(PacketParseError)
    case unsupportedProtocol
    case flowLimitExceeded
    case noRoute
}

enum PacketAction: Equatable, Sendable {
    case direct(FlowKey)
    case proxy(FlowKey)
    case reject(FlowKey)
    case drop(PacketDropReason)
}
```

`PacketProcessingResult` 至少包含：

- 原始 packet 或 packet id
- parsed packet（成功时）
- flow key（成功时）
- action

## 7. 测试策略

M2 必须通过 SwiftPM XCTest 验证，不依赖 Xcode scheme。

### 7.1 PacketParserTests

覆盖：

- IPv4 TCP packet 解析目的 IP/port。
- IPv4 UDP packet 解析目的 IP/port。
- UDP/53 标记为 DNS candidate。
- 短包返回 `.tooShort` 或 `.truncatedHeader`。
- 非 IPv4 版本返回 `.unsupportedIPVersion`。
- 不支持的 transport protocol 返回 `.unsupportedTransportProtocol`。

### 7.2 FlowTableTests

覆盖：

- 相同五元组生成稳定 flow key。
- 重复 packet 更新 packet count。
- 容量上限触发最旧 flow 淘汰。

### 7.3 PacketProcessorTests

覆盖：

- global proxy mode 返回 `.proxy`。
- direct mode 返回 `.direct`。
- rule based + final reject 返回 `.reject`。
- malformed packet 返回 `.drop(.parseFailed(...))`。
- unsupported protocol 返回 `.drop(.unsupportedProtocol)`。

### 7.4 PacketTunnelRuntimeTests

覆盖：

- in-memory reader 提供 batch。
- runtime 调用 processor。
- in-memory writer 收到 processing results。
- summary 计数正确。

### 7.5 TunnelRuntimeConfigurationTests

覆盖：

- configuration 消费 `RuntimeSnapshot.routeMode`。
- configuration 显式持有 runtime limits。
- runtime 不从 storage/UI/global state 读取状态。

## 8. 交付文件

M2 实现计划应创建或修改：

```text
Package.swift
packages/IrockTunnelCore/Sources/IrockTunnelCore/...
packages/IrockTunnelCore/Tests/IrockTunnelCoreTests/...
README.md
CLAUDE.md
```

建议源码文件按职责拆分：

```text
Packet.swift
PacketParser.swift
FlowTable.swift
PacketProcessor.swift
PacketTunnelRuntime.swift
TunnelRuntimeConfiguration.swift
InMemoryPacketIO.swift
```

测试文件按组件拆分：

```text
PacketParserTests.swift
FlowTableTests.swift
PacketProcessorTests.swift
PacketTunnelRuntimeTests.swift
TunnelRuntimeConfigurationTests.swift
```

## 9. 成功标准

M2 完成时必须满足：

- `IrockTunnelCore` product/target/test target 存在。
- `swift test --filter IrockTunnelCoreTests` 通过。
- `swift test` 全量通过。
- mock packet batch 能跑通 parse → flow → route → action → writer。
- M2 没有新增 Xcode workspace、app target、Packet Tunnel target 或 NetworkExtension 依赖。
- packet/flow/runtime 组件职责清晰，文件保持可独立理解和测试。

## 10. 后续衔接

M2 完成后，后续阶段可以按以下方向扩展：

- Xcode/Packet Tunnel 阶段：将真实 `NEPacketTunnelFlow` 适配为 `PacketReader` / `PacketWriter`。
- M3/M4/M5：把 `.proxy` action 接入协议和传输 adapter。
- M6：用完整规则系统替换 M2 的最小 route decision glue。
- M7：对 parser、flow table、processor 加入性能计数和 benchmark。

M2 的核心价值是提前固定 Tunnel Extension 与共享数据路径之间的接口，使后续真实系统集成尽量变成适配问题，而不是重新设计数据路径。
