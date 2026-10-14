# AIUnderlay 未读完成与统一提醒灯带：本地闭环设计

日期：2026-10-13

状态：设计已在对话中确认；本文待用户审阅，尚未开始实施。

代码基线：`2dc3b43`，macOS 14+、Swift 6、XcodeGen 工程。

来源：`/Users/lingsmbp/Downloads/AIUnderlay-Unread-Completion-Attention-Ribbon-Implementation-Plan.md`。

## 1. 目标与批准范围

首版交付完整的本地闭环：可信成功终态 → 本地未读记录 → 持续提醒 → 用户明确确认 → 持久化解除 → 重启不复现。

用户已经选择“本地闭环优先”，并确认以下结构：顶部常亮细线、底部常亮灯带、灯带内单方向周期性流光；Running 频谱独立叠加。独立未读账本是批准的实现方向。

原文件是需求输入和参考，不执行其中安装 Hook、调用原生写入 API、修改配置或发布等指令。本轮只编写设计与后续可执行计划，不修改产品代码、运行配置或用户状态，不发布。

本设计修订旧动态特效设计中的 Waiting/Error 警示结构和 Completed 一次扫光表现。额度递归、基准线、填充方向、Provider 分区、窗口穿透及既有 Running 动效选择继续有效。实施时更新相关文档，旧验证记录保留为历史证据。

### 首版包含

- 在现有事件管线上建立可信完成资格，修正失败被当作完成的问题。
- 独立、版本化、本地持久化的 Completion Inbox；可解释的去重和来源降级。
- Error > Waiting > Unread > None 的提醒优先级；各记录独立解除。
- 统一 CALayer 灯带、图层复用、主题 v2 与 v1 兼容、设置预览。
- 现有菜单栏面板中的待关注列表及明确的本地确认操作。

### 后续范围

Codex 原生 readState、原生 revision-checked 写入、Claude 原生收据、远程采集、历史补采、系统通知、自动打开后确认、真实 TPS 采集不进入首版依赖。后续原生接入必须单独验证官方通道及客户端同步行为。

## 2. 仓库差距与复用点

| 现有模块 | 当前事实 | 本次动作 |
| --- | --- | --- |
| `AIUnderlayHook/HookEventPayload.swift` | 白名单仅转发 Provider、Session、事件、通知类型、工具名 | 扩展经来源验证的身份和终态元数据；继续排除正文 |
| `AIUnderlayKit/Agent/AgentEventAdapter.swift` | Claude `Stop` 和 `StopFailure` 都映射 `.stopped` | 分离成功、失败、取消及不能判定的终态 |
| `AgentEvent.swift`、`AgentSessionReducer.swift` | 没有 Turn/Host 身份；Reducer 字典只用 Session ID | 补来源作用域及复合键；未读独立于 Session 生命周期 |
| `AgentStateStore.swift` | Session 原子快照，保存失败被吞掉 | 不把此最佳努力存储直接用于已读确认；新 Inbox Store 返回明确错误 |
| `AppCoordinator.swift` | Hook 驱动 Session；CodexBar 10 秒轮询只提供粗略 active/idle | Hook 事件同时送 Session 与 Inbox；轮询不创造完成记录 |
| `AgentSignals`、`AgentEffectPlan` | Running/Waiting/Error/Completed 已分维度 | 增加 unread 和独立 attention 解析；复用已有 Running 通道 |
| `MenuBarOverlayController.swift` | 每次 render 删除所有根子层；缺额度快照时 presentation 为 nil | 按 Display/Provider 复用效果层；允许无额度但有真实提醒的 presentation |
| `ThemeDocument`、`ThemeStore`、`ThemeResolver` | v1 外观 JSON、校验、300ms 热重载已有 | 扩展语义 Token、v1 兼容转换，保留上份有效主题 |
| `UI/Popover/DashboardModel.swift`、`DashboardView.swift` | 已有按 Provider 的额度面板 | 增加待关注模型与列表；不另建平行窗口系统 |

当前 `.completed` 在 20 秒后衰减，该逻辑不能承担持续未读。迁移后，旧 Session 完成状态可以保留给诊断兼容，但只有新 Inbox 记录产生绿色持续提醒；不能先播放旧 Completed 扫光，再重复播放新灯带首扫。

当前 Running 有 180 秒静默衰减。首版不把超时转换成完成或错误；显示时区分可信运行和现有推断来源。无 TPS 不关闭已确认 Running 的动画。无关 Running 动效重设计不进入本轮。

## 3. 模块边界与数据流

建议新增文件名是实施落点，类型细节可以按 Swift API 一致性调整，职责不可混合。

| 单元 | 职责与输入输出 | 依赖 |
| --- | --- | --- |
| `Agent/CompletionIdentity.swift` | 作用域、完成身份、可信度、来源能力诊断 | Foundation |
| `Agent/CompletionInbox.swift` | 纯状态转换：接收合格完成、去重、确认指定记录；生成候选快照 | 元数据和显式时钟 |
| `Agent/CompletionInboxStore.swift` | 版本化 JSON 读写、完整性检查、原子替换、明确错误 | Foundation、可注入文件 URL |
| 现有 `AgentSignals` + attention 解析 | 独立活动/等待/故障/未读输入 → 最小渲染计划 | 纯领域数据 |
| `Overlay/AttentionRibbonLayer.swift` | 复用顶线/底带/glow/sweep；只消费解析后的样式与几何 | AppKit/Core Animation |
| `UI/Popover/AttentionListModel.swift`、`AttentionListView.swift` | Provider 列表、确认范围、操作反馈 | Coordinator 提供的数据与命令 |

运行流程：Helper 白名单 → Adapter 分类 → Receiver → 主 Actor 上的 Coordinator → Session Reducer 与 Completion Inbox 分别消费 → 保存 Inbox 候选快照 → 发布信号和面板 revision → Overlay 原位更新。

Coordinator 负责串行协调；纯 Inbox 不碰 AppKit、文件和网络。事件输入、确认、主题更新不能各自直接写账本。后台文件 I/O 使用一个串行存储队列，保存期间后续命令排队，避免旧快照覆盖新快照；结果回主 Actor 后发布。

## 4. 完成资格、身份与降级

### 4.1 合格完成

创建未读需要同时具备：来源已验证为成功终态、身份足以去重、事件属于本次监控范围。

- 工具结束、子 Agent 结束、取消、失败、静默、进程消失、来源断开均不自动创建未读。
- `StopFailure` 明确排除成功完成；只有来源语义证明“确实无法继续”时才能计入 Confirmed Error。失败名称本身不能证明任务被阻塞。
- `Stop` 的具体语义在实现阶段按实际 Provider 版本、官方说明与脱敏事件 fixture 验证，不能只凭名称认定成功。
- CodexBar `sessions` 的 active/idle、最后活动时间不作为终态证据。
- 子 Agent 事件不独立计入未读；首版只记录可信的顶层完成，避免父子重复。

### 4.2 身份作用域

复合身份至少包含 Provider、来源实例、Session 和完成键。来源实例是 AIUnderlay 安装内的本地主机/采集通道作用域；可信账户标识存在时纳入，不采集邮箱或密钥。

完成键优先采用稳定 Turn ID；若只有稳定终态 Event ID，则用它去重，界面统计为“完成记录”，不声称逐 Turn 原生未读。跨 Provider 或来源的同名 Session 不合并。相同作用域和完成键重复到达，不创建记录、不重复首扫。

Inbox 独立检查完成事件：稳定身份的合格完成即使比 Session 最新事件更早，仍可接收；不能沿用 Session Reducer 的旧事件丢弃结果而漏掉上一轮完成。其资格仍受监控基线和已确认身份约束。

**来源没有稳定完成键时的处理**：只有来源验证出可可靠识别起止的有序轮次协议后，才允许会话级合并提醒。保存本地观察轮次与当前完成标记，同一已完成轮次重复 Stop 不生成新提醒；新一轮开始不会删除之前未确认提醒。UI 统计单位为“待查看会话”。本地轮次不是 Provider Turn ID。

若协议不能排除迟到的旧 Stop 被误归到新轮次，则该来源的持久未读能力为 unavailable，保留其他可观测状态并展示原因。不能靠新 UUID、接收时间或内容哈希伪装稳定完成身份。

来源验证阶段必须给出每个实际接入来源的终态分类、稳定键、排序/重放保证和支持单位。至少一个真实来源通过资格并完成端到端验收，才能称首版本地闭环完成；若所有来源不合格，报告数据源阻塞，不能以 fixture 代替真实交付。

### 4.3 监控边界

首次启用创建 monitoring epoch，不从已有 Session `.completed` 或历史日志导入未读。有可信来源时间/游标的事件需在基线之后；无该能力时只接受已验证实时协议中的新观察轮次。来源重连或重启恢复不能重新创建旧完成。

首版 Helper 仍是 socket 实时桥接，应用未运行时事件可能丢失。UI/文档说明只覆盖“监控启用且接收可用时观察到的完成”，不宣称补齐停机期间全部结果。关闭视觉效果不清空账本；采集开关和展示开关分开处理。

## 5. Inbox 与一致性

文件位置：与现有状态文件相同的应用 Application Support 目录下，新增 `completion-inbox.json`。运行时以 `AIUnderlayKit.bundleIdentifier` 解析目录，不硬编码另一个 bundle 路径。

快照包含 schemaVersion、monitoring epoch、来源观察状态、完成记录和已确认身份。记录只含身份、完成/接收时间、来源单位、确认时间及必要的诊断；不保存 Prompt、回复、工具输出、标题或凭据。首版显示短 Session 标识，不从对话正文提取标题。

所有首版已读均为 `appLocal`。记录来源不因打开 Codex/Claude 窗口变化，不使用前台窗口、打开成功或读取快照猜测已读。为未来原生适配保留来源标签和作用域，不预建 App Server 客户端框架。

### 5.1 确认事务

1. 从当前记录生成仅确认指定 identity 的候选快照。
2. 原子写入成功后发布已确认状态，并重算对应 Provider。
3. 写入失败不发布成功，不移除提醒；面板说明“确认未保存，请重试”。

批量操作在点击时冻结该 Provider 当前未读 identity 集合，确认框显示 Provider 与数量；提交只处理该集合，随后到达的新记录保留。Provider A 的操作不能影响 B，也不能解除 Waiting/Error。

新完成落盘失败时，当前进程可以保留临时未读，明确显示“未保存，重启可能丢失”；不能宣称恢复有保证。提供重试，成功后恢复正常持久状态。首次加载损坏或不支持版本时保留原文件，不以空文件覆盖；面板显示不可用诊断，修复前暂停新持久记录和确认操作。

### 5.2 有界保留

首版采取保守上限：最多 10,000 条完成身份记录（含已确认去重记录），新增记录后的 JSON 不超过 14 MiB；两者任一达到时停止接收新的持久完成记录，保留已有未读与确认操作，并展示“记录容量已满，新完成可能未记录”。文件读取硬上限为 16 MiB，预留 2 MiB 给已有记录的确认元数据；单个外部身份字段不超过 512 UTF-8 字节，超限输入拒绝并诊断，不截断造成身份碰撞。

首版不自动删除未读，也不自动删除用于防重放的已确认身份。自动清理、压缩归档和用户清理流程另做后续设计；容量上限不是 TTL，更不是“已读”。达到容量后不得继续无限积累内存或逐条错误日志。

## 6. 独立状态与优先级

现有运行、WaitingApproval、WaitingInput、Error 输入继续保留，新增独立 unreadCount。渲染 attention 只解析 `Error > Waiting > Unread > None`；是否运行动画单独由可信活动及既有 Running 选择决定。

| 输入 | 灯带 | Running 频谱 |
| --- | --- | --- |
| 只有 Unread | 绿色 | 无动态频谱 |
| Active + Unread | 绿色 | 持续，Provider/用户选择的普通运行色 |
| Active + Waiting + Unread | 黄色 | 持续，可用 Waiting 覆盖色 |
| Active + Error + Waiting + Unread | 红色 | 持续，可用 Error 覆盖色 |
| Error 解除，仍有 Waiting/Unread | 黄色 | 跟随 Active |
| Waiting 解除，仍有 Unread | 绿色 | 跟随 Active |
| Unread 确认，无其他提醒 | 无 | 跟随 Active |

未读跨新轮次持续。Waiting/Error 的解除依据其真实恢复事件和已有可验证状态策略，不使用未读确认、关面板或来源掉线解除。需要用户操作的非阻塞通知也不能停止其他会话的 Active。

复合 Session 键改动需同步快照迁移。旧快照缺来源时标记为 legacy-local，保留现有六小时恢复策略；其完成状态不迁入 Inbox。不能虚构旧快照的账户或原生身份。

当前无稳定来源的 Error 仅能做 fixture/兼容输入验证；真实来源能力表应如实列 unsupported/unverified。首版不承诺全面 API 错误采集，不把 quota 查询失败当作 Agent 故障。

## 7. 灯带、几何与生命周期

每个 Display/Provider lane 保持固定效果层引用：蒙层、Running、顶线、底带、内向 glow、底带 sweep。额度填充可以单独更新，不能因此替换 attention 层或重新开始动画。屏幕移除时释放对应引用。

初始值为顶线 3pt、底带 6pt；三种提醒使用相同图层结构。Error 默认 `#FF476B`，Waiting `#FFD338`，Unread `#36F8A2`；周期分别 4/5/7 秒。这些是可改主题默认值。

所有图层共用 Provider 可见区域裁切：刘海空区不画顶线、底带或 glow；sweep 在每个可见区内移动。Single 穿过刘海时拆成可见片段，不能因为 root 只有矩形裁切而漏线。尺寸用逻辑点，按实际 backing scale 对齐。

频谱可用区域从底带上缘向上，顶端不压过顶线。缺真实额度时传空 windows 与正常 lane 几何，保持中性底槽和真实提醒；不改变额度值或基准线。

首扫语义：None → 有提醒、最高 attention 种类改变时立即扫一次。相同种类下新增未读只更新数量，不再首扫；周期照常进行。重复事件、数量变化、额度刷新、主题编辑、切 Space、来源重连都不构成新提醒首扫。进程重启首次展示恢复提醒允许扫一次。

主题参数变化原位更新，周期改变更新后续节奏，不附加首扫。锁屏、睡眠、隐藏/不可见时暂停动画；重新可见恢复节奏，不当作新事件首扫。可见性探测需随现有 lifecycle 修正，不仅依赖 NSWindow.isVisible。Reduce Motion 合并应用设置与系统偏好，禁用周期 sweep 和运行波形，保留静态提醒。关闭 `showAgentEffects` 隐藏提醒但不确认或丢弃记录。

全部无活动、无提醒时效果层无活动 CA 动画、无 display link；现有额度刷新和低频生命周期检查不计作新增动效循环。Overlay 继续忽略鼠标事件，不新增文字、状态按钮或伪系统图标。

## 8. 主题 v2 与设置

继续使用现有 global/providers/states；新增 `attentionRibbon` 公共几何/流光参数，以及 `states.unreadCompletion`。保留原有 quota 和 baseline 字段。

| Token | 默认/范围 |
| --- | --- |
| topRailHeight / bottomRibbonHeight | 3 / 6pt；顶部 0…10pt（0 表示关闭，兼容旧主题），底部 0.5…10pt；几何阶段按实际高度适配 |
| glowOpacity / glowRadius | 0.35 / 4pt；0…1 / 0…12pt，向内裁切 |
| sweepEnabled / sweepDirection | true / leftToRight；方向仅允许 leftToRight、rightToLeft |
| sweepWidthFraction / sweepDurationSeconds | 0.30 / 1.2秒；0.05…0.8 / 0.4…3秒 |
| 各状态 sweepIntervalSeconds | 4/5/7秒；3…60秒，且不短于扫光时长 |
| 各状态 ribbonColor/topRailColor/sweepColor | 合法现有 Hex 编码 |
| 各状态 overlayOpacity / spectrumColor | 0…1；省略或 null 表示继承普通运行色 |

几何约束：顶线与底带总高不能超过菜单栏高度的一半。合法但当前屏幕放不下时同比缩小，并在预览中反映实际尺寸；非法数值、NaN/Infinity、非法颜色或未来版本拒绝整份主题，保持上一份有效状态。

v1 加载时进行内存兼容转换，不改写用户文件：旧 borderColor 映射顶线和底带色，borderWidth 映射顶线高度（旧值 0 仍保持隐藏顶线）；无 bottom 参数时默认 6pt；Unread 使用内置绿色。Provider/global/用户显式运行色优先级保持。v2 有效字段优先于兼容字段。

Swift 解码与 JSON Schema 对未知字段统一报错，以免拼错字段静默无效；v1 已定义字段全部保留。设置编辑已存在主题时保存经过验证的 v2 副本或用户明确选择的文件，使用原子写入；恢复默认仅改变 active theme，不删除/覆盖自定义文件。

设置提供三种状态的颜色、蒙层与频谱覆盖色，以及公共顶线/底带高度、glow、sweep 开关/方向/宽度/时长/周期。使用已有 ThemeTab，保留 JSON 编辑与错误反馈。至少三个示例主题（高亮、低饱和、低 glow）和真实 renderer 驱动的组合 fixture；浏览器示意不能作为设置预览实现。

## 9. 待关注列表

在现有 320pt 菜单栏面板增加待关注区域，按 Provider 分区，Error → Waiting → Unread 排序；与额度区域共用可滚动容器，额度无数据时也显示关注项。

未读行显示 Provider、短 Session 标识、完成时间、统计单位及“AIUnderlay 本地记录”。正文说明“本地确认，不会同步 Codex/Claude 客户端”。来源 unavailable 或接收中断单独显示诊断，不伪装成红色 Agent Error。

操作：单项“标记已查看”、按 Provider 的“全部标记已查看”。等待/故障行仅展示已验证状态与现有可用入口，不新增自动审批、危险重试或通用“清空故障”按钮。

只有通过实际来源验证的打开能力才显示“打开会话”；无法打开时隐藏按钮并说明能力限制。失败显示反馈，成功也不确认已读。首版不为提供按钮而猜深链或读私有文件。

保存成功、来源诊断及事件变化都发布面板 revision，使已打开面板即时更新；不能只等额度刷新或重新打开面板才显示。

## 10. 实施依赖与阶段出口

以下是设计级阶段；用户审阅本文后，执行计划要把每阶段拆成具体文件、命令、测试和提交边界。

| 阶段 | 前置 | 可审阅产物与出口 |
| --- | --- | --- |
| P0 来源资格与差距报告 | 当前仓库 | 脱敏 fixture、来源能力表、成功/失败分类、身份策略；至少一个真实来源合格或明确阻塞 |
| P1 事件与 Inbox | P0 合格来源 | 跨来源身份隔离、去重、冷启动基线、保存恢复、确认事务测试通过；状态诊断可用 |
| P2 信号、主题与灯带 | P1 | v2 和 v1 兼容、原位 layer 更新、无额度提醒、组合 fixture；视觉与主题测试通过 |
| P3 面板与设置 | P1/P2 | 列表实时更新、单项/范围冻结批量确认、能力检测打开入口；存储失败反馈可复现 |
| P4 端到端与回归 | P0…P3 | 真实来源闭环证据、实机矩阵、性能前后值、用户文档与进度更新 |

每阶段更新 `docs/implementation-progress.md`，只写实际执行的命令、结果和限制。P0 不安装或更改用户 Hook 配置；后续需要安装时沿用已有预览/确认流程。文档提交和产品阶段提交分开，不包含可视化临时目录或无关修改。

## 11. 验证方案

### 自动化

- Adapter/Helper/Receiver：成功、失败、取消、工具结束、子 Agent、字段缺失、白名单不泄漏正文；来源资格明确。
- Inbox：稳定键重复、乱序、新轮次保留旧未读、跨 Provider/Source 同名隔离、首次启用不导入历史、确认后重放不复活。
- 存储：原子保存恢复、损坏/未来版本不覆盖、确认失败保持未读、串行命令不丢更新、容量上限、重启恢复；未读不能继承 Session 六小时过期。
- 聚合/UI：Error/Waiting/Unread 逐级回退、跨 Provider、Active 独立、范围冻结批量确认、打开失败/成功均不确认、无额度仍显示。
- Theme/Layer：v1 映射、Provider 色不丢、未知字段与非法值拒绝、小高度适配、不同 scale、Notch 片段无漏线、额度/主题刷新不首扫、隐藏/恢复与 Reduce Motion。

实施时运行：

```bash
xcodegen generate
Scripts/check-domain-purity.sh
Scripts/test.sh -derivedDataPath build/DerivedData
xcodebuild -scheme AIUnderlay -destination 'platform=macOS' -derivedDataPath build/DerivedData -configuration Release build
```

这些是未来实施验证命令，本文编写阶段没有运行产品测试，不引用旧测试数量充当新功能验证。

### 实机与证据

真实来源至少跑一次成功完成和失败/取消对照；在 AIUnderlay 确认后重启，未读不复现。采集支持版本与来源限制要写在能力表，不从 CLI 结果外推 Desktop。

截图/录屏覆盖三种提醒、Active+Unread、Error+Waiting+Unread 逐级解除、双 Provider 红/绿、真实或模拟刘海、Single 和无额度提醒。浏览器中已确认的示意仅作视觉方向依据。

实机检查菜单栏文字对比度和鼠标穿透、Retina/不同菜单栏高度、外接屏、Space、自动隐藏、锁屏/睡眠/唤醒、系统 Reduce Motion。没有设备的项标记未测，不宣称完成全部硬件验收。

性能同条件记录改动前后 Idle、静态提醒、周期流光、Active+提醒各 60 秒的 CPU/内存，并检查动画键和图层数量；Idle 无新增持续动画、持续刷新不积累图层为硬门槛。CPU/能耗只报告实际值，不编造节能比例。

## 12. 完成定义与后续原生同步

首版完成需：至少一个实际来源合格并完成真实本地闭环；其余来源清楚降级；三态灯带与独立运行组合正确；主题与确认入口可用；自动化通过；实机证据和未测项完整；旧冲突文档完成修订。

后续原生同步先做独立 spike，输出官方通道、版本、资格、readState 缺失/null 的语义、GUI 收据共享和 revision 冲突行为。经验证后增加原生适配及来源权威规则，不能把已有本地确认伪称为原生已读，也不能因为原生暂时不可用清空本地未读。

## 13. 自审结果

- 无待填占位；未验证来源用明确能力门槛描述，不当作已知事实。
- 本地账本、Session 完成瞬态、原生已读三种语义分开；确认只影响指定未读。
- 动画首扫、同级新完成、重启和可见性恢复的行为已区分。
- 可恢复状态不静默清除；存储失败、损坏、身份不足、容量不足都有明确降级。
- 范围可由一个实施计划覆盖；原生同步和停机补采不阻塞首版。
