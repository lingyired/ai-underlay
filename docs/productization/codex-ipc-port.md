# Codex Desktop IPC 适配移植

完成日期：2026-10-18（Asia/Shanghai）。工作区 `codex/product-settings-polish`。
本子任务只新增 `AIUnderlayKit/Data/Codex/Runtime/` 与对应适配测试；没有提交、
分支、合并、推送、构建或实机操作，xcodegen、全量测试与原生 QA 由父任务执行。

## 上游与归属

- 移植来源：本机 `codex-pacer` 快照，提交
  `b0e763236a00fd725e9a32b002ee3a664c96e003`（2026-10-13），目录
  `native/Sources/PacerCore/`。origin `RyanZhangNTU/codex-pacer`，fork
  `lingyired/codex-pacer`，许可 MIT。
- NOTICE 与 MIT 许可全文由父任务按该快照加入；本子任务未改动许可文件。
- 上游文件哈希用 `shasum -a 256` 取自同一快照，下表为前 16 位。

## 文件清单

| 目标文件（`AIUnderlayKit/Data/Codex/Runtime/`） | 上游文件（sha256 前缀） | 移植差异 |
|---|---|---|
| `NativeDesktopCollector.swift` | `NativeDesktopCollector.swift` `3dab6f4b24d8b78e` | API 不变（`init(home:hosts:localRuntime:batchInterval:onFrame:onClosed:)`、`start()/stop()/setBatchInterval`）；新增 `indexedSeeds`，用本仓 `CodexSessionIndex` 取本机、未归档、非内部、UUID 且 ≤32 条线程做初始订阅，启动时与路由文件变更后经 utility 队列执行，间隔 ≥1s |
| `NativeDesktopSession.swift` | `NativeDesktopSession.swift` `e6b625bd6e62595e` | initialize 的 `clientType` 改为 `aiunderlay-events`；注意力帧前显式 `publishEvents()`，保证生命周期帧先于请求状态 |
| `DesktopWireProjection.swift` | `DesktopWireProjection.swift` `5468534fe01bf127` | `PendingAttentionRequest.Kind` 换成内部 `CodexDesktopRequestKind`；snapshot、投影根值与 metadata 不再保留 `title`/`cwd` |
| `JSONFieldView.swift` | `JSONFieldView.swift` `c48a3772f52037a5` | 原样移植 |
| `DesktopRouteHints.swift` | `DesktopRouteHints.swift` `93b876e5bb295253` | 原样移植 |
| `RuntimeItemKind.swift` | `RuntimeItemKind.swift` `e083ed2f9cd4a024` | 原样移植 |
| `CodexDesktopRequestKind.swift` | 新增 | `enum CodexDesktopRequestKind: String, Sendable { case input, approval }`，会话用 `.rawValue` 序列化，不引入 Pacer 领域类型 |

适配测试移植自同一快照的 `native/Tests/PacerCoreTests/NativeDesktopTests.swift`
（协议与投影部分），运行时领域用例未迁移，改由父任务
`CodexRuntimeStateTests.swift` 覆盖。

## 集成契约

- 主机集合固定为 `["local"]`；批量间隔由父级传参（`CodexRuntimeMonitor`
  当前传 0.25s），适配层保留上游默认 5s 与 0.1–5s clamp。
- 帧类型：`status`、`runtimeBatch`、`attention`、`streamInvalidated`；
  非本机主机才出现的 `discovery` 在本产品不发送。
- 握手前 `status.connected` 恒为 `false`；initialize 成功后才为 `true`，
  并在同一回调内 drain 握手前排队的订阅。`start()` 本身不发布任何帧。
- 有界资源：每主机活跃订阅 ≤32、waiting ≤256、dormant ≤64、单批事件 ≤512、
  单帧 ≤16 MiB；快照按 0.5/1/2/5s 重试，仍无响应则释放订阅。
- 断线语义：owner 断开时先 flush，再发 `streamInvalidated` 并重新订阅；
  已观察到的待处理请求不因断线被当作已解决，直到显式解决或新 turn 建立。
- 顺序语义：attention 变更（包括清空）之前必须先发布该投影产生的
  runtimeBatch，避免消费者在 turn/attached 清空旧请求时丢掉同一帧里的新请求。

## 隐私边界（诚实表述）

- 适配层会在 utility 队列上瞬时解析原始 IPC 帧（结构遍历与有界字段解码）。
  这些字节可能包含会话内容；它们只在内存中存在，投影完成后即丢弃。
- 投影不把提问、回答、命令、工具参数或输出正文解码成 Swift 值：这些字段只做
  结构校验后跳过；判断“是否已有生成文本”时仅检测非空字符串字面量，不物化文本。
- 不打印、不落盘任何 wire 内容：collector 的错误分支静默处理，`onFrame` 只
  送出上述有界 JSON 信封；原始帧不进入日志、缓存或设置。
- 不保留任务名与工作目录（`title`/`cwd` 既不投影也不进 metadata 帧）。模型名、
  来源与父线程 ID 仅用于排除 review／子代理等内部线程。
- 驻留状态只有线程 ID、状态、请求种类（`kind` 的 rawValue）与时间；父级
  `CodexRuntimeState` 同样只保存这些字段。

## 测试

`AIUnderlayKitTests/DataTests/CodexDesktopAdapterTests.swift`（11 项，全部为
合成帧，使用 `/private/tmp` 临时 home，不读真实 `~/.codex`）：

- 握手门控与 `clientType`；握手前排队的 discovery seed 在握手后被 drain。
- revision gap、同批次原子回滚、其他 owner 拒绝；请求只保留 kind+hash；
  异步提问以用户回复为边界；turn 结束释放 item 体。
- owner 断开 → `streamInvalidated`，请求身份跨 owner 重连保持；`targetClientIds`
  过滤；terminal 后 dormant 兴趣仍能看到下一 turn。
- 路由提示 bootstrap 上限 8/32；索引 seed 仅本机、未归档、非内部、≤32。
- 顺序回归 2 项：snapshot 带待处理请求时 `runtimeBatch`（含 `turn/attached`）
  先于 `attention`，并按帧序回放 `CodexRuntimeState` 断言 `pendingQuestion`
  仍保留；队列里未 flush 的增量批次必须先于尾部 attention 变更发布。

父任务最终全量结果：535 项、3 条件跳过、0 失败（2026-10-18 12:36:32），
已包含本文件 11 项用例和最后 2 项顺序回归。Debug 构建成功；本机诊断实际显示
实时连接覆盖 3 个会话，真实配置检查前后 SHA-256 相同。详见
`codex-hook-free-validation.md`。

## 验证边界

- 本子任务未运行 xcodegen／xcodebuild，未构建或运行应用；构建、全量测试与
  实机只读 QA 由父任务执行。
- 未读写真实 `~/.codex`、`~/.claude`；未安装、移除或信任任何 Hook。
- 未新加 socket 级 fixture 测试以保持最小集：stop/restart 与重连由父级 monitor
  的单消费者 AsyncStream 加 generation 校验处理，尚未独立进行 socket fixture
  验收；collector 沿用上游 NSLock
  保护的线程模型，没有无锁的 `@unchecked Sendable`。
- 本机 Codex 桌面端实时连接、真实提问/批准与外观行为属于父任务原生 QA，
  本文不把合成协议测试表述为实机验收。
