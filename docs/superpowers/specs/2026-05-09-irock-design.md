# irock 技术攻坚型 Alpha 设计规格

日期：2026-05-09

## 1. 产品定位

**irock** 是一款面向 iOS 和 macOS 的个人自用科学上网客户端，产品体验高相似度参考 Shadowrocket：主界面以连接开关、当前节点、节点列表、规则、日志、配置为核心。首个大版本目标不是上架商业化，而是在个人设备上稳定运行。

首批 Alpha 的目标：

- iOS/macOS 双平台同步开发。
- 通过 Packet Tunnel 实现系统级 TUN VPN。
- 架构上同时保留本地 SOCKS/HTTP 代理模式。
- 使用 Swift + Apple 系统库优先实现核心能力。
- App 内不嵌入 sing-box/xray/clash 等大内核。
- 开发期允许用 sing-box/xray/clash 做协议对照验证。
- 首批 Alpha 跑通 SS、VMess、VLESS、Trojan 及主流传输组合，包括 TCP、TLS、WebSocket、gRPC、HTTP/2、Reality、QUIC/Hysteria/TUIC。
- 性能按最新 Apple Silicon Mac 和近两代 iPhone 验收：Wi‑Fi 单连接 ≥600 Mbps、额外延迟 ≤10ms、Packet Tunnel 内存 ≤50MB。
- 首版数据本地优先，不做账号、不做 iCloud。
- 首版日志面向普通使用，默认只记录连接成功/失败、当前节点、简单错误信息。

首批 Alpha 不优先做：

- App Store 商业发布合规。
- 账号体系、订阅购买、云同步。
- 完整订阅 URL 导入和 Clash YAML 全量兼容。
- 自动测速择优和复杂策略自动选择。
- 高级可视化诊断面板。
- 像素级复制 Shadowrocket 素材或图标。
- 嵌入第三方完整代理内核运行。

## 2. 总体架构

项目采用 Xcode Workspace + Swift Package 混合结构：

```text
irock/
  irock.xcworkspace
  apps/
    irock-iOS/
      irockApp/
      irockTunnelExtension/
    irock-macOS/
      irockMacApp/
      irockMacTunnelExtension/
  packages/
    IrockCore/
    IrockProtocols/
    IrockRouting/
    IrockTransport/
    IrockStorage/
    IrockDiagnostics/
    IrockPerformanceKit/
  tools/
    protocol-lab/
    benchmark-runner/
    config-fixtures/
  tests/
    protocol-fixtures/
    routing-fixtures/
    performance-baselines/
```

核心原则：平台壳很薄，核心能力在 shared packages 中。

### 2.1 主 App

主 App 负责：

- Shadowrocket 风格主界面。
- 节点列表、节点编辑、URI 导入。
- 规则页面、配置页面、日志页面。
- VPN 开关与系统授权引导。
- 写入 App Group 中的运行配置快照。
- 展示基础连接状态。

主 App 不处理 packet 数据，不执行协议代理转发，不在 UI 层做规则匹配热路径。

### 2.2 Packet Tunnel Extension

Tunnel Extension 负责：

- 读取 App Group 中的运行快照。
- 配置 `NEPacketTunnelNetworkSettings`。
- 从 `packetFlow` 读取 IP packet。
- 调用路由引擎判断 direct/proxy/reject。
- 调用协议适配器建立出站连接。
- 写回响应 packet。
- 记录最小化运行日志和性能计数。

关键约束：

- 不依赖主 App 进程在线。
- 不访问 UI 状态。
- 限制内存、日志、缓存。
- 所有运行配置在启动时形成不可变快照。

### 2.3 Shared Packages

- `IrockCore`：通用类型和协调逻辑，例如 `ProxyNode`、`RuntimeSnapshot`、`ConnectionState`、`IrockError`。
- `IrockProtocols`：SS、VMess、VLESS、Trojan、Hysteria2、TUIC、Reality 适配器。
- `IrockTransport`：TCP、TLS、WebSocket、HTTP/2、gRPC、QUIC 传输适配。
- `IrockRouting`：规则解析、预编译和路由决策。
- `IrockStorage`：本地配置、App Group 快照、基础日志、Keychain 凭据。
- `IrockDiagnostics`：用户日志、Debug 日志、错误展示。
- `IrockPerformanceKit`：吞吐、延迟、内存、握手耗时、规则匹配耗时测量。

## 3. 协议与传输兼容性

所有协议节点归一到统一模型：

```text
ProxyNode
  id
  name
  protocolType
  serverHost
  serverPort
  credentials
  transport
  tls
  multiplex
  udpPolicy
  metadata
```

协议类型：

```text
shadowsocks
vmess
vless
trojan
hysteria2
tuic
```

传输类型：

```text
tcp
ws
http2
grpc
quic
```

TLS 配置：

```text
enabled
serverName
allowInsecure
alpn
fingerprint
realityOptions
```

每个协议实现统一 `ProxyAdapter` 概念接口：

```swift
protocol ProxyAdapter {
    func connect(request: ProxyRequest) async throws -> ProxyConnection
}
```

适配器职责包括参数校验、协议握手、绑定传输层、TCP 转发、按协议能力提供 UDP 转发、输出统一错误。

首批 Alpha 目标覆盖：

| 协议 | TCP | TLS | WebSocket | HTTP/2 | gRPC | Reality | QUIC |
|---|---:|---:|---:|---:|---:|---:|---:|
| Shadowsocks | 是 | 插件型扩展项 | 不作为 Alpha 验收项 | 否 | 否 | 否 | 否 |
| VMess | 是 | 是 | 是 | 是 | 是 | 否 | 否 |
| VLESS | 是 | 是 | 是 | 是 | 是 | 是 | 否 |
| Trojan | 是 | 是 | 是 | 是 | 是 | 否 | 否 |
| Hysteria2 | 否 | 内建 | 否 | 否 | 否 | 否 | 是 |
| TUIC | 否 | 内建 | 否 | 否 | 否 | 否 | 是 |

Reality 单独建模为 `RealityOptions`，不混入普通 TLS 配置。Hysteria2/TUIC 作为独立 QUIC 协议族处理。上表中的“是”均为 Alpha 发布前必须通过至少一个真实节点验收的范围；“插件型扩展项”和“不作为 Alpha 验收项”不阻塞首批 Alpha。

首批 URI 导入支持：

- `ss://`
- `vmess://`
- `vless://`
- `trojan://`
- `hysteria2://`
- `tuic://`

开发期建立 `protocol-lab`，同一节点配置分别跑 irock 自研实现和 sing-box/xray/clash 对照实现，对比握手成功率、首包耗时、TLS/ALPN/SNI 行为、UDP 可用性、错误原因和吞吐表现。

统一协议错误分类：

```text
invalidConfiguration
dnsFailed
tcpConnectFailed
tlsHandshakeFailed
authenticationFailed
unsupportedTransport
protocolHandshakeFailed
quicHandshakeFailed
udpUnsupported
remoteClosed
timeout
```

## 4. TUN、路由和规则系统

Tunnel 启动流程：

```text
读取 RuntimeSnapshot
  → 配置虚拟 IPv4/IPv6 地址
  → 配置 DNS
  → 配置 includedRoutes / excludedRoutes
  → 初始化 Packet Processor
  → 初始化 Routing Engine
  → 初始化 Proxy Adapter
```

运行时数据路径：

```text
packetFlow.readPackets
  → packet batch
  → packet parser
  → flow classifier
  → routing decision
  → direct/proxy/reject
  → writePackets
```

核心组件：

- `PacketReader`：批量读取 packet。
- `PacketParser`：解析 IPv4/IPv6、TCP、UDP、ICMP 基础字段。
- `FlowTable`：把 packet 映射到连接流，维护最小状态。
- `RouteResolver`：根据目标 host/IP、端口、协议和规则做决策。
- `ProxyOutbound`：走选中节点的代理适配器。
- `DirectOutbound`：直连目标地址。
- `PacketWriter`：批量写回响应 packet。

规则类型：

```text
DOMAIN
DOMAIN-SUFFIX
DOMAIN-KEYWORD
IP-CIDR
GEOIP
PROCESS-NAME
FINAL
```

动作：

```text
DIRECT
PROXY
REJECT
```

首批连接体验是单节点手动选择。规则中 `PROXY` 表示走当前选中节点，未来可扩展为策略组动作。

规则采用自上而下匹配，第一条命中即返回动作，无命中走 `FINAL`。

规则预编译策略：

- `DOMAIN-SUFFIX` 编译为反向域名 trie。
- `DOMAIN` 编译为 hash set。
- `DOMAIN-KEYWORD` Alpha 阶段使用优化数组并纳入规则匹配性能验收；如果 P95 超出预算，再替换为 Aho-Corasick。
- `IP-CIDR` 编译为 prefix trie / radix tree。
- `GEOIP` 使用压缩 IP 区间表。
- `FINAL` 单独保存。

远程规则纳入设计：更新失败时保留上一版缓存，UI 显示更新失败，不影响当前 VPN 连接。

## 5. UI 信息架构

UI 高相似度参考 Shadowrocket 的信息架构和操作路径，但不复制素材、图标、精确配色、精确间距、专有文案或像素级布局。

### 5.1 iOS

iOS 采用高密度列表结构：

```text
首页
  连接开关
  当前状态
  当前节点
  路由模式
  节点列表入口
  规则入口
  日志入口
  配置入口
```

底层页面：

```text
节点
  手动添加
  URI 导入
  节点编辑
  协议参数
  传输参数
  TLS/Reality/QUIC 参数

规则
  路由模式
  本地规则列表
  远程规则入口
  FINAL 行为

日志
  连接记录
  错误摘要
  当前节点
  最近状态

设置
  VPN 权限
  App Group 状态
  调试开关
  数据清理
```

### 5.2 macOS

macOS 使用工具型桌面布局：

```text
侧边栏
  概览
  节点
  规则
  日志
  设置
```

概览页展示连接状态、当前节点、路由模式、性能摘要、最近日志。菜单栏状态提供连接/断开、当前节点、最近错误、打开主窗口。

### 5.3 状态模型

统一连接状态：

```text
Disconnected
Preparing
Connecting
Connected
Reconnecting
Disconnecting
Failed
```

UI 简化展示为未连接、连接中、已连接、连接失败。

## 6. 数据存储、错误处理与性能验收

首批 Alpha 本地优先：

```text
UserConfiguration
  节点列表
  规则列表
  路由模式
  最近选择节点
  基础设置

RuntimeSnapshot
  当前选中节点
  已编译规则 manifest
  DNS 策略
  日志级别
  运行参数

ConnectionLog
  时间
  节点
  状态
  错误摘要

PerformanceSample
  时间
  协议
  吞吐
  延迟
  内存
```

存储位置：

- 主 App 私有容器：完整用户配置。
- App Group：Extension 运行需要的快照和最小状态。
- Keychain：敏感凭据，例如密码、UUID、token。
- Extension：只读快照，写少量状态和日志。

连接前主 App 校验配置、读取选中节点、编译规则、生成 `RuntimeSnapshot`、写入 App Group、请求启动 Tunnel。连接中用户编辑配置只更新 `UserConfiguration`，UI 提示“重连后生效”。

错误分层：

```text
ConfigurationError
TunnelError
ProtocolError
RoutingError
```

首页只显示一句摘要，日志页显示最近错误列表，Debug 模式显示错误阶段、协议、传输、节点 ID。

用户日志默认只记录连接开始、连接成功、连接失败、断开连接、当前节点、简单错误摘要。日志固定最大条数，环形写入，默认不记录每个请求。

旗舰目标设备：Apple Silicon Mac 和近两代 iPhone 真机。

硬指标：

```text
Wi‑Fi 单连接吞吐 ≥600 Mbps
额外延迟 ≤10ms
Packet Tunnel 内存 ≤50MB
```

扩展指标：

```text
Tunnel 启动时间 ≤2s
规则匹配 P95 ≤0.2ms
DNS 查询缓存命中 P95 ≤1ms
空闲 10 分钟内存无持续增长
连续运行 2 小时无崩溃
```

## 7. 测试策略和里程碑

测试分层：

- 单元测试：URI 解析、节点参数校验、规则解析、规则预编译、路由决策、错误映射、RuntimeSnapshot 序列化。
- 协议测试：SS、VMess、VLESS、Trojan、Reality、Hysteria2/TUIC、TCP 转发、UDP 转发。
- Tunnel 集成测试：iOS/macOS Packet Tunnel 启停、Global Proxy、Rule Based、DNS、断网恢复、节点失败提示。
- UI 测试：选择节点、添加节点、URI 导入、连接/断开、查看日志、切换路由模式、VPN 权限引导。
- 性能测试：吞吐、延迟、内存、启动时间、规则匹配、协议握手、长时间运行。

内部里程碑：

1. **M0 工程底座**：Workspace、App Target、Tunnel Extension、App Group、Shared Packages、基础 CI/test scheme。
2. **M1 基础 UI 与配置**：首页、节点列表、手动添加、URI 导入入口、基础日志页、设置页。
3. **M2 TUN 数据路径**：Packet 读写、FlowTable、Global Proxy、Direct/Proxy/Reject、DNS 基础处理。
4. **M3 基础协议**：Shadowsocks、Trojan、VMess/VLESS TCP/TLS、统一协议错误模型。
5. **M4 高级传输**：WebSocket、HTTP/2、gRPC、Reality。
6. **M5 QUIC 协议**：Hysteria2、TUIC、QUIC transport、UDP 转发能力。
7. **M6 规则系统**：DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR、GEOIP、FINAL、规则模式 UI、远程规则缓存设计。
8. **M7 性能攻坚**：benchmark runner、内存采样、吞吐测试、延迟测试、热路径优化、长时间运行测试。
9. **M8 Alpha 集成**：双平台完整 Alpha、节点管理、单节点手动选择、一键连接、基础日志、规则模式、全协议/传输验收报告。

## 8. 主要风险与缓解

### Swift + 系统库实现 QUIC/Reality 难度高

缓解：单独做协议实验室，用参考实现对照。必要时允许引入小型辅助库，但不集成完整代理内核。

### Packet Tunnel 内存 ≤50MB 难度高

缓解：规则、日志、FlowTable 全部设上限；热路径避免频繁分配；性能测试从 M2 开始。

### 首批范围过大

缓解：内部分里程碑推进，Alpha 发布前全量验收，每个协议独立 fixture 和验收记录，不把订阅、云同步、商业化纳入首批关键路径。

### UI 高相似度带来版权或审查问题

缓解：参考信息架构，不复制素材；自定义图标、配色、文案；商业发布前重新审查视觉差异。

## 9. 设计结论

irock 采用 **技术攻坚型 Alpha** 路线：

- 双平台 SwiftUI + shared Swift packages。
- iOS/macOS Packet Tunnel Extension 同步设计。
- 主 App 与 Extension 通过 App Group 和 RuntimeSnapshot 解耦。
- 协议通过 `ProxyAdapter` 插件化。
- 传输通过 `TransportAdapter` 复用 TCP/TLS/WS/gRPC/HTTP2/QUIC。
- 规则系统从一开始支持 Shadowrocket/Clash 风格，但首批交互保持单节点手动选择。
- UI 高相似度参考 Shadowrocket 的信息架构，视觉素材保持独立。
- 性能指标从首批纳入硬验收。
- 第三方代理内核只作为开发期对照，不进入 App 运行时。
