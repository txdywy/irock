# irock M3 Runtime Snapshot Persistence Design

日期：2026-05-10

## 1. 目标

M3 补齐 M1 app configuration foundation 和 M2 tunnel runtime core 之间的持久化边界：未来主 App 生成并保存 `RuntimeSnapshot`，未来 Packet Tunnel 只读取冻结后的 snapshot 并构造 `TunnelRuntimeConfiguration`。

本阶段只实现 SwiftPM 可测试的文件存储能力，不创建 Xcode workspace、app target、Packet Tunnel target，也不接入真实 App Group entitlement。

## 2. 范围

M3 实现：

- 在 `IrockStorage` 中新增文件版 `RuntimeSnapshotStore` 实现。
- 使用 JSON 编码和解码 `RuntimeSnapshot`。
- 使用调用方传入的目录 URL 存放 runtime snapshot 文件。
- 用 XCTest 覆盖 round-trip、missing file、overwrite、corrupt JSON、自动创建目录。

M3 不实现：

- `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` 调用。
- `.xcodeproj`、`.xcworkspace`、iOS/macOS app target、Packet Tunnel target。
- 多 snapshot 历史、迁移版本、加密、锁文件。
- 默认节点 fallback 或配置自动修复。
- credential 明文存储；snapshot 继续只包含 `CredentialReference`。

## 3. 架构

继续使用现有协议：

```swift
public protocol RuntimeSnapshotStore {
    func save(_ snapshot: RuntimeSnapshot) throws
    func load() throws -> RuntimeSnapshot?
}
```

现有 `InMemoryRuntimeSnapshotStore` 保留用于测试、预览和无文件系统场景。

新增 `FileRuntimeSnapshotStore`，职责限定为“把一个 `RuntimeSnapshot` 存到一个目录中的固定 JSON 文件，并从该文件读取”。它不负责寻找 App Group container，也不理解平台 entitlement。

```text
IrockStorage
  RuntimeSnapshotStore
    ├─ InMemoryRuntimeSnapshotStore
    └─ FileRuntimeSnapshotStore
```

`FileRuntimeSnapshotStore` 初始化参数：

```swift
public init(directoryURL: URL)
```

固定文件名：

```text
runtime-snapshot.json
```

## 4. 数据流

```text
AppFeature / future app shell
  → builds RuntimeSnapshot
  → FileRuntimeSnapshotStore.save(snapshot)
  → shared directory/runtime-snapshot.json
  → future Packet Tunnel shell
  → FileRuntimeSnapshotStore.load()
  → TunnelRuntimeConfiguration(snapshot: ...)
  → PacketTunnelRuntime
```

未来真实 App Group 集成时，平台壳负责取得共享目录：

```text
FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ...)
  → FileRuntimeSnapshotStore(directoryURL: containerURL)
```

这样 `IrockStorage` 仍保持 SwiftPM 可测，不需要导入 `NetworkExtension` 或依赖签名配置。

## 5. 行为要求

### save

`save(_:)` 必须：

- 确保 `directoryURL` 存在；不存在时创建目录。
- 使用 `JSONEncoder` 编码 `RuntimeSnapshot`。
- 写入 `directoryURL/runtime-snapshot.json`。
- 覆盖已有 snapshot。
- 写入失败时抛出底层错误，不吞错。

### load

`load()` 必须：

- 当 snapshot 文件不存在时返回 `nil`。
- 当文件存在且 JSON 有效时返回解码后的 `RuntimeSnapshot`。
- 当文件存在但 JSON 损坏或 schema 不匹配时抛出解码错误。
- 不在读取失败时制造默认 snapshot。

## 6. 错误策略

- Missing file 表示 tunnel 尚无可用配置，返回 `nil`。
- Corrupt JSON 表示配置文件损坏，抛出错误，由调用方决定展示或记录。
- Directory creation failure 和 write failure 保留系统错误并抛出。
- 不做 fallback 到默认节点，因为错误默认值可能导致错误代理、错误路由或连接到非预期节点。

## 7. 测试策略

新增或扩展 `IrockStorageTests`，覆盖：

1. `FileRuntimeSnapshotStore` round-trips a `RuntimeSnapshot`.
2. Missing `runtime-snapshot.json` returns `nil`.
3. Saving a second snapshot overwrites the first snapshot.
4. Corrupt JSON throws from `load()`.
5. Saving creates the storage directory when it does not exist.

所有测试使用临时目录，测试结束清理目录，不依赖真实 App Group、Xcode target 或平台 entitlement。

## 8. 成功标准

M3 完成时：

- `IrockStorage` 同时提供 in-memory 和 file-backed snapshot store。
- `RuntimeSnapshot` 可以通过 JSON 文件持久化并恢复。
- 缺失、损坏、覆盖写入和目录创建行为被测试锁定。
- `swift test` 全量通过。
- README 或项目指导文档能准确说明 M0/M1/M2/M3 当前状态。
