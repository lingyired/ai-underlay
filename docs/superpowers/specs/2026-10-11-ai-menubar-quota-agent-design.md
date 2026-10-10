# AI Menu Bar Overlay — V1 设计规范（Design Spec）

> 日期：2026-10-11
> 状态：已通过 brainstorm 逐节确认，待用户复核
> 上游计划：`docs/AI-Menubar-Quota-Agent-V1-Codex-Plan.md`（ChatGPT 生成，作为输入之一）
> 绘制依据：`docs/reference/menubar-overlay-technical-notes.md`（WandelBar overlay 实验提炼）
> 本文性质：**设计规范**，回答"做什么、边界在哪、怎么分层、怎么验收"；具体实现步骤见后续 implementation plan。

---

## 0. 决策摘要（用户已拍板）

| # | 决策 | 结论 |
|---|---|---|
| 1 | V1 范围 | **完整四子系统**：Overlay 渲染 / CLI 额度管理 / Agent Hook / 设置 UI |
| 2 | 分发方式 | 前期 **GitHub 公开发布**，后期考虑 App Store；**以 GitHub 为主** |
| 3 | 信息密度 | **先渲染出来再调**，不预设密度上限 |
| 4 | 执行者 | **用户自己分步实现** |
| 5 | 设置入口 | **`NSStatusItem`**，默认显示，设置里可隐藏 |
| 6 | 多显示器 | **每显示器独立配置**（未来可能多 Agent 同时监控） |
| 7 | 部署目标 | **macOS 14**（因 CodexBar 生态要求，非覆盖层本身要求） |
| 8 | 架构方案 | **方案 A：单进程分层单体**，协议边界作为代码硬约束 |
| 9 | plan 组织 | **一份主 plan + P0–P4 分阶硬门禁** |

---

## 1. 架构与模块边界

### 1.1 进程形态

单个 `LSUIElement`（无 Dock 图标）后台 App，一个 Xcode 工程、一个 target。

```
AppCoordinator (启动编排)
 ├─ OverlayController     ← 每屏一个穿透窗口
 ├─ QuotaEngineManager    ← 发现/选择/安装 CLI 引擎
 ├─ AgentEventReceiver    ← 进程内 Unix Socket 服务，收 Hook 事件
 └─ SettingsWindow (SwiftUI, 按需打开)
```

### 1.2 分层与依赖方向（硬约束）

```
        ┌──────────── Domain ────────────┐   零外部依赖
        │  QuotaWindow / Snapshot /       │   （不 import AppKit/SwiftUI/CodexBar）
        │  AgentSession / Layout / Pace   │   ← 所有层都依赖它
        └─────────────────────────────────┘
             ▲          ▲          ▲
    ┌────────┴───┐ ┌────┴─────┐ ┌──┴────────┐
    │ Data       │ │ Agent    │ │ Overlay   │
    │ (CLI 引擎) │ │ (Hook)   │ │ (AppKit)  │
    └────────────┘ └──────────┘ └───────────┘
             ▲          ▲          ▲
             └──────────┴──────────┘
                    ┌─ UI (SwiftUI) ─┐   ← 只读 Domain，通过 Coordinator 下发命令
                    └────────────────┘
```

**两条铁律（作为代码审查项）：**

1. `Domain/` 目录下任何文件**不得**出现 `import AppKit` / `import SwiftUI` / `import CodexBar`。
2. `Overlay/GaugeLayerRenderer.swift` **不得**引用任何 `Data/CodexBar/*` 类型；它只吃 `QuotaWindow` / `QuotaSnapshot` 等 Domain 类型。

这两条是"Renderer 不 import CodexBar"要求的**可检查落地形式**。

### 1.3 相对上游计划的调整

| 上游 plan | 本设计 | 理由 |
|---|---|---|
| 目录树列 `UI/Settings/ProviderSetup/Diagnostics/Preview` 四个目录 | 合并为单个 `SettingsWindow` + 4 个 Tab | 单窗口 4 Tab 更简单；Preview 并入 Diagnostics |
| `Data/Fixtures/` 与 `Resources/PreviewFixtures/` 重复 | Fixture 只放 `Data/Fixtures/`（Swift 常量）；Resources 只放许可证 | 避免两处维护 |
| 未提 `LSUIElement` | 明确 `LSUIElement = true` | 菜单栏工具不应有 Dock 图标 |
| 未提 SkyLight 上架风险 | **默认不引入 SkyLight**；"全屏自动隐藏"降级为实验性开关 | 保留后期上架 App Store 的可能 |
| 部署目标 14+ 未解释 | 明确：覆盖层本身 macOS 12 即可，14 是 CodexBar 拖累 | 消除参考文档与 plan 的表面矛盾 |

---

## 2. 递归额度 Bar：几何与渲染

### 2.1 抽象轴（核心抽象）

所有布局归约到一个抽象轴，避免每种布局写一套百分比逻辑：

```
u = 0  → 锚点（notch 边缘 / 屏幕外缘，取决于锚点模式）
u = 1  → 该侧区域末端
screen_x = anchorX + u × sideLength × (growsTowardRight ? +1 : -1)
```

递归嵌套长度 = 累计乘积，纯函数、可单测、不碰 AppKit：

```swift
// windows 从最长 → 最短排列
func nestedLengths(trackWidth: CGFloat, remaining: [Double?]) -> [CGFloat] {
    var length = trackWidth
    return remaining.map { frac in
        guard let frac, frac.isFinite else { return .nan }  // 未知 → 断链
        length *= CGFloat(frac)
        return length
    }
}
```

**主方案**：后一个额度只占前一个额度的**剩余显示长度**，不按真实天数切格。

```
L_month = L × 0.80
L_week  = L_month × 0.60   = L × 0.48
L_5h    = L_week  × 0.25   = L × 0.12
```

从同一锚点绘制，**先画外层、后画内层**；只有周 + 5h 时不凭空补"月 100%"。

### 2.2 几何模型：track / fill 分离（沿用参考文档 §6.1）

```swift
struct GaugeGeometry {
    var trackRect: CGRect      // 底槽：永远横贯整屏，刘海模式下不裁
    var fillBounds: CGRect     // 本 Provider 可用区，止步于刘海边缘
    var growsTowardRight: Bool
    var fullBleed: Bool        // 高度铺满菜单栏、左右 inset=0、直角
}
```

**关键不变式（写进测试）：**

- 底槽跨整屏（哪怕 notch 双侧），否则刘海圆角处露壁纸
- 每个 Provider 的 fill 用独立 clip，不越界污染另一侧
- 无刘海屏退化：以屏幕中线分左右，`gap = 0`

### 2.3 布局模式

- `LayoutMode = single | dual`
- `AnchorMode = notch | outerEdge`（dual 使用）
- `SingleBarDirection = leadingToTrailing | trailingToLeading`（single 使用）
- single **不要求**设备有刘海

### 2.4 渲染器契约（依赖边界的落地）

```swift
protocol GaugeRendering {
    // 只吃 Domain 类型 + 纯几何 + 色板，返回 CALayer 树
    func render(windows: [QuotaWindow], geometry: GaugeGeometry,
                palette: ProviderPalette, baseline: BaselineSpec?) -> CALayer
}
```

`GaugeLayerRenderer` 实现此协议，**不知道 CodexBar 存在**。

### 2.5 配色（Provider 定色相，层级定明度）

```swift
struct ProviderPalette {
    var outer, middle, inner: RGBAColor   // 最长→最短窗口
    var track: RGBAColor                  // 底槽：黑色 ~35–40%（亮壁纸可读，非固定值）
    var baseline: RGBAColor
}
```

- Codex = 冷蓝/紫系；Claude Code = 暖陶土/橙系；颜色只是初值、主题可覆盖
- **橙色不代表错误**
- 额度告警 / Agent 状态 / Provider 身份使用**不同视觉通道**

### 2.6 基准线投影

```
markerLength = trackWidth × ∏(更外层实际 remainingFraction) × 选中窗口.expectedRemainingFraction
```

- Marker 必须与该侧方向一致，**不可永远用屏幕左侧 x 计算**
- 默认绑定最外层有效额度（通常 Weekly）
- `actualRemaining < expectedRemaining` = 消耗快于匀速；UI 用中性措辞（"超前消耗 / 仍有余量"）
- 无上游 pace 时，仅当可确定 `durationSeconds` + 可信 `resetAt` 才计算

### 2.7 边界情况（全部单测）

| 情况 | 行为 |
|---|---|
| 外层未知 | **断链**，显示缺失状态，绝不假设 100% |
| 外层 = 0 | 内层可见宽度也为 0，不虚构 |
| 内层 < 1px | 不改真实计算值；用**独立端帽层**表示"非零但过短" |
| 窗口数 > 3 | 用户选 ≤3 个有层级意义的窗口 |
| 数据过期/离线 | 中性底槽 + 离线提示，不伪装满额 |

### 2.8 每显示器配置模型

```swift
struct DisplayConfiguration: Codable, Sendable {
    var displayID: String          // 稳定 ID，非 NSScreen 索引
    var isEnabled: Bool
    var layout: LayoutMode
    var anchor: AnchorMode
    var singleDirection: SingleBarDirection
    var assignments: [SideAssignment]   // 每侧绑定的 provider + accountKey
}
```

每显示器独立配置**从 Day 1 进 Domain 模型**（即使 UI 初期只暴露主屏）。

### 2.9 信息密度

不在设计里预设密度上限。P1 用 Fixture 渲染全部状态，用户在真实菜单栏看到后拍板。诊断页显示"当前叠加几层/几个动画"作为**参考指标，非硬门禁**。

---

## 3. 数据引擎与 CLI 生命周期管理

### 3.1 核心抽象：引擎 ≠ 适配器

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

- **EngineManager**：只管发现 / 选择 / 安装 / 兼容性判断
- **Adapter（Decoder）**：只管把上游 JSON 解析并标准化成 Domain 模型
- 未来 HTTP / 用户脚本源实现同一协议，**Renderer 一行不改**

### 3.2 发现顺序

1. 用户手动指定路径
2. Homebrew：`/opt/homebrew/bin/codexbar`、`/usr/local/bin/codexbar`
3. `/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI`
4. App 专属：`~/Library/Application Support/<BundleID>/Engines/CodexBar/<ver>/CodexBarCLI`
5. 受控最小 PATH 解析（不依赖 Finder 环境）

**发现 ≠ 可用**：每个候选要解析 symlink、验可执行、读 `--version`、跑 schema 探测。必须区分：`CLI 不兼容` / `CLI 兼容但未登录` / `可用`。不用 `which` 作为唯一逻辑。

### 3.3 标准化规则

1. `usage.primary/secondary/tertiary` 是**位置字段不是周期名**；靠 `windowMinutes`（300=5h、10080=7d）或明确标签识别。**绝不默认 primary == monthly**。
2. `remainingFraction = (100 - usedPercent)/100`，仅当 `usedPercent` 是有限数且落在 0…100；异常标 invalid/unavailable，**不静默夹取**。
3. 只有上游明确标识的周期才建模为"月"。**没数据就没有月层。**
4. 原始错误 / 读失败 / 未登录 / 额度为 0 / Provider 不支持 —— **五种状态必须可区分**。
5. 新增 JSON 字段向前兼容；缺失必需字段时**隔离单 Provider 故障**，不清空其他 Provider。

### 3.4 进程执行安全

- `Process.executableURL` 用**已验证绝对路径**，`arguments` 数组化，**禁止 `sh -c` 拼接用户输入**
- 超时 / 终止 / 取消 / 并发去重；查询不阻塞主线程
- stdout 当 JSON、限最大长度；stderr 脱敏后只记短摘要，**错误不回显 Cookie/Token/账号标识**
- 隔离环境，只传必要变量；`CODEXBAR_CONFIG` 走用户选择的模式
- 刷新默认 3–5 分钟，可手动刷新；**禁止秒级轮询**

### 3.5 配置模式

- **模式 A（默认）**：沿用用户已有 CodexBar 配置，只读不改；要改共享配置**必须先确认**
- **模式 B**：App 独立 `CODEXBAR_CONFIG`；API Key 经 `--stdin` 输入，不落命令行/日志；目录 `0700`、文件 `0600`
- **明确不声称**：填 API Key 就能读 ChatGPT Plus / Claude Code 订阅额度（API 用量 ≠ 订阅额度）

### 3.6 关键取舍：App Store 与"运行时下载 CLI"的冲突

App Store 沙盒**禁止运行时下载并执行可执行文件**，而"托管安装 CodexBar CLI"正是此行为。设计为**编译期可切换的双模式**：

```swift
enum DistributionProfile {
    case github          // 全功能：可下载/安装/管理托管 CLI
    case appStore        // 禁用托管安装；仅使用用户已安装的外部 CLI
}
```

- `github` 模式（当前）：托管安装全开
- `appStore` 模式：Engine 设置页只显示"检测到的外部 CLI"，托管安装按钮隐藏，附引导"请自行安装 CodexBar"
- 通过**编译条件 + 运行时能力探测**双重实现，保证上架版本符号表干净
- 后期切 App Store 时**不重写 EngineManager**，只关闭一个能力

### 3.7 缓存与重置检测

- 按 `providerId + accountKey + windowId` 缓存最后有效快照 + `fetchedAt` + stale 阈值
- 初次离线：只能显示上次状态并标"已过期"，或只显示底槽；**缓存绝不冒充实时**
- 突增额度：未二次确认只标"可能重置/数据变化"，**不断言官方赠送**
- `resetAt` 变更 → 立即重算基准线，不固化上个周期

---

## 4. Agent 状态桥接

### 4.1 与额度引擎彻底分离

- **Quota**：分钟级主动抓取，百分比 + 重置时间
- **Agent**：事件驱动、低延迟、Session 状态
- 两者独立运行，只在 **Presentation 层**按 `providerId` + account/session 映射汇合

### 4.2 进程内 Unix Domain Socket 接收

```swift
protocol AgentEventAdapter: Sendable {
    func adapt(raw: AgentRawEvent) -> AgentEvent?
}
struct AgentEvent: Sendable {
    let providerId: String
    let sessionId: String
    let kind: AgentEventKind      // 白名单
    let at: Date
    // 绝不包含 prompt / 命令 / 回复正文
}
```

Socket 路径 `~/Library/Application Support/<BundleID>/agent.sock`，仅本用户可读写（`0600`）。

### 4.3 Hook 安装的安全设计（最高风险项）

修改 `~/.claude/settings.json` 的 Hook 必须：

1. **先预览后安装**：展示"将要插入的 Hook 配置 diff"，用户确认才写
2. **保留字节的最小插入**：解析 → 只增不改 → 序列化时尊重原格式与已有 hooks
3. **改前备份**：写 `settings.json.bak.<timestamp>`
4. **卸载只清理自己装的条目**：通过唯一标记（如 command 带 `--managed-by=<bundleid>`）识别
5. **不默认安装**：App 首次启动**绝不**动用户配置，必须用户主动点"启用 Agent 检测"

### 4.4 状态机与可信度

- Reducer 按 `sessionId` 处理**乱序 / 重复 / 重连 / 退出**，维护 `AgentConfidence`
- **禁止**用 CPU 活跃度或长时间无事件推断"已完成/空闲"——无法确认时用 `unknown/reconnecting`
- 能力矩阵**按宿主区分**：

| 宿主 | running | waitingApproval | waitingInput |
|---|---|---|---|
| Claude Code CLI | ✅ | ✅ | ✅ |
| Codex CLI | ✅ | ✅（可识别时） | ❌ → `unknown` |
| Codex VS Code | 未验证 | 未验证 | 未验证 |

**不把 CLI 结果推广到所有宿主。** Codex 无法判断等待普通输入时显示 `unknown`，**不强行亮橙灯**。

### 4.5 动效语言

| 状态 | 视觉 | 备注 |
|---|---|---|
| idle | 静态 | 不额外耗电 |
| running | 沿填充方向缓慢 shimmer | 1 个共享动画，拒绝逐帧重绘 |
| waitingInput | 小端点 + 温和双脉冲 | 必须真实可观察 |
| waitingApproval | 提示点 + 更明确脉冲 | 与一般等待区分 |
| completed | 一次短促亮度扫过（~1s）后复原 | 瞬态，不长期常亮 |
| error | 小端点/边缘告警 | 不把整条 Bar 换红 |
| unknown/reconnecting | 中性静态 | 不假装 idle |

多 Session 聚合优先级：`error > waitingApproval > waitingInput > running > completed > idle`；**未知会话数单独显示，绝不被忽略为已完成**。支持 `Reduce Motion`、低电量暂停、完全关闭动效（关闭后仍能靠小端点区分需处理状态）。

### 4.6 与"多显示器 / 多 Agent"的衔接

`AgentActivityAggregator` 按 **display** 聚合；每个 display 配置可指定关注哪些 provider/agent 的会话。V1 聚合到"每侧一个主状态动画"，数据结构预留**多 Agent 并列**扩展位。

### 4.7 降级与"全屏自动隐藏"的诚实处理

识别全屏 Space 需私有 SkyLight（参考文档 §11.3）。为保留上架可能：

- **默认不引入 SkyLight**
- 全屏处理降级为：设置里提供 **"全屏时隐藏（实验性）"开关**（基于公开 API 尽力探测）+ **手动隐藏**
- UI 中**明确标注"可能不准确"**，**不假称能准确识别全屏**

---

## 5. 设置 / 诊断 / 预览 UI

### 5.1 入口结构

- **`NSStatusItem`**：极窄图标，默认显示，设置里可隐藏
- **设置窗口**：SwiftUI，4 个 Tab，`Settings { }` scene
- 首次启动：若未配置过，自动弹一次设置窗口

```
SettingsWindow
 ├─ Providers  (发现列表 / 启停显示 / 账户 / Test Connection)
 ├─ Engine     (外部 CLI 路径版本 / 托管 CLI / 重检 / 安装 / 切换来源)
 ├─ Appearance (single|dual / 锚点 / 方向 / 色板 / 基准线 / Agent 动效 / 每显示器配置)
 └─ Diagnostics(几何实测值 / Overlay 窗口数 / CLI 状态 / Hook 状态 / 脱敏复制)
```

### 5.2 Providers Tab

- 列表：Codex、Claude Code，及 CodexBar 返回的其他 Provider
- 每项：启用/禁用显示、当前来源、登录状态、上次成功更新时间、支持的窗口、`Test Connection`
- API Key 模式**仅在上游明确支持时**显示输入框；不回显明文
- 共享配置 vs App 独立配置**必须显著说明**；改共享配置前先确认
- 多账号底层支持，**首版每侧只选一个账户快照，不暗中混合**

### 5.3 Engine Tab

- 显示：外部 CLI 路径/版本、托管 CLI 路径/版本、兼容性、优先选择、**脱敏**检测日志
- 按钮：重新检测 / 安装托管 / 更新托管 / 切换来源 / 卸载托管
- **只有用户明确点击才下载可执行文件**；进度可见；安装前说明许可、大小、来源
- 若切到 `appStore` 模式：隐藏托管安装按钮，只显示检测到的外部 CLI

### 5.4 Appearance Tab

- `single / dual`；dual 各侧可选 Provider + 账户
- `notch / outerEdge`（dual）；`leadingToTrailing / trailingToLeading`（single）
- 品牌色板 + 亮度/不透明度、轨道色、基准线开关与样式
- 嵌套窗口顺序与启用选择（**不违反周期语义**，默认 周 → 5h）
- Agent 动效开关 / 强度 / Reduce Motion / 低功耗暂停
- **每显示器启用与独立配置**
- 全屏/自动隐藏场景配置（含"实验性"标注）、开机自启

### 5.5 Diagnostics Tab

- 显示：窗口服务器测得高度、刘海矩形、显示器 scale、Overlay 窗口数量、CLI 路径/版本、上次查询状态、Hook 安装状态
- **脱敏**复制诊断信息按钮（不含 Token / 账号 / 对话）

### 5.6 Preview —— 用真实渲染器

- Fixture：`full / weekLow / sessionLow / allZero / missing / stale / reset / agentRunning / agentWaiting / notchless`
- 无需登录任何 Provider 即可预览
- 单侧/双侧/方向可即时切换
- **落地方式**：预览用**独立的预览用 `MenuBarBandWindow`**（复用同一渲染器），而非在 SwiftUI 里重画 —— 保证"预览所见 = 菜单栏实际所见"

### 5.7 点击穿透与设置入口

覆盖层 `ignoresMouseEvents = true`，**不能**把点击加到全宽背景。入口只能是：`NSStatusItem`（默认）/ 快捷键 / Dock（若显示）。

---

## 6. P0–P4 硬门禁与验收标准

每个阶段有：可运行产物、硬门禁（不通过不进下一阶段）、验收标准。**性能只记录实测值，不设通过线。**

### P0 — 可行性 Spike（阻塞一切）

| 项 | 内容 |
|---|---|
| 产物 | 最小 App：真实菜单栏后画静态色条 |
| 硬门禁 | ① 透明窗口 `desktopIconWindow+1` **不挡系统图标、不拦点击** ② 窗口服务器读到**内屏+外屏**菜单栏高度，无刘海退化可用 ③ 检出真实 CodexBar CLI 并跑通 `--version` + `usage --provider codex --format json`，保存**脱敏 Fixture** ④ 摸清 CodeStatus 复用边界 + Codex/Claude 真实事件能力 |
| 验收 | 真实可见原型 + 可执行 schema 测试 + Agent 能力报告；**非 macOS 缺项标 `BLOCKED`** |
| 文档 | `docs/architecture.md`、`docs/implementation-progress.md` |

**P0 结论先给用户看，再决定 P1 是否照原样走。**

### P1 — Domain / Renderer / Mock（核心演示版）

| 项 | 内容 |
|---|---|
| 产物 | 无 CodexBar/Agent 也能启动、操作、在真实菜单栏看到所有模拟状态 |
| 硬门禁 | ① 递归长度 `[0.8,0.6,0.25]→[0.8,0.48,0.12]×L` 单测通过 ② single/dual × notch/outerEdge × 双向 全正确 ③ 无刘海退化正确 ④ Fixture 走**真实渲染器** ⑤ 五秒看门狗 + 生命周期事件到位 |
| 验收 | 用户亲眼确认各状态渲染效果后**拍板信息密度** |

### P2 — 真实额度接入与 CLI 管理

| 项 | 内容 |
|---|---|
| 产物 | 至少一个已登录 Provider 的真实额度显示在菜单栏 |
| 硬门禁 | ① 外部 CLI 存在→不下载不覆盖 ② 无 CLI→用户确认后可装，装坏可回滚 ③ 未登录→引导设置而非重装 CLI ④ 绝不凭空造月额度 ⑤ 异常数据（NaN/超范围）不静默夹取 |
| 验收 | 至少两家 Provider 真实额度场景跑通；Fixture/EngineManager 测试通过 |

### P3 — Agent 桥接与动效

| 项 | 内容 |
|---|---|
| 产物 | Claude Code 的 running/waiting 事件在菜单栏产生真实可观察动效 |
| 硬门禁 | ① Hook 安装**预览+确认+备份+可卸载**，不破坏用户原配置 ② 无对话正文写盘 ③ 乱序/重复/重连不误判为完成 ④ Codex 不支持的细分状态标 `unknown` ⑤ 双 Provider 同时运行互不干扰 |
| 验收 | Claude 真实事件可观察；Codex 正确降级不作虚假承诺 |

### P4 — 发布收尾

| 项 | 内容 |
|---|---|
| 产物 | 可运行 `.app`（Developer ID 签名+公证，若签名环境可用） |
| 硬门禁 | ① 多屏/Space/锁屏/睡眠唤醒验证 ② 性能**实测记录**（CPU/内存/Energy，非杜撰门槛）③ 关闭动效时低负载 ④ README/`NOTICE`/隐私声明齐全 |
| 验收 | P0–P3 均有可核查代码+测试；未验证硬件/系统在 release checklist 明确列出 |

### 完成定义（DoD）

1. App 在真实菜单栏背景显示**一条连续嵌套 Bar**；双侧/单条可切换，两方向正确
2. Codex/Claude 可分别绑定不同侧，颜色与渲染独立；无刘海设备仍可用
3. 周和 5h 用真实数据按**递归乘法**绘制；缺月额度绝不假造
4. 基准线取可信 pace/周期信息，动态跟随更新与重置；不按固定四周/30 天代替
5. 发现已有 CLI 直接复用；未找到可由用户确认安装；安装不破坏系统已有 CodexBar
6. 用户可在 App 内选择 Provider、管理显示与接入方式；上游支持的 API Key 可安全输入
7. 至少 Claude Code 的运行/等待事件被真实接入；Agent 动效与额度独立，未知不冒充完成
8. 多屏/Space/窗口丢失恢复机制到位；不阻挡菜单栏点击；关动效时低负载
9. 有单元测试、Fixture、实机验证记录、第三方许可与上游版本记录
10. 不默认上传遥测，不采集对话正文，不静默安装 Hook/CLI，不引入私有 SkyLight

### 执行协议（用户自己分步实现）

每阶段结束产出固定格式：**① 完成项 ② 关键源码路径 ③ 实际构建/测试命令与结果 ④ 真实数据接入结论 ⑤ Agent 能力与限制 ⑥ 实机测试与未测项 ⑦ 上游版本/许可 ⑧ 已知问题/下版优先级 ⑨ App 路径**。

---

## 7. 测试策略（跨阶段）

### 7.1 纯逻辑单元测试

- `[0.8,0.6,0.25] → [0.8,0.48,0.12] × trackWidth`
- `[0.6,0.25] → [0.6,0.15] × trackWidth`
- 输入为 0 / 1 / 未知 / NaN / 无穷 / 缺窗口 / 未排序 → 明确结果
- 外层不存在不补 100%；单窗口渲染正确
- notch/outerEdge 在左右镜像下长度相等、方向对称；single 反向正确
- 基准线实际/预期关系正确；选 inner 时带外层乘积
- `resetAt` 更新 / 突增 / 过期 → 不产生虚假月额度或误判重置

### 7.2 JSON Fixture 合同测试

- 按**实际固定版本**采集脱敏 Fixture，至少 Codex / Claude / 一项 API Key Provider
- primary/secondary 颠倒、tertiary 新增、缺 `windowMinutes`、空数组、错误响应、混合成功失败、增字段 → 互不破坏
- `pace.expectedUsedPercent` 存在/缺失；不同账户独立
- Decoder 不依赖真实 CLI/网络/Keychain 即可测试

### 7.3 EngineManager 测试

- 外部兼容 CLI：不下载不覆盖
- 外部版本不兼容：提示托管/手动选择，不误报"未安装"
- symlink 断链 / 无执行权限 / 启动失败 / 超时 / 输出畸形 / 架构不匹配
- 下载网络错误 / 校验失败 / 磁盘不足：回滚，旧版本继续工作
- CLI 存在但未登录：引导 Provider 设置，不触发重装
- 改共享配置必须确认；App 独立 config 不覆盖共享

### 7.4 Agent 测试

- 乱序/重复/退出/重连，不把过期事件变成完成
- 2 running + 1 waitingApproval → 聚合为 waitingApproval，详情数正确
- Claude Input/Approval 与 Codex 无法确认 Input 的区别；未知不算 idle
- Hook 安装/卸载不破坏用户原配置；非阻塞，无对话文本写盘
- 无 Hook 时仅显示 `unavailable/unknown`，不显示虚假运行动画

### 7.5 macOS 实机测试清单

- macOS 14/15/26/27（能得到的设备就记录，**未验证明确标注**）
- 内置刘海屏 / 无刘海外接屏 / 双屏热插拔 / 镜像屏 / 缩放 Retina
- 菜单栏浅色/深色/壁纸明暗、图标可读、自动隐藏
- Space 切换 / Mission Control / 全屏 / 锁屏解锁 / 睡眠唤醒
- 快速修改滑块/方向，不出现旧渲染覆盖新状态
- 看门狗模拟窗口被移出前台，不频繁闪烁
- 未装 CodexBar / 已有 CLI / App 内置 CLI / 非兼容版本
- 真实 Codex 与 Claude Code 各至少一条 Provider 成功取额度；真实 Hook 产生状态切换

---

## 8. 参考

- 上游计划：`docs/AI-Menubar-Quota-Agent-V1-Codex-Plan.md`
- 绘制依据：`docs/reference/menubar-overlay-technical-notes.md`
- CodexBar：https://github.com/steipete/CodexBar
- CodexBar CLI 文档：https://github.com/steipete/CodexBar/blob/main/docs/cli.md
- CodexBar CLI 配置：https://github.com/steipete/CodexBar/blob/main/docs/cli-configuration.md
- CodexBar Releases：https://github.com/steipete/CodexBar/releases
- CodeStatus：https://github.com/henriquegpb/codestatus

**注意**：外部项目文档与二进制会更新。实施时固定已验证 tag/commit，保存协议 Fixture 与兼容性记录，不把网页示例版本号当作最新可用版本。
