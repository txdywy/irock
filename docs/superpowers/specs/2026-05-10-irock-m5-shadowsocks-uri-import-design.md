# irock M5 Shadowsocks URI Import Design

日期：2026-05-10

## 1. 目标

M5 将 M1 的 URI import entry point 从“只识别 scheme”推进到可导入最小 Shadowsocks 节点：`ss://` URI 被解析成 `NodeDraft`，之后沿用现有 `NodeDraft.buildNode(...)` 生成 `ProxyNode`。

本阶段仍保持 SwiftPM 可测试，不实现真实 Shadowsocks 协议握手，不保存凭据明文，不创建 Xcode target，也不接 Keychain 或 App Group。

## 2. 范围

M5 实现：

- 在 `IrockAppFeature.URIImport` 中新增 Shadowsocks URI 解析能力。
- 支持常见 SIP002 形态：
  - `ss://BASE64(method:password@host:port)#Name`
  - `ss://BASE64(method:password)@host:port#Name`
- 解码 URI fragment 作为节点名；没有 fragment 时使用 `host:port` 作为名称。
- 将 Shadowsocks URI 转成 `NodeDraft`：
  - `protocolType = .shadowsocks`
  - `serverHost` 和 `serverPortText` 来自 URI
  - `credentialAccount` 使用 `method:password`
  - `transport = .tcp`
  - `tlsEnabled = false`
  - `tlsServerName = ""`
  - `udpEnabled = false`
- 用明确错误表达 malformed URI、base64 解码失败、缺少 user info、缺少 host、缺少 port。

M5 不实现：

- VMess/VLESS/Trojan/Hysteria2/TUIC URI 解析。
- Shadowsocks plugin 参数、`?plugin=...` 参数、SIP008 JSON。
- 加密方法白名单校验。
- Keychain 写入或 credential 加密。
- 订阅 URL 批量导入。
- UI 粘贴板、二维码、文件导入。

## 3. 架构

继续使用 `URIImport` 作为 AppFeature 的 URI 入口：

```text
URIImport
  classify(text) -> URIImportResult
  parseShadowsocksDraft(text) -> NodeDraft
```

`classify(_:)` 保持现有行为。新增 `parseShadowsocksDraft(_:)` 只处理 `ss://`，让后续协议可以逐个追加独立 parser，而不是一次性扩大导入系统。

`NodeDraft` 继续作为 editable app configuration 和 `ProxyNode` 之间的边界，因此 URI parser 不直接创建 `ProxyNode`，也不接触 Keychain service。

## 4. URI 支持格式

### 4.1 全量 base64 authority

```text
ss://BASE64(method:password@host:port)#Name
```

示例：

```text
ss://YWVzLTI1Ni1nY206cGFzc0BleGFtcGxlLmNvbTo4Mzg4#Demo%20SS
```

解析为：

```text
name = Demo SS
serverHost = example.com
serverPortText = 8388
credentialAccount = aes-256-gcm:pass
```

### 4.2 userinfo base64

```text
ss://BASE64(method:password)@host:port#Name
```

示例：

```text
ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo%20SS
```

解析结果同上。

### 4.3 base64 variant

Parser 支持标准 base64 和 URL-safe base64，并自动补齐缺失 padding。

## 5. 错误策略

扩展 `URIImportError`：

```swift
case malformedURI
case invalidBase64
case missingUserInfo
case missingHost
case missingPort
```

行为：

- 非 `ss://` 输入调用 `parseShadowsocksDraft` 时返回 `.unsupportedScheme(scheme)`。
- 无法拆分 URI 或 authority 为空返回 `.malformedURI`。
- base64 解码失败返回 `.invalidBase64`。
- 解码后没有 `method:password` 返回 `.missingUserInfo`。
- host 缺失返回 `.missingHost`。
- port 缺失返回 `.missingPort`。
- port 文本是否合法继续交给 `NodeDraft.buildNode(...)` 验证。

## 6. 测试策略

扩展 `URIImportTests`，覆盖：

1. 解析 `ss://BASE64(method:password@host:port)#Name`。
2. 解析 `ss://BASE64(method:password)@host:port#Name`。
3. fragment 百分号解码成节点名。
4. 缺少 fragment 时名称使用 `host:port`。
5. URL-safe base64 和缺失 padding 可解析。
6. 非 `ss://` 输入返回 `.unsupportedScheme`。
7. 无效 base64 返回 `.invalidBase64`。
8. 缺少 user info 返回 `.missingUserInfo`。
9. 缺少 host 返回 `.missingHost`。
10. 缺少 port 返回 `.missingPort`。

所有测试只验证 `NodeDraft` 字段和错误，不写 Keychain、不访问文件系统、不建立网络连接。

## 7. 成功标准

M5 完成时：

- `URIImport.classify(_:)` 现有测试继续通过。
- `URIImport.parseShadowsocksDraft(_:)` 能把常见 `ss://` URI 转成 `NodeDraft`。
- 解析失败有稳定、可测试的错误分类。
- `NodeDraft.buildNode(...)` 可继续从导入 draft 构造 `.shadowsocks` 节点。
- `swift test` 全量通过。
- README 和 CLAUDE.md 能准确说明 M0-M5 当前状态。
