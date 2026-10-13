# AIUnderlay 本地未读完成与统一提醒灯带 Implementation Plan

> For agentic workers: 按任务逐项执行，使用 `superpowers:executing-plans`；需要独立任务实施与审阅时使用 `superpowers:subagent-driven-development`。执行方法由用户在实施前选择；本文件不启动实施。步骤使用 checkbox 跟踪。

**Goal:** 从真实可信完成事件建立本地未读账本，以统一灯带持续提示，并通过明确确认形成重启后不复现的闭环。

**Architecture:** 复用 Hook、Session、ThemeStore 和菜单栏面板；新增纯 Completion Inbox 与独立存储服务。Running 与 attention 分别解析，按 Display/Provider 复用 CALayer。原生收据后续独立验证，不阻塞本地首版。

**Tech Stack:** macOS 14+、Swift 6、Foundation、AppKit/Core Animation、SwiftUI、XCTest、XcodeGen；不新增生产依赖。

**Spec:** [`../specs/2026-10-13-unread-completion-attention-ribbon-design.md`](../specs/2026-10-13-unread-completion-attention-ribbon-design.md)，用户已审阅通过，设计提交 `4ed4450`。

**Workspace:** `/Users/lingsmbp/Documents/aiwork/ai-underlay`。代码检查基线 `2dc3b43`；`4ed4450` 仅新增设计文档。本计划是待执行任务，不是已完成报告。

## Global Constraints

- 只接受可信成功终态；工具结束、失败、取消、子 Agent 结束、静默和掉线不创建未读。
- 第一版全部为 appLocal；明确显示“AIUnderlay 本地记录”和“本地确认，不会同步 Codex/Claude 客户端”。
- Error > Waiting > Unread > None；Active 独立，确认未读不解除等待/故障。
- 首次启用不导入历史完成；停机漏收不补采；原生 readState/TPS/远程采集不进入本轮。
- 元数据最小化，不转发/保存正文、标题、工具输出、凭据；单个外部身份字段 ≤512 UTF-8 字节。
- Inbox ≤10,000 条身份记录；新增候选 JSON ≤14 MiB，读取硬上限 16 MiB；不自动删除未读或已确认防重放记录。
- 顶线/底带默认 3/6pt；红/黄/绿默认 `#FF476B` / `#FFD338` / `#36F8A2`；周期 4/5/7秒。其余范围严格按 Spec §8。
- 不改变额度递归、基准线和填充方向；无额度也能展示真实提醒；刘海空区不绘制；Overlay 忽略鼠标。
- 主题只改外观；保留 v1 兼容、不覆盖自定义主题；恢复默认仅修改 active selection。
- 每阶段更新 `docs/implementation-progress.md`；明确区分自动化、fixture 与真实来源/实机验证。

## 执行前检查与阶段顺序

先读 Spec，再检查 Git 状态；并行工作或 dirty baseline 下隔离实施，保留 unrelated changes。可视化 `.superpowers/` 是本次规划临时产物，不进入产品提交；不要用 `git add .` 或 `git add -A`。

依赖顺序：P0 Task 1 → P1 Tasks 2–5 → P2 Tasks 6–10 → P3 Tasks 11–13 → P4 Task 14。P0 没有真实合格来源时，停止产品实施并提交差距报告；不能靠 fixture 宣布数据源成功。

本次不自动安装/信任 Hook、不更改 Provider 配置、不调用原生已读写入、不发布。需要用户安装时沿用现有 App 的预览与确认流程。规划通过不等于安装授权。

常用验证命令：

```bash
xcodegen generate
Scripts/check-domain-purity.sh
Scripts/test.sh -derivedDataPath build/DerivedData
xcodebuild -scheme AIUnderlay -destination 'platform=macOS' -derivedDataPath build/DerivedData -configuration Release build
```

新增 Swift 文件后运行 `xcodegen generate`，XcodeGen 会按现有 source 目录纳入文件。测试延迟使用条件与有界 deadline，不靠固定次数 Task.yield 或任意 sleep。任务的红灯可以是缺类型/方法的编译错误，也可以是行为断言失败；修复后的绿灯必须零失败，不得 skip 关键案例。

## Review Focus

| 容易遗漏的输入 | 必须固定的行为 | 任务 |
| --- | --- | --- |
| 同一 Session 新轮次开始后，上一轮稳定完成事件迟到 | Session 不倒退；上一轮未读仍能入账 | 3、6 |
| 批量确认时同时来了新的完成 | 只确认弹框冻结的 identity 集合 | 5、11 |
| 额度未登录/没有 snapshot，但 Hook 完成可信 | 中性额度底槽上仍有提醒，面板仍有未读 | 6、9、11 |
| 额度刷新、主题修改或切 Space | 保持效果层 identity，不重复首扫 | 8、9、10 |
| 不兼容来源、账本损坏或容量满 | 显示诊断，保留已有提醒，不假称已读或全部正常 | 1、4、5、11 |

## 文件与接口约定

使用现有 XCTest，不迁移测试框架。以下约定由对应任务创建，后续任务按这些名称接线，避免每个模块自行发明状态。

| 文件 | 责任 |
| --- | --- |
| `Agent/CompletionIdentity.swift` | 来源作用域、完成身份、记录、统计单位、能力等级 |
| `Agent/CompletionEvidence.swift` | 合格终态证据、监控基线及来源规则 |
| `Agent/CompletionInbox.swift` | 纯 Inbox 快照转换、去重、受控确认 |
| `Agent/CompletionSourceTracker.swift` | 经 P0 验证的来源协议观察、监控基线和本地轮次 |
| `Agent/CompletionInboxStore.swift` | 明确错误的版本化 JSON 原子读写 |
| `Agent/CompletionInboxService.swift` | actor 串行接收/保存/确认，返回可发布更新 |
| `Overlay/AttentionRibbonLayer.swift` | 固定图层、样式更新和动画调度 |
| `Overlay/AttentionRibbonGeometry.swift` | 可见片段、像素对齐、频谱避让 |
| `Overlay/OverlayLaneLayers.swift` | Display/Provider lane 的稳定 layer 引用 |
| `Overlay/OverlayAnimationLifecycle.swift` | 可见性、锁屏、睡眠、Reduce Motion 策略 |
| `UI/Popover/AttentionListModel.swift` | 列表行、统计单位、范围冻结、打开能力 |
| `UI/Popover/AttentionListView.swift` | 列表与操作反馈 |
| `UI/ThemeRibbonControls.swift` | ThemeTab 的 Ribbon 编辑控件 |

路径省略前缀的文件均位于 `AIUnderlayKit/`。新的领域文件只依赖 Foundation，不导入 UI；用针对这些文件的 import 检查补充现有仅检查 Domain 的脚本。

## P0 — 来源资格

### Task 1: 建立可信终态与身份能力表

**Files:** 创建 `docs/unread-completion-spike.md`、`AIUnderlayKitTests/Fixtures/agent-completion-cases.json`；修改 `docs/agent-capability-report.md`、`docs/implementation-progress.md`。只添加脱敏事件，不保存真实正文。

**Interfaces:** 输出每个来源的 `stableTurn`、`stableEvent`、`orderedSession` 或 `unavailable` 资格，提供成功/失败/取消/工具事件及顺序保证的证据。来源作用域按 Provider + 本地安装/通道 + 可验证账户区分；不能用 Session UUID 代替来源。

- [ ] 1. 记录当前 Git/工程基线，运行 `xcodegen generate` 和完整 `Scripts/test.sh -derivedDataPath build/DerivedData`；将真实结果写进进度文件。已有失败先与基线核对，不隐藏失败。
- [ ] 2. 阅读 Helper、Adapter、HookSetup 与实际已安装 Provider 的公开版本/官方事件说明；记录使用版本及精确来源链接。只检查现有 Hook 可用性，不安装或更改配置。
- [ ] 3. 收集或请求用户触发一个真实成功完成，以及失败/取消对照；仅收集字段名和白名单元数据。确认 `Stop` 是否真终态、`StopFailure` 是否阻塞、Turn/Event ID 是否稳定、事件是否可能重放/乱序。
- [ ] 4. 对没有稳定键的来源，证明“观察到新轮次 → 合格完成”协议足以拒绝旧 Stop 误入新轮次；无法证明就列 unavailable。不能采用接收时间/新 UUID 作去重键。
- [ ] 5. 写能力表：Completion 证据、身份模式、初始基线、断线/停机覆盖、打开能力、验证命令/步骤。至少一个真实来源合格才通过 P0；否则报告确切缺失能力并停止。仅提交本任务文档和脱敏 fixture，提交信息 `docs: verify local completion source capabilities`。

**Exit:** P0 有明确 pass/block 结果。Native read receipt 对全部来源标注“本轮未接入”，不运行原生 API spike。

## P1 — 元数据、Inbox 和持久化

### Task 2: 规范身份与成功终态证据

**Files:** 创建 `AIUnderlayKit/Agent/CompletionIdentity.swift`、`CompletionEvidence.swift`；修改 `AIUnderlayHook/HookEventPayload.swift`、`AIUnderlayKit/Agent/AgentEvent.swift`、`AgentEventAdapter.swift`、`AgentEventReceiver.swift`；测试 `HookEventPayloadTests.swift`、`AgentEventAdapterTests.swift`、`AgentEventReceiverTests.swift`。

**Interfaces:** 定义 Hashable/Codable/Sendable 的 `CompletionIdentity(providerId:sourceId:accountKey:sessionId:completionKey:)`；`CompletionUnit` 为 completionRecord/session。`CompletionReadStatus` 为 unread/acknowledged，来源固定 appLocal。`CompletionRecord` 保存 identity、completedAt、updatedAt、acknowledgedAt、unit。`CompletionSourceCapability` 保存 P0 模式及诊断。`CompletionObservation` 表达已观察轮次、起始时间和是否已完成；`CompletionEvidence.qualify(event:capability:monitoringStartedAt:observation:) -> QualifiedCompletion?` 只接受合格元数据，返回 identity/time/unit，稳定键模式的 observation 可为 nil。AgentEvent 新元数据为 optional，旧初始化调用仍可编译。

- [ ] 1. 写回归：`test_stopFailureDoesNotQualifyAsCompletion`、`test_toolFinishDoesNotQualify`、`test_cancelDoesNotQualify`、`test_oversizedIdentityRejected`、`test_providerScopeIsTrusted`。更新旧 Mirror 测试为明确允许字段集合，仍断言 prompt/response/tool_input 不存在。

  ```swift
  XCTAssertNotEqual(ClaudeCodeAdapter.kind(forHookName: "StopFailure"), .stopped)
  XCTAssertEqual(ClaudeCodeAdapter.kind(forHookName: "PostToolUse"), .toolUseFinished)
  // 512 字节身份通过；513 字节身份拒绝，不能截断后合并。
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/AgentEventAdapterTests -only-testing:AIUnderlayKitTests/HookEventPayloadTests -only-testing:AIUnderlayKitTests/AgentEventReceiverTests`，确认红灯对应新增终态与身份规则。
- [ ] 3. 实现白名单和 P0 规则。来源作用域从受信本地配置/通道解析，不盲信 Hook 原始 source/host/provider 字段；原始 payload 与 adapter.providerId 必须匹配。事件时间只信 P0 验证字段，保留 receivedAt 作诊断，不将它当去重键。Failure/取消不走 `.stopped`，没有阻塞证据不制造 `.error`。
- [ ] 4. 重新生成工程并运行相同过滤测试，零失败；确认旧缺元数据 payload 能用于原有 Running/Waiting，但不会自动获得未读资格。
- [ ] 5. 更新 P1 进度，只 stage 本任务文件，提交 `feat(agent): qualify successful completions with scoped identities`。

### Task 3: 实现独立 Inbox 和监控基线

**Files:** 创建 `AIUnderlayKit/Agent/CompletionInbox.swift`、`CompletionSourceTracker.swift`、`AIUnderlayKitTests/AgentTests/CompletionInboxTests.swift`、`AIUnderlayKitTests/Fixtures/CompletionFixtures.swift`。

**Interfaces:** `CompletionInbox.Snapshot` 为 Codable/Sendable/Equatable，含 schemaVersion=1、monitoringStartedAt、持久 installationID、records、来源观察游标。`CompletionInbox(snapshot:)`；`mutating ingest(_ completion: QualifiedCompletion) -> CompletionIngestResult`；`acknowledging(_ identities: Set<CompletionIdentity>, at: Date) -> Snapshot` 返回候选、不修改原状态；`unreadRecords(providerId:) -> [CompletionRecord]`。结果区分 inserted/duplicate/rejected。`CompletionSourceTracker` 从 snapshot 初始化，`mutating observe(event:capability:now:) -> QualifiedCompletion?` 更新来源观察并调用 Task 2 资格解析；其 observations 随 Inbox snapshot 保存，不凭接收时间发明 Turn 身份。Fixture helper 提供 `CompletionFixtures.identity(provider:source:session:key:)`、`completion(identity:at:)`、`snapshot(records:monitoringStartedAt:)`，参数都有明确默认值，后续测试复用。

- [ ] 1. 写 `test_duplicateCompletionIsOneRecord`、`test_acknowledgedReplayStaysAcknowledged`、`test_nextTurnKeepsPreviousUnread`、`test_lateStableCompletionSurvives`、`test_crossProviderAndSourceIDsDoNotMerge`、`test_preEpochCompletionRejected`。

  ```swift
  XCTAssertEqual(inbox.ingest(completion), .inserted)
  XCTAssertEqual(inbox.ingest(completion), .duplicate)
  XCTAssertEqual(inbox.unreadRecords(providerId: "codex").count, 1)
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/CompletionInboxTests`，确认新增类型/行为尚未实现的红灯。
- [ ] 3. 用 identity 字典实现纯转换；保留已确认记录作 tombstone，不继承 Session 的 20 秒或六小时过期。历史旧 Session 不导入 Inbox。若 P0 允许 orderedSession，增加观察游标和本地 generation，只合并同一 session 的提示单位；旧轮次重复 Stop 不新增，新轮次不吞旧未读；该模式断线后无法可靠恢复时降级 unavailable。
- [ ] 4. 运行上述测试，确认所有时间由显式 Date 注入，稳定身份迟到事件独立于 Session 的时间丢弃规则；单独断言 `acknowledging` 不改变原 snapshot。
- [ ] 5. 更新进度，提交 `feat(agent): add independent local completion inbox`。

### Task 4: 实现可报告错误的版本化原子存储

**Files:** 创建 `AIUnderlayKit/Agent/CompletionInboxStore.swift`、`AIUnderlayKitTests/AgentTests/CompletionInboxStoreTests.swift`。

**Interfaces:** `CompletionInboxPersisting: Sendable` 提供 `load() throws -> CompletionInbox.Snapshot?`、`save(_ snapshot: CompletionInbox.Snapshot) throws`。`CompletionInboxStore(fileURL:)` 实现协议；`CompletionStoreError` 明确区分 corrupt/unsupportedVersion/oversized/writeFailed。目录复用现有 bundle 计算规则，文件为 completion-inbox.json。

- [ ] 1. 写临时目录测试：`test_roundTripRetainsAcknowledgedIdentity`、`test_corruptFileIsNotOverwritten`、`test_futureVersionRejected`、`test_readOver16MiBRejectedBeforeDecode`、`test_atomicWriteFailureLeavesOldSnapshot`。

  ```swift
  try store.save(snapshot)
  XCTAssertEqual(try store.load(), snapshot)
  // 损坏文件 load 抛错后，文件 bytes 必须与原输入一致。
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/CompletionInboxStoreTests`，确认红灯。
- [ ] 3. 保存先 encode/校验，再原子替换；读文件大小先检查，损坏/未来版本不创建空快照覆盖。新建目录与文件使用应用私有权限。注入写入故障，不依赖机器 chmod 是否真正生效。确认错误向上传播，不使用 try? 静默吞错。
- [ ] 4. 相同测试零失败；补“完整临时写失败不会出现半份有效 JSON”和新记录超过 14 MiB 的预检查。已确认更新保留 2 MiB 空间，不因新增容量门槛阻止已有记录确认。
- [ ] 5. 更新进度，提交 `feat(agent): persist completion inbox atomically with explicit failures`。

### Task 5: 串行事务、确认和容量诊断

**Files:** 创建 `AIUnderlayKit/Agent/CompletionInboxService.swift`、`AIUnderlayKitTests/AgentTests/CompletionInboxServiceTests.swift`。

**Interfaces:** `actor CompletionInboxService` 持有 Inbox/tracker/store；`restore(now: Date) -> InboxUpdate`、`observe(event:capability:now:) -> InboxUpdate`、`ingest(_ completion: QualifiedCompletion) -> InboxUpdate`、`acknowledge(identities: Set<CompletionIdentity>, at: Date) -> InboxUpdate`、`retryPendingSave() -> InboxUpdate`。外部调用 await actor 方法；内部 store 操作为串行同步 I/O，不跨 await 后用旧 snapshot 覆盖新状态。生产事件走 observe，先更新 tracker 再 ingest；直接 ingest 是已合格输入的接缝。`InboxUpdate` 含 records、计算属性 unreadCount、diagnostic、change revision，以及 volatileIdentities；保存失败临时记录只在进程内保留。

- [ ] 1. 写 `test_ackWriteFailureKeepsUnread`、`test_frozenBatchDoesNotAcknowledgeNewCompletion`、`test_serialCommandsDoNotLoseUpdates`、`test_capacityDoesNotEvictUnreadOrTombstones`、`test_corruptRestoreDisablesMutations`。

  ```swift
  XCTAssertEqual(afterFailedAck.unreadCount, before.unreadCount)
  XCTAssertNotNil(afterFailedAck.diagnostic)
  // 冻结 {A}，其后收到 B；确认 {A} 后仍存在 unread B。
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/CompletionInboxServiceTests`，确认红灯。
- [ ] 3. 先保存候选再发布成功确认；失败返回“确认未保存，请重试”，不清提醒。新完成保存失败保留临时提示“未保存，重启可能丢失”；重试操作提交最新一致快照。观察到新轮次时也保存 tracker 的必要变化，不因没有新完成就丢掉观察基线；不保存无变化的每次工具事件。完成记录与观察会话分别最多 10,000 个，序列化共用 14 MiB 新增门槛；容量满拒绝新增但允许已有确认，volatile 也受同上限约束。错误只发布状态变化，避免无限内存/重复日志。损坏 restore 保留原文件，暂停持久操作。
- [ ] 4. 相同测试零失败；注入源重连、确认与 ingest 交错，证明确认 tombstone 保存后重启不复活。无需新增自动清理或 archive UI。
- [ ] 5. 更新进度，提交 `feat(agent): serialize local acknowledgements and expose inbox diagnostics`。

## P2 — 信号、主题和稳定图层

### Task 6: 合并信号并与 Coordinator 接线

**Files:** 修改 `AgentSessionReducer.swift`、`AgentStateStore.swift`、`Application/AppCoordinator.swift`、`Overlay/MenuBarOverlayController.swift` 中 GaugePresentation；新增 `AIUnderlayKitTests/AgentTests/ProviderAttentionTests.swift`、`AIUnderlayKitTests/ApplicationTests/CompletionCoordinatorTests.swift`；修改 Session/StateStore 测试。

**Interfaces:** 新 `AttentionKind` 为 none/unreadCompletion/waitingForUser/confirmedError；`AgentSignals.unreadCount` 和 `effectiveAttention`。Session 字典用 `AgentSessionKey(providerId:sourceId:accountKey:sessionId:)`，Snapshot 接受旧版 legacy-local 键迁移。Coordinator 发布 `attentionRevision`，并提供 `attentionRecords(providerId:)`、`acknowledgeCompletions(identities:) async -> InboxUpdate`、`retryInboxSave() async -> InboxUpdate`。

- [ ] 1. 写独立优先级测试，以及 `test_missingQuotaStillProducesAttentionPresentation`、`test_hookCompletionUpdatesOpenPanelRevision`、`test_polledIdleNeverCreatesUnread`、`test_lateCompletionDoesNotRegressSession`。Coordinator 注入 store/service/clock，禁止测试读写用户真实 Application Support。

  ```swift
  let signals = AgentSignals(activeCount: 2, waitingApprovalCount: 1, errorCount: 1, unreadCount: 1)
  XCTAssertTrue(signals.hasActive)
  XCTAssertEqual(signals.effectiveAttention, .confirmedError)
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/ProviderAttentionTests -only-testing:AIUnderlayKitTests/CompletionCoordinatorTests -only-testing:AIUnderlayKitTests/AgentSessionReducerTests -only-testing:AIUnderlayKitTests/AgentStateStoreTests`，确认红灯。
- [ ] 3. Receiver 事件分别送 Session 和 service.observe，不因 Session 拒绝旧事件而漏 Inbox；来源 capability 由 P0 验证配置提供。恢复 Inbox 后发布 revision；合并 Hook 信号时始终附加 Inbox，即使 Hook Session 为空/过期也保留未读。额度 snapshot 缺失时生成 windows=[] 的 presentation，使用正常 Provider lane；不从未读创造 quota。Session 键迁移不导入旧完成。
- [ ] 4. 同过滤测试零失败。补 Error→Waiting→Unread 回退、Provider 独立、来源掉线不清未读、visual effects off 不清账本。更新 agentSignature 纳入 unread 与 attention，不拿 unknown 当零或红色故障。
- [ ] 5. 更新进度，提交 `feat(agent): aggregate unread attention independently of running and quota`。

### Task 7: Theme v2 与解析边界

**Files:** 修改 `Domain/ThemeDocument.swift`、`Overlay/ThemeResolver.swift`、`Application/ThemePresets.swift`、`docs/theme/theme.schema.json`；测试 `ThemeDocumentTests.swift`、`ThemeResolverTests.swift`、`ThemeStoreTests.swift`。

**Interfaces:** ThemeDocument 新 `AttentionRibbon` 公共配置与 StateStyle ribbonColor/topRailColor/sweepColor/sweepIntervalSeconds；`ThemeResolver.ribbon(theme:kind:) -> AttentionRibbonStyle`。Style 保存全部已解析颜色、几何/动画参数，不携带 Agent 身份；默认值与范围按 Spec §8。Loader 同时接受 v1/v2，返回可渲染的规范化 v2，不改源文件。

- [ ] 1. 写 `test_v1PreservesProviderColors`、`test_zeroLegacyBorderKeepsTopRailHidden`、`test_missingUnreadUsesDefaults`、`test_nullSpectrumInherits`、`test_unknownFieldRejected`、`test_sweepIntervalCannotBeShorterThanDuration`。

  ```swift
  XCTAssertEqual(ThemeDocument.currentSchemaVersion, 2)
  XCTAssertEqual(style.topRailHeight, 3)
  XCTAssertEqual(style.bottomRibbonHeight, 6)
  XCTAssertEqual(style.sweepIntervalSeconds, 7) // unread 默认
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/ThemeDocumentTests -only-testing:AIUnderlayKitTests/ThemeResolverTests -only-testing:AIUnderlayKitTests/ThemeStoreTests`，确认红灯。
- [ ] 3. 实现 Token、版本兼容与严格未知字段校验（包括嵌套对象）；允许既有 providers/states 动态键和已定义字段，不把 unknown field 与未知 Provider 混淆。NaN/Infinity 拒绝。Schema 用版本分支表达 v1/v2；spectrumColor 的 null/省略语义一致。已有用户显式 Running 色选择继续有效。
- [ ] 4. 同过滤测试零失败。加入当前主题变坏仍保持上一份、原子文件替换后热重载；v1/2 fixtures 与 JSON Schema 字段逐项比对，记录哪些约束由运行时跨字段校验执行。普通 Running 及 quota palette 旧测试继续通过。
- [ ] 5. 更新进度，提交 `feat(theme): add attention ribbon tokens with v1 compatibility`。

### Task 8: 统一 Ribbon 图层和纯几何

**Files:** 创建 `Overlay/AttentionRibbonGeometry.swift`、`AttentionRibbonLayer.swift`；修改 `Overlay/AgentEffectLayer.swift`；新增 `AIUnderlayKitTests/OverlayTests/AttentionRibbonGeometryTests.swift`、`AttentionRibbonLayerTests.swift`，更新 `AgentEffectTests.swift`。

**Interfaces:** `AttentionRibbonGeometry.make(visibleRects:menuBarHeight:scale:style:) -> AttentionRibbonLayout`，含可见片段的 top/bottom/spectrum/glow 区域；`@MainActor final class AttentionRibbonLayer: CALayer` 提供 `update(kind:style:layout:motionAllowed:mediaTime:)`。Layer 保留 last kind/sweep phase；测试通过 animation key、对象 identity 与几何观察行为，不绑定无意义子层数量。

- [ ] 1. 写 `test_sameStructureForThreeKinds`、`test_sameKindDoesNotRestartSweep`、`test_priorityChangeStartsOneSweep`、`test_notchHasNoRailOrGlow`、`test_spectrumStartsAboveRibbon`、`test_smallHeightScalesRails`。

  ```swift
  XCTAssertEqual(layout.bottomRibbonHeight, 6)
  XCTAssertGreaterThanOrEqual(layout.spectrumRect.minY, layout.bottomRibbonRect.maxY)
  // 坐标采用 lane-local、向上为正；几何任务统一约定，再映射 CALayer。
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/AttentionRibbonGeometryTests -only-testing:AIUnderlayKitTests/AttentionRibbonLayerTests -only-testing:AIUnderlayKitTests/AgentEffectTests`，确认红灯。
- [ ] 3. 三态复用顶线/底带/glow/sweep；轻蒙层静态，不保留旧 Waiting/Error 呼吸警示和第二套边框。Running 既有选项保留，频谱避让底带。顶线+底带总高超过菜单栏一半时同比缩放并做像素对齐。刘海拆可见片段，glow/sweep 同 mask。首扫/重复/主题更新语义按 Spec §7；用 CA animation 表达完整周期，禁止逐帧 CPU 回调。
- [ ] 4. 同过滤测试零失败。扩展 1x/2x、双方向、Single 刘海、Reduce Motion、零顶部兼容主题；现代实时路径不再执行 legacy completed 单次 sweep。更新过时的边框/呼吸内部形状断言，保留旧四种 Running 行为回归。
- [ ] 5. 更新进度，提交 `feat(overlay): unify attention rails and bottom ribbon sweeps`。

### Task 9: 稳定 Lane 层与无额度提醒

**Files:** 创建 `Overlay/OverlayLaneLayers.swift`；修改 `MenuBarOverlayController.swift`、`GaugeLayerRenderer.swift`（仅需要的 quota 更新接缝）；新增 `AIUnderlayKitTests/OverlayTests/OverlayLaneLayersTests.swift`。

**Interfaces:** `@MainActor final class OverlayLaneLayers` 持有 quotaRoot/runningRoot/ribbonLayer；`apply(presentation:geometry:visibleRects:motionAllowed:mediaTime:)` 原位更新。Controller 按 DisplayID/ProviderID 管理实例，换屏只释放对应实例；preview 与 live 共用相同 path。

- [ ] 1. 写 `test_quotaRefreshRetainsRibbonIdentity`、`test_themeRefreshDoesNotFirstSweep`、`test_missingQuotaKeepsRealAttention`、`test_providerLanesDoNotShareLayers`。

  ```swift
  XCTAssertTrue(beforeRibbon === afterRibbon)
  XCTAssertEqual(beforeSweepBeginTime, afterSweepBeginTime)
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/OverlayLaneLayersTests -only-testing:AIUnderlayKitTests/GaugeLayerRendererTests`，确认红灯。
- [ ] 3. 移除 render 中无条件删除所有 root.sublayers 的行为，固定 lane parent；只更新变化的 quota/geometry/style。必要时允许替换 quota 子树，不能替换效果对象。None 清动画并隐藏 Ribbon；数量变化只更新诊断，不重新首扫。窗体和正常 quota 长度/基准线不变。
- [ ] 4. 同过滤测试零失败；加入连续 100 次 apply 后层数稳定、额度改变不会改变 sweep beginTime、无额度只显示空窗口/中性底槽与真实 attention。
- [ ] 5. 更新进度，提交 `fix(overlay): retain attention layers across presentation updates`。

### Task 10: 可见性与动画生命周期

**Files:** 创建 `Overlay/OverlayAnimationLifecycle.swift`；修改 `MenuBarOverlayController.swift`、`MenuBarBandWindow.swift`（仅需要的可见性接缝）；新增 `AIUnderlayKitTests/OverlayTests/OverlayAnimationLifecycleTests.swift`。

**Interfaces:** `OverlayAnimationEnvironment` 记录 display/overlay 可见、locked、sleeping、系统/应用 Reduce Motion；`OverlayAnimationLifecycle.motionAllowed(environment:) -> Bool` 纯决策；controller 持有每屏状态，调用 Task 9 的 motionAllowed，不伪造 None→kind 转换。

- [ ] 1. 写 `test_lockedAndSleepingDisableMotion`、`test_hiddenOverlayDisablesMotion`、`test_systemOrAppReduceMotionDisablesMotion`、`test_resumeDoesNotFirstSweep`、`test_idleHasNoEffectAnimations`。

  ```swift
  XCTAssertFalse(OverlayAnimationLifecycle.motionAllowed(environment: lockedEnvironment))
  XCTAssertEqual(ribbon.kind, .unreadCompletion) // 暂停不清真实状态
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/OverlayAnimationLifecycleTests -only-testing:AIUnderlayKitTests/AttentionRibbonLayerTests`，确认红灯。
- [ ] 3. 正确注册 NSWorkspace 自身通知中心和 AppKit/system accessibility 偏好变化；存 observer token 并释放。暂停/恢复使用 CA 时间状态，不新增逐帧 Timer；Space/锁屏/屏幕移除更新实际可见性，不能仅依赖 isVisible。隐藏不清账本，不触发首扫。
- [ ] 4. 同过滤测试零失败；验证切 Space 不增长 observer/layer、睡眠唤醒不重新创建 Overlay Window、所有 Idle 效果 animationKeys 为空。若自动隐藏/全屏环境不可可靠判断，列限制并禁止宣称该场景实测通过。
- [ ] 5. 更新进度，提交 `fix(overlay): pause attention and running motion when not visible`。

## P3 — 用户确认与可编辑主题

### Task 11: Provider 待关注模型与冻结批量范围

**Files:** 创建 `UI/Popover/AttentionListModel.swift`、`AIUnderlayKitTests/UITests/AttentionListModelTests.swift`；修改 `UI/Popover/DashboardModel.swift`。

**Interfaces:** `AttentionRow` 含 provider/session 短标识/time/unit/kind/source/persistence/可用打开目标；`AttentionListModel.sections(providers:signals:records:diagnostics:)`；`acknowledgementScope(providerId:records:) -> Set<CompletionIdentity>`。诊断不是 Error 行；会话级提醒只计一次。

- [ ] 1. 写 `test_errorWaitingUnreadOrdering`、`test_localSourceCopy`、`test_unitsAreNotMixedAsTurns`、`test_frozenScopeIsProviderSpecific`、`test_noQuotaStillHasAttentionSection`、`test_unavailableIsDiagnosticNotAgentError`。

  ```swift
  XCTAssertEqual(row.sourceLabel, "AIUnderlay 本地记录")
  XCTAssertEqual(section.localConfirmationNote, "本地确认，不会同步 Codex/Claude 客户端")
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/AttentionListModelTests -only-testing:AIUnderlayKitTests/DashboardModelTests`，确认红灯。
- [ ] 3. 生成真实记录行，不读取正文获取标题。默认按 attention 优先级，再按完成时间新到旧；短身份只是展示，确认永远传完整 identity。打开目标来自 P0 验证能力，没有能力则无按钮。
- [ ] 4. 同过滤测试零失败；加入容量满/存储失败/来源掉线诊断，确认 rows 保留已知未读，并标清覆盖/新记录缺失限制。
- [ ] 5. 更新进度，提交 `feat(ui): model provider attention lists and explicit acknowledgement scopes`。

### Task 12: 面板中的单项/批量确认与即时更新

**Files:** 创建 `UI/Popover/AttentionListView.swift`；修改 `DashboardView.swift`、`MenuBarPanel.swift`（如需命令接入）、`Application/AppCoordinator.swift`；新增 `AIUnderlayKitTests/UITests/AttentionActionsTests.swift`。

**Interfaces:** `AttentionActions` 接收 `acknowledge: @MainActor (Set<CompletionIdentity>) async -> InboxUpdate`、`retrySave` 和可选 `openSession` 命令；打开服务返回成功/失败但不能调用 acknowledge。批量范围仅在用户确认时发送 Task 11 的冻结集合。

- [ ] 1. 用 fake service 写 `test_openSuccessDoesNotAcknowledge`、`test_openFailureDoesNotAcknowledge`、`test_ackFailureKeepsRow`、`test_batchCancelDoesNothing`、`test_newCompletionDuringConfirmationRemainsUnread`。

  ```swift
  XCTAssertEqual(fake.acknowledgeCalls.count, 0) // 仅打开会话后
  XCTAssertTrue(rows.contains { $0.identity == newlyArrivedIdentity })
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/AttentionActionsTests -only-testing:AIUnderlayKitTests/CompletionCoordinatorTests`，确认红灯。
- [ ] 3. 现有 320pt 面板内增加关注区域，不改变 Overlay hit target；共用滚动区，长列表不撑高窗口。单项确认按钮、Provider 批量确认框、失败重试和必要覆盖说明。面板订阅 attentionRevision，事件到达和保存成功即时刷新；确认期间禁止重复提交同一操作。
- [ ] 4. 同过滤测试零失败；实际打开面板验证来源标签、失败反馈、无额度关注项和按 Provider 批量范围。只为 P0 验证成功的来源增加打开实现；未验证时隐藏并说明，不猜深链。
- [ ] 5. 更新进度，提交 `feat(ui): add explicit local completion acknowledgement to the dashboard`。

### Task 13: 主题控件、组合预览与文档

**Files:** 创建 `UI/ThemeRibbonControls.swift`、`docs/theme/examples/attention-vivid.json`、`attention-muted.json`、`attention-soft-glow.json`；修改 `ThemeTab.swift`、`Application/ThemeStore.swift`、`Data/Fixtures/FixtureSnapshots.swift`、`Application/AppCoordinator.swift`、`docs/theme/README.md`；测试 ThemeTab/ThemeStore/FixtureSnapshots。

**Interfaces:** `ThemeRibbonControls(document:onValidatedSave:)` 编辑 v2 draft；`ThemeStore.saveValidatedTheme(_:to:) throws` 使用 Task 7 校验并原子写入用户明确选择位置。恢复默认调用现有 setActive(id:nil) 与 SettingsStore 保存 selection，不删除主题文件。fixture 只改预览输入，不能写 live Inbox。

- [ ] 1. 写 `test_restoreDefaultDoesNotDeleteCustomTheme`、`test_invalidDraftDoesNotReplaceActiveTheme`、`test_fixturePreviewDoesNotPersistCompletions`、`test_fixtureIncludesIndependentProviders`。

  ```swift
  XCTAssertTrue(FileManager.default.fileExists(atPath: customThemeURL.path))
  XCTAssertEqual(beforeLiveInbox, afterPreviewLiveInbox)
  ```

- [ ] 2. 运行 `Scripts/test.sh -derivedDataPath build/DerivedData -only-testing:AIUnderlayKitTests/ThemeTabTests -only-testing:AIUnderlayKitTests/ThemeStoreTests -only-testing:AIUnderlayKitTests/FixtureSnapshotsTests`，确认红灯。
- [ ] 3. 添加 Spec §8 全部颜色/高度/glow/流光开关、方向、宽度、时长、周期、蒙层与频谱覆盖控件；保留 JSON 编辑和错误反馈。自定义修改先做 draft 校验；内置主题另存副本，v1 修改保存为 v2 用户副本，不自动重写原文件。
- [ ] 4. 同过滤测试零失败；新增 None、Unread、Waiting、Error、三者重叠、Active 组合、双 Provider 独立 fixtures，设置预览驱动真实 Renderer。检查三份 JSON 在 Loader 中通过并热重载；README 给出 Token、范围、v1 迁移、原子编辑和恢复默认说明。
- [ ] 5. 更新进度，提交 `feat(theme): expose ribbon controls and shared attention previews`。

## P4 — 验收与交付

### Task 14: 真实来源闭环、回归和性能证据

**Files:** 创建 `AIUnderlayKitTests/AgentTests/CompletionEndToEndTests.swift`、`docs/unread-completion-acceptance.md`、`docs/preview/unread-completion/` 中真实截图/录屏；修改 `README.md`、`docs/acceptance.md`、`docs/privacy-and-permissions.md`、`docs/implementation-progress.md`、旧动态特效设计中的当前行为说明。

**Interfaces:** 端到端测试用临时 store，真实 parse → evidence → Inbox → signals → presentation → acknowledgement → restore；测试 socket/fixtures 与真实来源验收分别记录，不混称真机支持。

- [ ] 1. 写 `test_completeAcknowledgeRestartDoesNotResurrect`、`test_errorWaitingUnreadFallbackPreservesRecords`、`test_completionWithNoQuotaIsVisible`。证明已确认 replay 不复活，另外 Provider 的未读未变。

  ```swift
  XCTAssertEqual(restoredUnreadCount, 0) // 合格完成已确认并保存后
  XCTAssertEqual(otherProviderUnreadCount, 1)
  ```

- [ ] 2. 运行完整测试、Domain purity 与 Release build（使用执行前检查中的精确命令）。只记录本次实际结果；零失败、成功 build 才通过自动化门槛。
- [ ] 3. 在 P0 合格真实来源触发新完成，看到绿色、确认后消失、重启不复现；另做失败/取消对照。若必须新装 Hook，交用户通过现有安装预览确认，未获授权不要安装；缺这一步则真实闭环仍未完成。
- [ ] 4. 按下面验收表记录截图与性能。没有设备或无法触发的项写未测与限制。真实闭环失败先定位来源/身份/保存/刷新节点，不以离线预览替代。
- [ ] 5. 更新用户文档及旧冲突说明：Completed 不再只短扫、Waiting/Error 统一 Ribbon、原生未读未接入、停机/容量限制。执行最终 `git diff --check`，按实际文件清单显式 stage，提交 `test: verify local unread completion attention end to end`；汇报分支、提交、测试和未测项，不自动 tag/release/推送/合并。

### 实机验收表

| 项目 | 通过条件与证据 |
| --- | --- |
| 真来源 | 至少一个支持版本的成功/失败对照；未读确认重启不复现；版本和脱敏身份路径可追溯 |
| 三态 | 红/黄/绿都为顶线+底带+内部流光；Error→Waiting→Unread→None 正确回退 |
| 独立性 | Active+Unread 频谱不停；Active+Error/Waiting 组合；两 Provider 独立；无额度有提醒 |
| 几何 | 真菜单栏高度、不同 scale、Single/双侧、刘海空区无漏线；外接屏缺设备则未测 |
| 生命周期 | 锁屏/睡眠/隐藏无活动动画；唤醒/Space 不首扫；系统/应用 Reduce Motion 静态灯带 |
| 交互/可读 | 不拦菜单栏点击；原生文字和图标可读；确认只清所选范围；打开不清未读 |
| 性能 | 同条件改动前后各 60 秒 Idle/静态/周期流光/Active+提醒；CPU/内存实值、动画键与层数稳定 |

### 交付必须列明

1. Source 能力表与 P0 证据，包括真实支持范围与 unavailable 来源。
2. 自动化命令及通过/失败数量、Release artifact 路径；不得复用旧测试数量。
3. 三态/组合/跨 Provider 截图或录屏与实机未测项。
4. 主题 Schema、三份样例、本地确认语义、停机与容量限制。
5. Git 分支和提交、产品代码变更范围、后续原生 readState spike。

## 计划自审

| Spec 内容 | 覆盖 |
| --- | --- |
| 可信终态、身份与基线、实际来源门槛 | Tasks 1–3 |
| 独立 Inbox、持久化、确认失败、容量 | Tasks 3–5 |
| Session 隔离/迁移、无额度提醒、即时 revision | Task 6 |
| 优先级、图层复用、首扫和刘海/频谱避让 | Tasks 6、8、9 |
| 主题 v2/v1、未知字段、控件、JSON、真实预览 | Tasks 7、13 |
| 可见性、系统/应用 Reduce Motion、Idle | Task 10 |
| 面板、范围冻结、打开不确认、诊断 | Tasks 11、12 |
| 真实闭环、测试、性能、旧文档修订 | Task 14 |

接口由前置任务定义，后续任务引用；未验证来源有显式 gate，不用待填占位或假定能力。任务步骤是未来实施动作，规划阶段未执行产品测试。原生 readState 不在当前任务中。
