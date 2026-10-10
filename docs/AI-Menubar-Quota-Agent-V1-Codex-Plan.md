# AI Menu Bar Overlay — V1 可执行开发计划（交给 Codex）

> 版本：V1 / 2026-10-11  
> 性质：**工程实施计划**，不是设计脑暴；Codex 应直接按阶段执行、提交代码与测试。  
> 项目定位：**macOS 菜单栏背景中的 AI 额度与 Agent 运行状态可视化**。社区负责 Provider 数据采集；本 App 负责发现/管理采集引擎、标准化数据、计算布局及绘制。  
> 参考实验文档：`menubar-overlay-technical-notes.md`（用户提供，源于 WandelBar 的覆盖层实验）。如该文件未放入仓库，应先将它加入 `docs/reference/` 或保留其来源链接。本计划已包含关键技术约束，可独立阅读。

---

## 0. Codex 执行指令（务必先读）

1. **先检查仓库现状**：若已有 Xcode 项目、Overlay 代码或既有架构，尽量增量改造，不要为了匹配本文目录而重写。若仓库为空，创建新的 Swift/SwiftUI + AppKit macOS 项目。
2. 先完成 **P0 验证**（菜单栏覆盖窗口层级、真实菜单栏高度、外部 CodexBar CLI JSON、Agent Hook 可达性），确认关键假设后再逐步实施。
3. 每个阶段都应产出可运行的增量和测试；**不要只提交空接口、TODO 或 mock UI 就声称阶段完成**。无法在当前环境实测 macOS API 时，应编写隔离的纯逻辑测试并明确列出硬件验证项。
4. `CodexBar`、`CodeStatus` 是可替换的上游数据来源，**不可让它们的数据结构直接进入渲染器**。
5. 不做 Provider 私有接口逆向；不做密码窃取、自动复制 Cookie、私自修改 Agent 配置、默认安装可执行文件、默认上报遥测。
6. 对不确定的上游行为，先读对应版本源码和官方文档，再做兼容性验证；不要根据本文示例推断所有版本具有同样字段。
7. V1 必须能离线用 Fixture/Mock 数据完整预览菜单栏效果；真实 Provider 连接失败不能让 UI 崩溃或变成虚假的 0%。
8. 每阶段更新 `docs/implementation-progress.md`（完成/未完成、变更、验证、风险）；最后输出 README、演示截图或录屏路径、测试结果、已知限制。

**首版范围约束：** 优先发布 GitHub/Developer ID 版本。Mac App Store 兼容性单独评估，不能假定运行时下载 CLI 的方案可通过审核。UI 初版至少包括：双侧/单条、两种锚点、递归嵌套额度、基准线、Provider 配置、Agent 状态动效、基础诊断。

---

## 1. 产品目标 / 非目标

### 1.1 目标

- 在**菜单栏背景**中渲染一条完整的 Progress Bar，而不是额外占据宽度的多个独立状态项。
- 有刘海时可用左右两侧分别显示 Provider（默认左 Codex、右 Claude Code）；无刘海时可按屏幕中线形成双侧，或切换为一个贯穿菜单栏的完整 Bar。
- 使用**递归嵌套的剩余额度**（例如周 → 5h；当 Provider 真有月额度时才支持月 → 周 → 5h）。
- 支持**外缘锚点 / 刘海锚点**双向切换；方向与数据含义解耦。
- 在进度条上显示一条与当前额度窗口对应的**使用节奏基准线**；不用固定 30 天/4 周计算周额度。
- 叠加 Agent 生命周期动效（运行/等待用户/等待授权/完成/错误/未知），不影响额度 Bar 的真实数值。
- 自动检测用户现有 CodexBar CLI；若未找到，允许用户在界面上**明确确认后**下载托管版 CLI；不强制安装完整 CodexBar App。
- 在本 App 里配置 Provider：优先复用已有本地登录状态；对于上游明确支持的 API Key Provider，提供本 App 的安全输入与验证；对不支持的认证方式给出引导，而不是伪造登录流程。
- 数据来源开放：日后可添加其他 CLI、localhost HTTP、用户自定义脚本，Renderer 无需修改。

### 1.2 V1 不做

- 自己实现 Codex/Claude/Gemini 的额度抓取、登录协议、逆向 API。
- 将 Codex 的订阅月视为独立“月额度”（**没有数据就不展示月层**）。
- 复杂的多 Provider 合成「综合使用率」或多账号自动切换。
- 自动操作 Agent、代答审批、发送 Prompt、切换会话内容。
- 壁纸修改、完整壁纸特效重渲染、私有 SkyLight 注入、按 Space 独立配置。
- 未经用户确认修改 `~/.claude/settings.json`、Codex Hook 配置或全局 CLI。
- 自动采集 Prompt、对话文本、项目内容，或向外部发送使用统计。

---

## 2. 技术选型与兼容性

| 组件 | 技术与约束 |
| --- | --- |
| 语言 | Swift 6，尽可能启用严格并发检查 |
| UI | 设置/详情使用 SwiftUI；菜单栏覆盖绘制使用 AppKit + Core Animation `CALayer` |
| 最低系统 | **macOS 14+（V1 建议）**；虽然覆盖层公开 API 的理论下限是 macOS 12，但 CodexBar 当前 CLI/构建生态要求 macOS 14+，V1 不为 12/13 额外改造 |
| 处理器 | 优先 arm64，计划兼容 x86_64；安装 CLI 时依硬件架构选择实际 Release Asset |
| 分发 | GitHub Releases + Developer ID 签名/公证（若签名环境可用）；开发构建可 ad-hoc |
| 窗口 | 透明、无边框、`ignoresMouseEvents = true`、位于 `desktopIconWindow + 1`；保证菜单栏原生交互不被遮挡 |
| 几何 | `CGWindowListCopyWindowInfo` 获取菜单栏真实窗口 bounds；`NSScreen.auxiliaryTopLeftArea/RightArea` 获取刘海左右区域 |
| 绘制 | `CALayer` 实体填充、clip mask、基准线、CAAnimation；仅数据/几何变化时更新图层 |
| 数据采集 | `CodexBarCLI`（外部优先，托管安装兜底）；通过进程无 shell 调用、JSON 解析 |
| Agent 事件 | 参考/按许可复用 CodeStatus 的 Hook、Socket、Reducer 原理；不依赖其 UI |
| 配置 | 应用自有设置（UserDefaults / Codable 文件），机密数据与非机密分离 |

**务必保留实验文档中的三个结论：** ① 不修改壁纸，② 菜单栏高度不能只靠 `visibleFrame`（外接屏可能测出 0），③ Progress 本身用 CALayer、不要为百分比刷新重跑 Core Image。

### 2.1 特别注意

- 实验文档中的层级值 24 只是特定系统实测，**必须用** `CGWindowLevelForKey(.mainMenuWindow)`，不要写死 24。
- 实验文档只实测过特定 macOS 27 环境；macOS 14/15、自动隐藏菜单栏、Stage Manager、1x/2x、全屏 Space 均需重新验证。
- 纯 Overlay 的几何/绘制不需要屏幕录制权限；**Provider 登录凭证访问、Agent Hook 安装可能涉及额外系统权限与用户授权**，不可笼统宣称整 App 无权限需求。
- V1 不调用私有 SkyLight。全屏检测若无法仅靠公开 API 可靠实现，应在设置里明确提供“全屏时自动隐藏（实验性）/手动隐藏”的行为与已知限制，而不是假称准确识别。

---

## 3. 推荐模块划分

```text
App/
├── Application/
│   ├── AppCoordinator.swift
│   ├── SettingsStore.swift
│   └── AppLifecycle.swift
├── Domain/                         # 不依赖 SwiftUI/AppKit/CodexBar
│   ├── ProviderID.swift
│   ├── QuotaSnapshot.swift
│   ├── AgentSession.swift
│   ├── QuotaLayout.swift
│   ├── QuotaPace.swift
│   ├── QuotaEvent.swift
│   └── DisplayConfiguration.swift
├── Data/
│   ├── QuotaEngine.swift
│   ├── QuotaEngineManager.swift
│   ├── CodexBar/
│   │   ├── CLIInventory.swift
│   │   ├── CodexBarCLIClient.swift
│   │   ├── CodexBarInstaller.swift
│   │   ├── CodexBarUsageDecoder.swift
│   │   └── CodexBarProviderConfig.swift
│   ├── SnapshotCache.swift
│   ├── QuotaRefreshScheduler.swift
│   └── Fixtures/
├── Agent/
│   ├── AgentEventAdapter.swift
│   ├── AgentEventReceiver.swift
│   ├── AgentSessionReducer.swift
│   ├── HookSetupCoordinator.swift
│   └── AgentActivityAggregator.swift
├── Overlay/
│   ├── MenuBarOverlayController.swift
│   ├── MenuBarBandWindow.swift
│   ├── MenuBarGeometry.swift
│   ├── BandWatchdog.swift
│   ├── GaugeLayerRenderer.swift
│   ├── NestedGaugeGeometry.swift
│   ├── BaselineMarkerLayer.swift
│   ├── AgentEffectLayer.swift
│   └── ThemePalette.swift
├── UI/
│   ├── Settings/
│   ├── ProviderSetup/
│   ├── Diagnostics/
│   └── Preview/
└── Resources/
    ├── Licenses/
    └── PreviewFixtures/
Tests/
├── DomainTests/
├── AdapterTests/
├── EngineManagerTests/
├── AgentTests/
├── GeometryTests/
└── SnapshotRenderingTests/
docs/
├── reference/menubar-overlay-technical-notes.md
├── architecture.md
├── implementation-progress.md
├── privacy-and-permissions.md
└── release-checklist.md
```

名称仅为建议，可依现有仓库命名调整；**模块依赖方向必须严格遵守：Data/Agent → Domain ← Overlay/UI**。

---

## 4. 统一的 Provider/Quota 领域模型

### 4.1 领域接口

```swift
enum DataAvailability: String, Codable, Sendable {
    case valid, stale, unavailable, unauthenticated, unsupported, unknown
}

struct QuotaWindow: Identifiable, Codable, Sendable {
    let id: String                   // provider-specific stable window identifier
    let label: String                // "5h", "Weekly", "Monthly", "Sonnet" 等
    let kind: QuotaWindowKind        // session / weekly / monthly / custom
    let durationSeconds: TimeInterval?
    let remainingFraction: Double?  // 0...1，nil 表示未知；绝不把 nil 当 0
    let resetAt: Date?
    let expectedRemainingFraction: Double?  // 节奏基准（可能缺失）
    let updatedAt: Date?
    let availability: DataAvailability
}

struct ProviderQuotaSnapshot: Identifiable, Codable, Sendable {
    let id: String                   // providerId + accountKey, 避免跨账号混合
    let providerId: String
    let accountKey: String?          // 内部稳定 ID，不以邮箱直接做公开显示
    let sourceEngineId: String
    let windows: [QuotaWindow]       // 不写死 month/week/5h
    let fetchedAt: Date
    let availability: DataAvailability
    let diagnosticCode: String?
}

struct AgentSession: Identifiable, Codable, Sendable {
    let id: String
    let providerId: String
    let state: AgentState
    let observedAt: Date
    let confidence: AgentConfidence
}

enum AgentState: String, Codable, Sendable {
    case idle, running, waitingApproval, waitingInput
    case completed, error, unknown, reconnecting
}
```

`QuotaWindowKind` / `AgentConfidence` 请实现完整 Codable 定义；示例不要求照搬变量名。

### 4.2 标准化规则

1. CodexBar 的 `usage.primary/secondary/tertiary` 是**位置字段，不是周期名称**；优先使用 `windowMinutes`（300=5h、10080=7d）或来源明确提供的标签识别，不可默认 `primary == monthly`。
2. `remainingFraction = (100 - usedPercent)/100`，只在 `usedPercent` 为有效有限数字且落在 0...100 时成立；异常数据标记 invalid/unavailable，不静默乱夹取。
3. 窗口长度不是独立月额度的证据；只有上游明确标识该周期的真实额度才能建模为月。
4. `resetAt`、`updatedAt` 均可为 nil；重置时间改变不等于当前数据被官方重置。
5. 一家 Provider 可有多账号、多种模型专用额度；每个账号快照独立，不把 Sonnet 限额自动和 Claude 总周额度当作同层链条。
6. 原始 CLI 错误、读取失败、没有登录、额度为 0、Provider 不支持这些状态**必须可区分**。
7. 来源增加新的 JSON 字段时保持向前兼容；缺失必需字段时隔离单 Provider 故障，不能清空其他正常 Provider。

---

## 5. 核心：递归嵌套剩余额度 Bar

### 5.1 唯一认可的主方案

**后一个额度只占前一个额度的剩余显示长度，不按真实天数切格。**

例如有真实月额度：

```text
Base bar: 100%
  └─ Monthly remaining: 80%
      └─ Weekly remaining: 60% of monthly-visible length
          └─ 5h remaining: 25% of weekly-visible length
```

若 `L = trackWidth`：

```text
L_month = L × 0.80
L_week  = L_month × 0.60        = L × 0.48
L_5h    = L_week × 0.25         = L × 0.12
```

从同一锚点绘制，**先画外层，后画内层**。外层被内层覆盖，最终一根连续 Bar 的可见区域依次代表最短窗口 → 较长窗口 → 最长窗口 → 底槽。颜色含义由 Provider 的配色方案与窗口层级共同决定。

**只有周 + 5h 的 Codex/Claude：**

```text
L_week = L × weeklyRemaining
L_5h  = L_week × sessionRemaining
```

不允许为了统一视觉凭空补一个“月 100%”。

### 5.2 规范化布局算法

```swift
// 输入：窗口从最长到最短排列，e.g. [weekly, session]
func nestedLengths(trackWidth: CGFloat, remaining: [Double]) -> [CGFloat] {
    var length = trackWidth
    return remaining.map { fraction in
        length *= CGFloat(fraction)
        return length
    }
}
```

正式实现需额外处理：有限值、未知值、零值、尺寸为零、overflow、屏幕缩放、过短区域、重复周期。**未知外层不可假设为 100%，应停止该链并显示缺失状态；允许用户在设置里显式选择另一条独立链作为主显示。**

### 5.3 方向与锚点独立配置

```swift
enum GaugeLayoutMode: String, Codable { case single, dual }
enum GaugeAnchorMode: String, Codable { case notch, outerEdge }
enum SingleBarDirection: String, Codable { case leadingToTrailing, trailingToLeading }
```

- `dual + notch`：左右 Provider 均以刘海边缘为起点，进度向屏幕外缘延伸。
- `dual + outerEdge`：左右 Provider 均从屏幕外缘向刘海方向延伸。
- `single`：整条菜单栏为一个 Provider 的 Bar，能选择从左向右或从右向左；**不要求设备有刘海**。
- 无刘海时，dual 使用中线分区（`gap = 0`）；不在屏幕中间人为制造缝隙。
- 初版每个显示器分别计算 track、几何和是否显示；默认主屏开启、其他屏可配置。

用**抽象轴**定义进度：`u = 0` 为锚点、`u = 1` 为区域末端。各层宽度按上节计算，然后统一由坐标变换映射成屏幕坐标，避免每种布局写一套百分比逻辑。

### 5.4 底槽与填充的几何分离

保留用户实验中的关键抽象：

```swift
struct GaugeGeometry {
    var trackRect: CGRect       // 底槽覆盖整条菜单栏/整屏顶部条带
    var fillBounds: CGRect      // 当前 Provider 的可用区，刘海边缘止步
    var growsTowardRight: Bool
    var fullBleed: Bool
}
```

- **底槽跨整屏**，即便 notch 双侧也不切成两个会漏出壁纸的半底槽。
- 各 Provider 的 fill 使用独立 clip，不越界、不污染另一侧。
- `fullBleed` 高度铺满菜单栏、横向 inset = 0、直角收边；不要默认画成悬浮胶囊。
- 底槽先使用黑色约 35–40% 不透明度作为初始调试参数，最终须根据浅/深色菜单栏及图标可读性调优；不是每个主题都强制此数值。

### 5.5 配色策略（先抽象，不定死色值）

```swift
struct ProviderPalette: Codable, Sendable {
    let providerId: String
    let outer: RGBAColor     // 最长窗口
    let middle: RGBAColor    // 次长窗口
    let inner: RGBAColor     // 最短窗口
    let track: RGBAColor
    let baseline: RGBAColor
}
```

- **Provider 决定主色相**（Codex 冷蓝/紫系，Claude Code 暖陶土/橙系）；窗口层级决定该色系的亮度/明度。
- 颜色只是初版建议、可由主题覆盖；**不要把橙红默认当成错误**。
- 额度告警、Agent 状态和 Provider 身份使用不同视觉通道：`颜色/长度` 表示 Provider/额度，`Marker` 表示进度基准，`动画/小端点` 表示 Agent 状态。
- 允许主题透明度调节；优先保证系统原生菜单栏文字/图标可读。

### 5.6 关键边界

- 3 个额度均满额：只看到最内层颜色是此模型的自然结果；展开详情中仍要显示全部数字。
- 某外层为 0：内层可见宽度也为 0，不为“美观”虚构剩余额度；可选独立告警点，但与实际进度长度分离。
- 1px 以下：不修改真实计算值；如需最小可见提示，用**独立端帽/标记层**表示“非零但过短”，不得让总填充超过真实长度。
- 单个窗口：一层 Bar 即可；窗体为空/数据过期时显示中性底槽与离线提示，不可伪装满额。
- 窗口数量 > 3：首版 UI 提供选择最多 3 个**可比较且有层级意义**的窗口；不把所有字段自动乱嵌套。

---

## 6. 基准线（使用节奏）

目标：帮助用户区分“当前剩余高于/低于按时间匀速消耗的预期”，而不是只看余额。

- 对某个真实的周期窗口，若上游有 `pace.expectedUsedPercent`，优先读取；转换为 `expectedRemaining = 1 - expectedUsedPercent / 100`。
- 无上游 pace 时，仅在可确定 `durationSeconds` 与可信 `resetAt` 时计算：

```text
periodStart = resetAt - duration
elapsedRatio = clamp((now - periodStart) / duration, 0, 1)
expectedRemaining = 1 - elapsedRatio
```

- 对窗口频繁提前重置的场景，不保留旧的 periodStart；`resetAt` 变更立即重算，**无可信周期则隐藏 Marker 并给出原因**。
- V1 默认**只绘制一条基准线**，默认绑定当前 Bar 的**最外层有效额度**（通常 Weekly）。设置可选择 Session/Weekly/Monthly，但要在面板说明基准对应哪个额度。
- 若绑定的是第 `i` 层，Marker 的位置必须按同样的递归空间投影：

```text
markerLength = trackWidth × (所有更外层实际 remainingFraction 的乘积)
                        × selectedWindow.expectedRemainingFraction
```

- Marker 必须与该侧进度方向一致；不可永远用屏幕左侧 x 值直接计算。
- **`actualRemaining < expectedRemaining` 表示消耗比匀速基准更快**；在 UI 中用“超前消耗/仍有余量”等中性描述，不用“浪费/白嫖”等带价值判断的词。
- 线宽建议约 1–2pt；清晰但不抢眼，提供开关和颜色/不透明度调整；至少在高对比主题里可辨识。

---

## 7. CodexBar CLI 数据引擎管理

### 7.1 真实依据（不要拍脑袋）

- 上游仓库：<https://github.com/steipete/CodexBar>
- CLI 文档：<https://github.com/steipete/CodexBar/blob/main/docs/cli.md>
- CLI Provider 配置：<https://github.com/steipete/CodexBar/blob/main/docs/cli-configuration.md>
- CLI 发布包：<https://github.com/steipete/CodexBar/releases>
- macOS 发行包命名现状：`CodexBarCLI-v<tag>-macos-arm64.tar.gz` / `...macos-x86_64.tar.gz`，解包后运行 `CodexBarCLI` 或 `codexbar`。
- 示例调用：`codexbar usage --provider codex --format json --pretty`；`codexbar config providers --json --pretty`；`codexbar --version`。
- CLI JSON 的 `usage.primary/secondary/tertiary` 含 `usedPercent`、可选 `windowMinutes/resetsAt`，另有可选 `pace.primary/secondary.expectedUsedPercent`。

### 7.2 引擎发现顺序

1. 用户手动指定路径（最高优先级）。
2. 常见 Homebrew 路径 `/opt/homebrew/bin/codexbar`、`/usr/local/bin/codexbar`。
3. 完整应用内 Helper：`/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI`；必要时搜索用户 Applications 路径。
4. App 专属管理目录：`~/Library/Application Support/<BundleID>/Engines/CodexBar/<version>/CodexBarCLI`。
5. 从**受控、最小 PATH**解析 `codexbar`；不能依赖 Finder 环境恰好包含用户的 shell PATH。

**发现不等于可用**：每个候选必须解析 symlink、确认路径和可执行性、读取 `--version`、运行小型 JSON/schema 探测，分辨“CLI 不兼容”和“CLI 兼容但账户未登录”。不使用 `which` 作为唯一逻辑。

### 7.3 首次使用与安装

- 有兼容外部 CLI：默认优先使用；不私自修改其 binary、更新版本或清理用户配置。
- 无兼容 CLI：显示解释 + **用户确认后**一键安装 CLI；提供取消、重试、查看安装路径。
- 使用 GitHub 正式 Releases 的**固定且测试通过**的版本、匹配 CPU 架构的资产，下载后验证预置 SHA-256/可信 manifest、文件结构与签名/来源；下载失败回滚，无半安装状态。
- 保存到 App 自己的 Application Support，不写 `/usr/local/bin` 或系统目录，不要求 sudo；只清理 App 管理的安装。
- 托管更新与外部 CLI 更新分开：检测更新可提示，但**不要升级用户的外部 CLI**。
- 上游若发生破坏性 CLI JSON 变化，按兼容性矩阵禁用受影响的查询、提示切换已验证托管版本。

### 7.4 进程执行安全

- `Process.executableURL` 使用**已验证的绝对路径**；`arguments` 明确数组化，禁止 `sh -c` 拼接用户输入。
- 超时、终止、取消与并发去重；防止 CLI 查询卡住导致 UI/主线程冻结。
- 将 stdout 当做结构化 JSON，限制最大输出长度，stderr 对用户脱敏后记录短摘要；错误时不回显 Cookie、Token 或账户标识。
- 隔离运行环境，只传必要环境变量；确保 `CODEXBAR_CONFIG` 走用户选择的配置模式。
- Quota 刷新默认分钟级（例如 3–5 分钟），设置页可手动刷新；禁止 1 秒一次启动 CLI。

### 7.5 配置模式必须区分

**模式 A：沿用已有 CodexBar 配置（默认优先尝试）**

- 外部 CLI 使用其自身的有效配置；我们只读并调用额度数据，不在未经明确确认时修改用户的 CodexBar 设置。
- 若想在我们的界面中启停上游 Provider，先解释这会修改共享的 CodexBar 配置，并要求用户确认；否则只改变我们自己的显示过滤，不改上游配置。

**模式 B：App 独立配置（用户要从我们的设置页直接添加新 Provider）**

- 使用 App 自己的 `CODEXBAR_CONFIG` 指向 App 专属配置文件；避免静默覆盖共享配置。
- 上游 CLI 支持 `config enable/disable` 与 `config set-api-key --provider <id> --stdin`：对支持 API Key 的 Provider，通过 stdin 输入，不放在命令行参数/日志中。
- 配置文件权限需至少参照上游限制（目录 `0700`、文件 `0600`），对凭证做 UI 脱敏和安全删除。
- 复用本机 Codex/Claude CLI 登录状态不能保证每种系统/沙盒环境都可读取；失败时显示具体来源与指引。
- 不声称单纯填写 API Key 就能读取 ChatGPT Plus/Codex 或 Claude Code 订阅额度：API 用量与订阅额度是不同概念。

### 7.6 Adapter 和协议

```swift
protocol QuotaEngine: Sendable {
    var id: String { get }
    func probe() async -> EngineProbe
    func fetch(provider: String, account: String?) async throws -> ProviderQuotaSnapshot
}

protocol ManagedQuotaEngine: QuotaEngine {
    func install() async throws
    func update() async throws
    func uninstall() async throws
}
```

EngineManager 只负责发现/选择/安装/兼容性；ProviderAdapter 负责解析与标准化。未来 HTTP/用户脚本可以实现相同模型；**Renderer 不 import CodexBar 类型**。

---

## 8. 额度刷新、缓存、重置检测

- 每个 `providerId + accountKey + windowId` 缓存最后的有效快照，附带 `fetchedAt`、源数据时间、stale 阈值。
- 初次启动离线：只能展示上次状态并明确标注“已过期”，或者只显示底槽；不得把缓存变成实时数值。
- 上游可在非计划时间恢复额度，也可能因同步问题出现跳变。因此：
  - 额度**按最新可信快照及时刷新**；
  - “确认已重置”的事件（比如闪光动效、重置记录）需要时间戳/窗口变化或二次采样来确认；
  - 未确认突增只标“可能重置/数据变化”，不能断言是官方赠送额度；
  - `resetAt` 变化后重新计算基准线，不按上个周期固化日期。
- 只更新受影响的 CALayer 数据；正常刷新不可制造整条 Overlay 的闪烁。
- 刷新周期、动画强度、显示的 Provider 均可配置；空闲时降低采集频率。

---

## 9. Agent Activity 数据接入与动效

### 9.1 不和 Quota 引擎混为一谈

- Quota：分钟级主动抓取、主要是百分比和重置时间。
- Agent：事件驱动、低延迟、主要是 Session 状态。
- 两者独立运行，通过 `providerId` 及账户/会话映射在 Presentation 层汇合。

### 9.2 参考上游

- <https://github.com/henriquegpb/codestatus>（CodeStatus，MIT；参考 Hook、Unix Socket、Session Reducer、去重、掉线恢复）。
- Codex 在不同宿主中的 Hook 能力**不完全相同**。当前 CodeStatus 的能力说明表明：Claude Code CLI 可检测 Busy/Approval/Input；Codex CLI 可检测 Busy/Approval，但一般不能可靠检测“等待自由文本回答”，Codex VS Code 的若干状态尚未验证。
- **禁止通过 CPU 活跃度或长时间无事件推断 Agent 一定已完成/空闲。** 状态无法确认时用 `unknown/reconnecting`。

### 9.3 V1 实施策略

P0 Spike：先检查 CodeStatus 能否直接复用稳定的 Hook client / Core reducer（或按 MIT 许可引用经过许可的代码）。记录 upstream commit/tag 和改动。不能复用时，仅移植**极少量** Hook 事件转接和状态机，而非复制完整 app/UI。

P0 真正接通 Claude Code CLI 生命周期：

1. 设置页“启用 Agent 检测”需**用户确认**，并展示要安装的 Hook 配置变更预览。
2. 安装器尊重原文件格式和已有 hooks，优先做保留字节的最小插入；修改前备份；卸载只清理自己安装的条目。
3. Hook 回调异步/非阻塞，使用 Unix Domain Socket 或同等受控本地 IPC 发出**白名单元数据**（provider、sessionId、事件类型、时间）；不包含 prompt、命令行秘密、回复文本。
4. Reducer 按 `sessionId` 处理乱序、重复、重连、退出；维护可信度。
5. 先做到 `running`、`waitingApproval`、`waitingInput`、`completed`、`error/unknown` 的真实支持（某事件不可观测要降级）。

P0 Codex CLI：接入经验证的事件，包括 `running`、可识别的 approval、完成；无法判断等待普通输入时显示 `unknown`，不能强行显示橙灯。Codex VS Code 支持应按实测标记，不将 CLI 结果推广到所有宿主。

### 9.4 动效语言

| 状态 | 视觉行为 | 备注 |
| --- | --- | --- |
| idle | 静态额度条 | 不额外耗电 |
| running | 沿额度填充方向缓慢 shimmer/柔和扫光 | 1 个共享动画驱动，拒绝全屏逐帧重绘 |
| waitingInput | 一端小型提示点 + 温和双脉冲 | 必须是真实可观察的等待输入 |
| waitingApproval | 提示点 + 更明确的节奏脉冲 | 和一般等待回答区分 |
| completed | 一次短促亮度扫过（约 1 秒）后恢复静态 | 瞬态，不长期绿色常亮 |
| error | 小端点/边缘告警高亮 | 不把 Provider 品牌主色整条换红 |
| unknown/reconnecting | 中性静态、详情中标未知 | 不假装 idle |

多 Session 聚合优先级：`error > waitingApproval > waitingInput > running > completed > idle`；未知会话数单独显示，绝不能被忽略为已完成。Popover/详情页列出不同状态的 Session 数量；V1 Bar 一侧只播放一种主状态动画。

支持 `Reduce Motion`、低电量模式和“完全关闭动效”；动画关闭后仍能通过小端点/详情区分需用户处理的状态。暂停不可见屏幕的动画，避免持续高帧率 CPU 占用。

---

## 10. Overlay 具体实现（以实验文档为准）

### 10.1 Band Window

```swift
@MainActor
final class MenuBarBandWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
}
```

- 每块显示器一个实例，以显示器稳定 ID 维护；移除显示器要彻底移除旧窗口。
- `setFrame(x: display.frame.minX, y: display.frame.maxY - menuBarHeight, width: display.frame.width, height: menuBarHeight)`；处理 Retina 缩放。
- 从窗口服务器读取菜单栏 layer/bounds，匹配 display 位置与宽度；500ms 缓存降低开销。
- 刘海边界优先 `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`；nil 时用中线退化。
- 底槽用单个全宽 Layer，各 Provider 裁切仅在自己区域内。
- 不实现墙纸预处理路径；初版只要透明窗口 + 中性底槽 + CALayer fill。实验中的 Core Image 壁纸渲染/`NSVisualEffectView` 可以作为后续独立显示选项，**不得纳入 P0 的必做范围**。

### 10.2 生命周期和看门狗

- 监听：`NSApplication.didChangeScreenParametersNotification`、`NSWorkspace.activeSpaceDidChangeNotification`、session lock/unlock、外观变化。
- `NSWindow.isVisible` 不足以保证覆盖窗口真实存在：每 5 秒用 `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 对比同进程、同层级的窗口数量，缺少才 `orderFrontRegardless()`。
- 全屏/菜单栏自动隐藏要做能力探测和实机测试；不采用私有 SkyLight 偷偷判断。
- 数据与颜色更新只修改 Layer 属性；异步耗时任务离开主线程，用 revision token 丢弃旧结果。

### 10.3 性能限制

- Quota 数据变化最多按实际刷新频率驱动，不创建高速 polling。
- Agent 动画交给 Core Animation 合成，尽量不使用全局每帧 `Timer` / SwiftUI 主视图刷新。
- 窗口服务器探测独立节流；UI 隐藏时降低检查频率。
- 性能验收需要采样 CPU、内存、Energy Impact，在空闲、持续运行、睡眠唤醒、双屏分别记录；不要杜撰通过门槛数值。

---

## 11. 设置和交互（V1 最小但可用）

采用 SwiftUI 设置窗口（用户无需终端）：

### 11.1 Providers

- 已发现的 Provider 列表：Codex、Claude Code，以及 CodexBar 能返回的其他 Provider。
- 每项显示：启用/禁用显示、当前来源、登录状态、上次成功更新时间、支持的额度窗口、`Test Connection`。
- 对 API Key/Token 模式，只有在该 Provider 通过上游明确支持时显示输入框；完成后输入不明文回显，保存遵循上游配置机制。
- 外部 CodexBar CLI 共享配置与 App 独立配置必须提供明确说明；修改外部共享配置前先得到确认。
- 多账号支持底层结构；首版单侧选择**一个账户快照**，不可暗中混合账号余额。

### 11.2 Engine

- 显示：外部 CLI 路径/版本、托管 CLI 路径/版本、兼容性、优先选择、检测日志（脱敏）。
- 按钮：重新检测 / 安装托管 CLI / 更新托管 CLI / 切换来源 / 卸载托管 CLI。
- **只有用户明确点击安装才下载可执行文件**，下载进度可见；安装前说明许可、文件大小、来源。

### 11.3 Appearance

- `single / dual`；dual 可各自选择 Provider 与账户。
- `notch / outerEdge`（dual）；`leftToRight / rightToLeft`（single）。
- Provider 品牌色板与亮度、不透明度、轨道色、基准线开关/样式。
- 嵌套窗口顺序和启用选择（不能随意违反周期语义）；默认周 → 5h。
- Agent 动效开关、强度、Reduce Motion、低功耗自动暂停。
- 显示器启用选择；菜单栏自动隐藏/全屏场景配置；启动时运行可选。

### 11.4 Preview & Diagnostics

- 内建 Fixture：`full`, `weekLow`, `sessionLow`, `allZero`, `missing`, `stale`, `reset`, `agentRunning`, `agentWaiting`, `notchless`。
- 不需要登录任何 Provider，就能预览真实 Layer Renderer 的输出（不是另一套仅在设置窗口画的“假预览”）。
- 单侧/双侧方向效果能即时切换。
- 诊断：窗口服务器测得的高度、刘海矩形、显示器 scale、Overlay 窗口数量、CLI 路径/版本、上次查询状态、Agent Hook 安装状态，提供**脱敏**复制诊断信息。
- Overlay 本身点击穿透：设置入口用**紧凑的 NSStatusItem**（仅控制，允许用户隐藏）或 Dock/设置窗口，不能把点击加到全宽背景上拦截 macOS 菜单栏。

---

## 12. 测试矩阵（必须实现）

### 12.1 纯逻辑单元测试

- `[0.8, 0.6, 0.25]` 的结果恰为 `[0.8, 0.48, 0.12] × trackWidth`。
- `[0.6, 0.25]` 的结果恰为 `[0.6, 0.15] × trackWidth`。
- 任意输入为 0、1、未知/NaN/无穷、缺少窗口、不按长度排序，都有明确结果。
- 外层窗口不存在不能被悄悄补为 100%；单窗口渲染正确。
- notch 锚点/外缘锚点在左右屏幕镜像下填充长度相等、方向对称；single 反向正确。
- 基准线实际与预期的关系正确；选 inner 时带上外层长度乘积。
- `resetAt` 更新、服务端额度突然上升、数据过期，均不产生虚假月额度或误判重置事件。

### 12.2 JSON Fixture 合同测试

- 根据**实际固定版本** CodexBar CLI 输出采集脱敏 Fixture，至少 Codex/Claude/一项 API Key Provider。
- `primary/secondary` 颠倒，`tertiary` 新增，缺失 `windowMinutes`，空数组，错误响应，混合成功失败，数据结构增字段，不互相破坏。
- `pace.expectedUsedPercent` 存在/缺失；不同账户独立。
- Decoder 不依赖真实 CLI、真实网络、真实 Keychain 就能测试。

### 12.3 EngineManager 测试

- 外部存在兼容 CLI：不下载、不覆盖外部。
- 外部存在但版本不兼容：提示托管版本/手动选择，不误报“未安装”。
- symlink 断链、没有执行权限、CLI 启动失败、超时、输出畸形、架构不匹配。
- 下载网络错误/校验失败/磁盘不足：回滚，旧版本继续工作。
- CLI 存在但账户未登录：引导 Provider 设置，不触发 CLI 重新安装。
- 修改共享 CodexBar config 必须经过确认；App 独立 config 不覆盖共享文件。

### 12.4 Agent 测试

- 乱序事件/重复事件/Session 退出/重连，不把过期事件变成完成。
- 两个 running + 一个 waitingApproval 时，状态聚合为 waitingApproval，详情数正确。
- Claude Input/Approval 和 Codex 无法确认 Input 的区别；未知不能算 idle。
- Hook 安装/卸载不破坏用户原配置；非阻塞，无对话文本写盘。
- 无 Hook 时仅显示 `unavailable/unknown`，不显示“正在运行”的虚假动画。

### 12.5 macOS 实机测试清单

- macOS 14/15/26/27（可得到哪些设备就记录哪些设备；**未验证明确标注**）。
- 内置刘海屏、无刘海外接屏、双屏热插拔、镜像屏、缩放/Retina。
- 菜单栏浅色/深色/壁纸明暗、图标可读、自动隐藏。
- Space 切换、Mission Control、全屏应用、屏幕锁定/解锁、睡眠/唤醒。
- 重复快速修改滑块/方向，不出现旧渲染覆盖新状态。
- 看门狗模拟实际窗口被移出前台的情况，不频繁闪烁。
- 用户未安装 CodexBar；已有 CodexBar CLI；CodexBar App 内置 CLI；非兼容版本。
- 真实 Codex 和 Claude Code 至少各一条 Provider 成功取得额度数据；真正的 Agent Hook 在可信支持的平台上产生状态切换。

---

## 13. 可分阶段直接执行的任务清单

### P0 — 环境与可行性 Spike（先做，阻塞后续）

- [ ] 检查仓库与编译目标、创建工程骨架，记录 macOS/Swift/Xcode 版本。
- [ ] 用透明 `NSWindow` + `desktopIconWindow + 1` 在真实菜单栏后画一个静态颜色条，验证不挡系统图标、不会拦截点击。
- [ ] 用窗口服务器读取菜单栏高度，验证一块内屏、一块外屏；无刘海退化可工作。
- [ ] 在可访问的真实环境下检测 CodexBar CLI，运行 `--version` 与 `usage --provider codex --format json`；保存**脱敏 JSON Fixture**。
- [ ] 检查上游 CodeStatus 可复用的 Hook/Reducer 边界和 Codex/Claude 的真实事件能力；写明“哪些状态能准确监控”。
- [ ] 建立 `docs/implementation-progress.md` 与 `docs/architecture.md`。

**验收：** 有真实可见的静态 Overlay 原型、可执行的 CLI schema 测试、Agent 能力验证报告，非 macOS 环境缺项有明确标识。

### P1 — Domain / Renderer / Mock（核心演示版）

- [ ] 实现领域模型、配置存储、Fixture 状态源。
- [ ] 实现全宽单条与左右双侧布局、两种锚点、无刘海退化。
- [ ] 实现周 → 5h、月 → 周 → 5h 的递归嵌套几何与 CALayer 渲染。
- [ ] 实现品牌可替换色板、底槽、基准线、离线/空额状态。
- [ ] 实现 Overlay 多屏 Controller、缓存菜单栏几何、五秒看门狗与生命周期事件。
- [ ] 实现 SwiftUI 设置页可调布局、配色、模拟百分比及预览。
- [ ] 补齐几何、递归长度、Marker 和显示状态测试。

**验收：** 在没有 CodexBar/Agent 的情况下，用户能启动 App、操作设置、在真实菜单栏背景看到所有模拟状态与正确的方向和嵌套。

### P2 — 真实额度接入与 CLI 管理（首版最重要功能）

- [ ] 实现 `QuotaEngine` / `EngineManager` / `CodexBarCLIClient`。
- [ ] 外部 CLI 自动检测、路径与版本验证、手动覆盖选择。
- [ ] CLI JSON 解析/Adapter：至少 Codex、Claude；第三 Provider 可通过同一个泛型解析路径接入。
- [ ] 实现 App 专属托管 CLI 一键安装与更新/卸载（先 pin 版本，具校验与回滚）。
- [ ] Provider 设置：启用显示、选择账户、测试连接、现有登录态复用；支持已明确适配的 API Key 输入。
- [ ] 额度缓存、分钟级刷新、错误/失效处理、异常重置识别、基准线实时更新。
- [ ] 完成 CLI Fixture/EngineManager 测试，实际运行至少两家 Provider 的额度场景。

**验收：** 有 CLI 直接使用；无 CLI 可在 App UI 经同意安装；不安装完整 CodexBar App 也能取得至少一个已登录 Provider 的真实额度；不凭空创建月额度。

### P3 — Agent 状态桥接与动效

- [ ] 实现统一 `AgentEventAdapter` / `AgentSessionReducer`。
- [ ] 实现 Hook 接入（优先 Claude Code；Codex CLI 仅实现已验证能力）与用户确认安装/卸载。
- [ ] Overlay 上叠加 running shimmer、waitingInput、waitingApproval、completed、error 提示动效。
- [ ] Reduce Motion、动画节流、Session 聚合策略。
- [ ] 双 Provider 同时运行/一边等待输入时真实状态互不干扰。
- [ ] Hook 状态变更测试、配置不破坏测试、脱敏诊断。

**验收：** 至少 Claude Code 的 running/等待用户或授权事件能在菜单栏产生真实可观察的动效；Codex 不支持的细分状态正确标为 unknown，不作虚假承诺。

### P4 — 首版发布收尾

- [ ] 调整深/浅模式色彩和菜单栏图标可读性；主题可自定义。
- [ ] 验证多屏、Space、自动隐藏/全屏、锁屏、睡眠唤醒。
- [ ] 完成性能采样、处理异常恢复、测试报告与已知限制。
- [ ] 完成 README（安装、CLI 来源、Provider 登录、权限、排障）、第三方许可证 `NOTICE`、隐私声明。
- [ ] 输出可运行 `.app`（有签名环境再做 Developer ID 公证），给出版本号和变更摘要。

**验收：** 所有 P0–P3 阶段均有可核查代码与测试，核心体验无需终端；不满足的硬件/系统验证在 release checklist 中明确列出。

---

## 14. “完成定义”（Definition of Done）

V1 可被视为开发完成，当且仅当：

1. App 在实际 macOS 菜单栏背景显示**一条连续嵌套 Bar**；双侧与单条可切换，两个方向均正确。
2. Codex/Claude 可分别绑定不同侧，颜色与渲染逻辑独立；无刘海设备仍可用。
3. 周和 5h 使用真实 Provider 数据按**递归乘法**绘制；缺少月额度时绝不假造月数据。
4. 基准线取可信 pace/周期信息，动态跟随更新与重置；不再按固定四周/30 天代替实际窗口。
5. 系统发现已有 CLI 会直接复用；未找到可由用户在 App UI 确认安装；安装不会破坏系统已有 CodexBar。
6. 用户可以在 App 内选择 Provider、管理显示与接入方式；上游支持的 API Key 可以安全输入，其他认证提供真实限制说明。
7. 至少 Claude Code 的运行/等待事件被真实接入；Agent 动效与额度显示相互独立，未知状态不冒充已完成。
8. 多屏/Space/窗口丢失恢复的核心机制到位；不阻挡菜单栏点击；关闭动效时保持低负载。
9. 有单元测试、Fixture、实机验证记录、第三方许可与上游版本记录。
10. 不默认上传遥测，不采集对话正文，不静默安装 Hook/CLI，不引入私有 SkyLight。

---

## 15. 交付物和最后回复格式

Codex 执行结束后提供：

```text
1. 已完成内容（对应 P0–P4）
2. 核心源码路径 / 关键模块说明
3. 实际成功的构建/测试命令及结果
4. 真实 Codex/Claude 数据接入验证结论（通过/未验证）
5. Agent Hook 能力与限制（按宿主分别说明）
6. macOS 实机测试与未测试场景
7. CLI 上游版本、发布链接、许可证与 NOTICE
8. 已知问题、下一版优先级
9. App 可执行路径/Release Artifact
```

如果环境不能构建 macOS App，不得说已经完成整套 V1：可完成纯逻辑、文档、源码及 Fixture，但必须标注 `BLOCKED: needs macOS + Xcode`，让下一轮 Codex 在 Mac 上继续。

---

## 16. 上游资料与参考

**用户提供的实验文档（绘制依据）：** `menubar-overlay-technical-notes.md`。重点参阅窗口层级（第 2 节）、菜单栏几何（第 3 节）、Gauge 的 `trackRect/rect` 分离（第 6 节）、看门狗和生命周期（第 7 节）、macOS 兼容性限制（第 11 节）。

**额度数据：**
- CodexBar：<https://github.com/steipete/CodexBar>
- CodexBar CLI：<https://github.com/steipete/CodexBar/blob/main/docs/cli.md>
- CLI 配置：<https://github.com/steipete/CodexBar/blob/main/docs/cli-configuration.md>
- Releases：<https://github.com/steipete/CodexBar/releases>

**Agent 状态：**
- CodeStatus：<https://github.com/henriquegpb/codestatus>
- 能力矩阵和不完整 Hook 场景：CodeStatus README → Capability matrix。

**注意：** 外部项目文档与二进制会更新。实施时固定已验证 tag/commit，保存协议 Fixture 与兼容性记录，不将网页中的示例版本号误当作最新可用版本。
