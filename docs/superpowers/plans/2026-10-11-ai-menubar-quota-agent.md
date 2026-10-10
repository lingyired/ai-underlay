# AI Menu Bar Overlay V1 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 macOS 菜单栏背景中绘制一条递归嵌套的 AI 额度 Bar，叠加 Agent 运行状态，并管理 CodexBar CLI 数据源与 Hook 接入。

**Architecture:** 单进程 `LSUIElement` App（方案 A）。严格分层 `Domain ← Data / Agent / Overlay / UI`，Domain 零外部依赖，Renderer 不 import 数据源类型。额度引擎与 Agent 事件独立运行，仅在 Presentation 层汇合。全部走公开 API，不引入私有 SkyLight。

**Tech Stack:** Swift 6（严格并发）、AppKit + Core Animation（覆盖层绘制）、SwiftUI（设置）、XCTest/Swift Testing（测试）、外部 `CodexBarCLI`（额度数据）、Unix Domain Socket（Agent Hook）。

**Spec:** `docs/superpowers/specs/2026-10-11-ai-menubar-quota-agent-design.md`

## Global Constraints

- 部署目标 **macOS 14.0**；Swift 6，开启严格并发检查。
- App 为 `LSUIElement = true`（无 Dock 图标）；设置入口为 `NSStatusItem`（默认显示、可隐藏）。
- `Domain/` 下任何文件**不得** `import AppKit` / `import SwiftUI` / `import CodexBar`。
- `Overlay/GaugeLayerRenderer.swift` **不得**引用 `Data/CodexBar/*` 类型。
- 覆盖层窗口层级 = `CGWindowLevelForKey(.desktopIconWindow) + 1`；**禁止**写死 `24`，菜单栏层级用 `CGWindowLevelForKey(.mainMenuWindow)`。
- 覆盖层窗口 `ignoresMouseEvents = true`，**不得**拦截菜单栏点击。
- `remainingFraction` 的 `nil` **绝不**当 `0`；未知外层**绝不**假设 100%。
- **绝不**凭空创建"月额度"；只有上游明确标识的周期才建模。
- 进程调用 `Process` 时**禁止** `sh -c` 拼接用户输入；用已验证绝对路径 + 数组参数。
- **禁止**秒级轮询 CLI（默认 3–5 分钟）；**禁止**采集/落盘对话正文、Prompt、Token。
- **禁止**未经用户确认修改 `~/.claude/settings.json`、CodexBar 共享配置；**禁止**静默安装 Hook/CLI。
- **禁止**引入私有 SkyLight 符号；全屏识别降级为实验性开关并标注"可能不准确"。
- 基准线口径：`expectedRemaining = 1 - expectedUsedPercent/100`；无上游 pace 时 `expectedRemaining = 1 - clamp((now-periodStart)/duration, 0, 1)`。

## Review Focus

（spec 隐含但任何单测都没覆盖、最可能坑到使用者的输入类/失败模式，每行一个；每行的测试挂到拥有该代码的任务里。）

1. **上游 `usedPercent` 越界或 NaN** → 期望标记 `unavailable/invalid` 且**不静默夹取到 0/100**（Task P2-3）。
2. **`usage.primary/secondary` 位置颠倒** → 期望按 `windowMinutes` 识别周期，**不把 primary 当 monthly**（Task P2-3）。
3. **递归链外层为 nil（缺失）** → 期望**断链**并显示缺失，**不补 100%**（Task P1-3）。
4. **Hook 事件乱序/重复到达** → 期望 Reducer 不把过期事件翻成 `completed`（Task P3-3）。
5. **窗口被系统静默丢弃（`isVisible` 仍为 true）** → 期望看门狗按窗口服务器计数补位且**不频繁闪烁**（Task P1-6）。

---

## 文件结构（File Structure）

```text
AIUnderlay/
├── AIUnderlayApp.swift                 # @main, LSUIElement, AppCoordinator 装配
├── Info.plist                          # LSUIElement=true
├── Application/
│   ├── AppCoordinator.swift            # 启动编排：Overlay/Engine/Agent/StatusItem
│   └── SettingsStore.swift             # Codable 配置持久化（非机密）
├── Domain/                             # 零外部依赖
│   ├── QuotaWindow.swift               # QuotaWindow, QuotaWindowKind, DataAvailability
│   ├── ProviderQuotaSnapshot.swift
│   ├── AgentSession.swift              # AgentSession, AgentState, AgentConfidence
│   ├── NestedGauge.swift               # nestedLengths 纯函数
│   ├── GaugeGeometry.swift             # trackRect/fillBounds 分离 + 轴变换
│   ├── QuotaPace.swift                 # 基准线 expectedRemaining 计算
│   └── DisplayConfiguration.swift      # 每显示器配置模型
├── Data/
│   ├── QuotaEngine.swift               # QuotaEngine / ManagedQuotaEngine 协议
│   ├── QuotaEngineManager.swift        # 发现/选择/安装/兼容性
│   ├── QuotaRefreshScheduler.swift     # 分钟级刷新 + 手动刷新
│   ├── SnapshotCache.swift             # provider+account+window 缓存 + stale
│   ├── Fixtures/FixtureSnapshots.swift # full/weekLow/... 状态
│   └── CodexBar/
│       ├── CLIInventory.swift          # 发现顺序 + 候选验证
│       ├── CodexBarCLIClient.swift     # Process 调用（绝对路径/超时/脱敏）
│       ├── CodexBarInstaller.swift     # 托管安装/更新/卸载 + 校验回滚
│       └── CodexBarUsageDecoder.swift  # JSON → Domain（windowMinutes 识别）
├── Agent/
│   ├── AgentEvent.swift                # AgentEvent, AgentEventKind（白名单）
│   ├── AgentEventReceiver.swift        # Unix Domain Socket 服务
│   ├── AgentSessionReducer.swift       # 乱序/重复/重连/退出
│   ├── HookSetupCoordinator.swift      # 预览+确认+备份+最小插入+可卸载
│   └── AgentActivityAggregator.swift   # 按 display 聚合优先级
├── Overlay/
│   ├── MenuBarBandWindow.swift         # NSWindow 子类
│   ├── MenuBarGeometry.swift           # 窗口服务器读高度 + 刘海 + 坐标翻转
│   ├── BandWatchdog.swift              # 5 秒计数补位（纯函数 needsReassert）
│   ├── MenuBarOverlayController.swift  # 每屏一窗 + 生命周期
│   ├── GaugeLayerRenderer.swift        # CALayer 树（唯一渲染器）
│   ├── BaselineMarkerLayer.swift       # 基准线层
│   ├── AgentEffectLayer.swift          # Agent 动效层
│   └── ThemePalette.swift              # ProviderPalette
├── UI/
│   ├── SettingsWindow.swift            # 4 Tab 容器
│   ├── ProvidersTab.swift
│   ├── EngineTab.swift
│   ├── AppearanceTab.swift
│   ├── DiagnosticsTab.swift
│   └── StatusItemController.swift      # NSStatusItem 入口
└── Resources/
    └── Licenses/                       # NOTICE 等

AIUnderlayTests/
├── DomainTests/NestedGaugeTests.swift
├── DomainTests/GaugeGeometryTests.swift
├── DomainTests/QuotaPaceTests.swift
├── DataTests/CodexBarUsageDecoderTests.swift
├── DataTests/QuotaEngineManagerTests.swift
├── AgentTests/AgentSessionReducerTests.swift
├── OverlayTests/BandWatchdogTests.swift
└── Fixtures/*.json                     # 脱敏真实输出

docs/
├── architecture.md
├── implementation-progress.md
├── privacy-and-permissions.md
└── release-checklist.md
```

**依赖方向（每次提交都要守住）：** `Domain ← Data / Agent / Overlay / UI`。

---

# P0 — 可行性 Spike（阻塞一切，先做）

> **P0 门禁**：① 透明窗口不挡菜单栏图标、不拦点击 ② 窗口服务器读到内屏+外屏菜单栏高度 ③ 检出真实 CodexBar CLI 并跑通 `usage --provider codex --format json`，保存脱敏 Fixture ④ Agent 能力报告。
> **P0 完成后必须先给用户看结论，再决定 P1 是否照原样走。**

### Task P0-1: 工程骨架与可运行 App

**Files:**
- Create: `AIUnderlay/AIUnderlayApp.swift`
- Create: `AIUnderlay/Info.plist`
- Create: `AIUnderlay.xcodeproj`（Xcode GUI 或 `xcodegen`/`tuist`，二选一）
- Create: `docs/architecture.md`, `docs/implementation-progress.md`
- Test: `AIUnderlayTests/SmokeTests.swift`

**Interfaces:**
- Produces: 可 `⌘R` 运行的 `AIUnderlay.app`（LSUIElement，无 Dock 图标）；`AppCoordinator` 类型占位。

- [ ] **Step 1: 创建 Xcode 工程**，target `AIUnderlay`（macOS App，Swift，无 Storyboard），部署目标 `14.0`，测试 target `AIUnderlayTests`。
- [ ] **Step 2: 在 `Info.plist` 设置 `LSUIElement = true`**，在 `AIUnderlayApp.swift` 写最小 `@main`：

```swift
@main
struct AIUnderlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 3: 写冒烟测试**

```swift
import XCTest
final class SmokeTests: XCTestCase {
    func test_bundle_isAccessory() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? String, "true")
    }
}
```

- [ ] **Step 4: 构建并运行测试**

Run: `xcodebuild -scheme AIUnderlay -destination 'platform=macOS' test`
Expected: PASS，且运行 App 后 **Dock 无图标**。

- [ ] **Step 5: 记录环境**到 `docs/architecture.md`（macOS 版本、Xcode、Swift 版本、机型、显示器）。

- [ ] **Step 6: Commit**

```bash
git add AIUnderlay AIUnderlay.xcodeproj AIUnderlayTests docs
git commit -m "chore(P0): scaffold LSUIElement app skeleton"
```

---

### Task P0-2: 穿透覆盖窗口 + 静态色条（验证层级与点击穿透）

**Files:**
- Create: `AIUnderlay/Overlay/MenuBarBandWindow.swift`
- Create: `AIUnderlay/Overlay/MenuBarOverlayController.swift`（P0 仅单屏静态版本）
- Modify: `AIUnderlay/AIUnderlayApp.swift`（启动时显示色条）
- Test: `AIUnderlayTests/OverlayTests/BandWindowLevelTests.swift`

**Interfaces:**
- Consumes: 无。
- Produces: `MenuBarBandWindow`（`level = desktopIconWindow + 1`）、`MenuBarOverlayController.showStaticBand()`。

- [ ] **Step 1: 写失败测试**（断言层级公式，不依赖屏幕）

```swift
func test_bandLevel_isDesktopIconPlusOne() {
    let expected = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    XCTAssertEqual(MenuBarBandWindow.bandLevelRawValue, expected)
}
```

- [ ] **Step 2: 运行确认失败**：`xcodebuild ... test -only-testing:AIUnderlayTests/BandWindowLevelTests` → FAIL（未定义）。
- [ ] **Step 3: 实现 `MenuBarBandWindow`**（照 spec §2 / 参考文档 §2）：`isOpaque=false`、`backgroundColor=.clear`、`hasShadow=false`、`ignoresMouseEvents=true`、`isMovable=false`、`animationBehavior=.none`、`collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle]`，`level` 用相对值；暴露 `static var bandLevelRawValue: Int`。
- [ ] **Step 4: 实现单屏静态色条**：`MenuBarOverlayController` 取主屏 `NSScreen.main`，`setFrame` 到屏幕顶边一条（高度先临时用 `NSStatusBar.system.thickness`），加一个 35% 黑 `CALayer` + 一个品牌色 `CALayer`。
- [ ] **Step 5: 运行测试**：`xcodebuild ... test` → PASS。
- [ ] **Step 6: 人工验证（写进 progress 文档）**：运行 App → 色条出现在菜单栏后方；**菜单栏图标/文字仍在上层可见**；**点击菜单栏图标仍能弹出系统菜单**；`Cmd+Tab` 无该 App。
- [ ] **Step 7: Commit**

```bash
git add AIUnderlay/Overlay AIUnderlay/AIUnderlayApp.swift AIUnderlayTests/OverlayTests
git commit -m "feat(P0): click-through band window renders static color bar"
```

---

### Task P0-3: 菜单栏几何（窗口服务器高度 + 刘海 + 坐标翻转）

**Files:**
- Create: `AIUnderlay/Overlay/MenuBarGeometry.swift`
- Test: `AIUnderlayTests/OverlayTests/MenuBarGeometryTests.swift`

**Interfaces:**
- Produces:
  - `MenuBarGeometry.onScreenMenuBarBounds() -> [CGRect]`
  - `MenuBarGeometry.menuBarHeight(forQuartzFrame:menuBarWindowBounds:) -> CGFloat?`
  - `MenuBarGeometry.quartzFrame(for:primaryMaxY:) -> CGRect`
  - `MenuBarGeometry.notchEdges(for screen: NSScreen) -> (left: CGFloat, right: CGFloat)?`

- [ ] **Step 1: 写纯函数失败测试**（注入假 bounds，不依赖真实屏幕）

```swift
func test_height_matchesByXAndWidth() {
    let quartz = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let bars = [CGRect(x: 0, y: 0, width: 1728, height: 33),
                CGRect(x: 2048, y: 0, width: 2560, height: 30)]
    XCTAssertEqual(MenuBarGeometry.menuBarHeight(forQuartzFrame: quartz, menuBarWindowBounds: bars), 33)
}
func test_height_nilWhenNoMatch() {
    XCTAssertNil(MenuBarGeometry.menuBarHeight(forQuartzFrame: .init(x: 9, y: 0, width: 1, height: 1), menuBarWindowBounds: []))
}
func test_height_floorIs24() {
    let bars = [CGRect(x: 0, y: 0, width: 100, height: 3)]
    XCTAssertEqual(MenuBarGeometry.menuBarHeight(forQuartzFrame: .init(x: 0, y: 0, width: 100, height: 10), menuBarWindowBounds: bars), 24)
}
func test_quartzFrame_flipsY() {
    let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)   // AppKit
    XCTAssertEqual(MenuBarGeometry.quartzFrame(for: display, primaryMaxY: 1117).minY, 0)
}
func test_notchEdges_nilWhenNoGap() { /* 注入无刘海 screen 或直接测纯计算分支 */ }
```

- [ ] **Step 2: 运行确认失败**。
- [ ] **Step 3: 实现**（照参考文档 §3）：`CGWindowListCopyWindowInfo([.optionOnScreenOnly])` 过滤 `layer == CGWindowLevelForKey(.mainMenuWindow)`，`max(height, 24)` 兜底；`notchEdges` 用 `auxiliaryTopLeftArea/RightArea` 且 `right.minX > left.maxX` 才返回。加 **500ms 缓存**（`NSLock` + `nonisolated(unsafe)`）。
- [ ] **Step 4: 运行测试** → PASS。
- [ ] **Step 5: 实机验证**：把 `MenuBarOverlayController` 高度改为 `MenuBarGeometry` 实测值；**在内屏与外接屏各跑一次**，记录两屏实测高度到 `docs/implementation-progress.md`；无刘海外接屏 `notchEdges == nil`。
- [ ] **Step 6: Commit**

```bash
git add AIUnderlay/Overlay/MenuBarGeometry.swift AIUnderlayTests/OverlayTests/MenuBarGeometryTests.swift
git commit -m "feat(P0): query window server for real menu bar height and notch"
```

---

### Task P0-4: CodexBar CLI 探测 + 真实 JSON Fixture

**Files:**
- Create: `AIUnderlay/Data/CodexBar/CLIInventory.swift`
- Create: `AIUnderlay/Data/CodexBar/CodexBarCLIClient.swift`
- Create: `AIUnderlayTests/Fixtures/codex-usage.json`（脱敏）
- Create: `AIUnderlayTests/Fixtures/claude-usage.json`（脱敏）
- Test: `AIUnderlayTests/DataTests/CLIInventoryTests.swift`

**Interfaces:**
- Produces:
  - `CLIInventory.discover() -> [CLICandidate]`，`CLICandidate { url: URL, version: String?, compatibility: Compatibility }`
  - `CodexBarCLIClient.run(executable: URL, args: [String], timeout: TimeInterval) async throws -> Data`
  - `enum Compatibility { case compatible, incompatible, notLoggedIn }`

- [ ] **Step 1: 写测试**（对**已存在或不存在**两种情况都断言，不依赖真实 CLI 内容）

```swift
func test_discover_doesNotUseWhichAlone() { /* 断言返回候选都经过 isExecutableFile 校验 */ }
func test_run_rejectsNonAbsolutePath() {
    XCTAssertThrowsError(try CodexBarCLIClient.validate(executable: URL(fileURLWithPath: "codexbar")))
}
func test_run_enforcesTimeout() async { /* 用 /bin/sleep 10，超时 0.2s，期望抛 timeout */ }
```

- [ ] **Step 2: 运行确认失败**。
- [ ] **Step 3: 实现 `CLIInventory`**（照 spec §3.2 发现顺序）：手动路径 → Homebrew → `/Applications/CodexBar.app/Contents/Helpers/` → App 专属目录 → 受控最小 PATH；每个候选 `resolvingSymlinksInPath()` + `isExecutableFile` + 跑 `--version`；**区分** `incompatible`（版本/输出不符）与 `notLoggedIn`（`usage` 返回未登录错误码）。
- [ ] **Step 4: 实现 `CodexBarCLIClient`**：`Process.executableURL` 绝对路径、`arguments` 数组、`Pipe` 收集、超时 `terminate()`、stdout 限长、stderr **脱敏**（正则抹掉疑似 token/email 再记摘要）。
- [ ] **Step 5: 运行测试** → PASS。
- [ ] **Step 6: 采集真实 Fixture**：在本机（若有 CodexBar CLI）运行 `codexbar usage --provider codex --format json --pretty` 与 claude，**手工脱敏**（删除邮箱/账号/token 字段）后存为 Fixture；无 CLI 时用官方文档示例结构并标注"未实采"。
- [ ] **Step 7: Commit**

```bash
git add AIUnderlay/Data/CodexBar AIUnderlayTests/DataTests AIUnderlayTests/Fixtures
git commit -m "feat(P0): detect CodexBar CLI and capture desensitized fixtures"
```

---

### Task P0-5: Agent 能力验证报告（CodeStatus 复用边界）

**Files:**
- Create: `docs/agent-capability-report.md`
- Create: `AIUnderlay/Agent/AgentEvent.swift`（仅定义类型，无实现）

**Interfaces:**
- Produces: `AgentEventKind`（白名单枚举）、`AgentEvent`、`AgentState`、`AgentConfidence`（供 P3 使用）。

- [ ] **Step 1: 阅读 CodeStatus 源码与 README 能力矩阵**，记录 commit/tag 与许可证（MIT）。
- [ ] **Step 2: 写报告** `docs/agent-capability-report.md`，逐宿主列能力：

| 宿主 | running | waitingApproval | waitingInput | 依据 |
|---|---|---|---|---|
| Claude Code CLI | ? | ? | ? | 实测/文档 |
| Codex CLI | ? | ? | ? | 实测/文档 |
| Codex VS Code | 未验证 | 未验证 | 未验证 | — |

必须明确写出**"哪些状态能准确监控、哪些必须降级为 unknown"**，并给出**是否可复用 CodeStatus 代码**的结论（可复用则记录待移植的最小边界）。
- [ ] **Step 3: 定义 `AgentEventKind` 白名单枚举**（`sessionStart/sessionStop/preToolUse/notification/...`），**不含**任何正文承载字段。
- [ ] **Step 4: 编译通过**：`xcodebuild ... build` → 成功。
- [ ] **Step 5: Commit**

```bash
git add AIUnderlay/Agent/AgentEvent.swift docs/agent-capability-report.md
git commit -m "docs(P0): agent capability report and event whitelist types"
```

> **P0 结束 → 停下，向用户汇报 P0 结论（原型截图/录屏 + 实测高度 + 能力报告），确认后再进 P1。**

---

# P1 — Domain / Renderer / Mock（核心演示版）

> **P1 门禁**：① `[0.8,0.6,0.25]→[0.8,0.48,0.12]×L` 单测通过 ② single/dual × notch/outerEdge × 双向全对 ③ 无刘海退化正确 ④ Fixture 走**真实渲染器** ⑤ 五秒看门狗 + 生命周期到位。
> **P1 结束 → 用户亲眼确认渲染效果后拍板信息密度。**

### Task P1-1: Domain 基础模型

**Files:** Create `Domain/QuotaWindow.swift`, `Domain/ProviderQuotaSnapshot.swift`, `Domain/AgentSession.swift`, `Domain/DisplayConfiguration.swift`；Test `DomainTests/DomainModelTests.swift`

**Interfaces:**
- Produces: `DataAvailability`, `QuotaWindowKind`, `QuotaWindow`, `ProviderQuotaSnapshot`, `AgentState`, `AgentConfidence`, `AgentSession`, `LayoutMode`, `AnchorMode`, `SingleBarDirection`, `DisplayConfiguration`, `SideAssignment`（签名照 spec §2.8 / §4.1）。

- [ ] Step 1: 写 Codable round-trip 测试（含 `remainingFraction == nil` 保持 nil）。
- [ ] Step 2: 运行确认失败。
- [ ] Step 3: 实现全部 struct/enum（`Codable, Sendable`）。
- [ ] Step 4: 运行测试 → PASS。
- [ ] Step 5: 加**依赖边界测试**：`DomainTests` 中 `grep` 断言 `Domain/*.swift` 不含 `import AppKit|SwiftUI|CodexBar`（用 `Bundle` 读源码或独立 shell 校验脚本 `Scripts/check-domain-purity.sh`）。
- [ ] Step 6: Commit `feat(P1): domain models + purity guard`.

### Task P1-2: 递归嵌套长度纯函数

**Files:** Create `Domain/NestedGauge.swift`；Test `DomainTests/NestedGaugeTests.swift`

**Interfaces:** Produces `NestedGauge.nestedLengths(trackWidth: CGFloat, remaining: [Double?]) -> [CGFloat]`（spec §2.1）。

- [ ] Step 1: 写测试（spec §7.1 全部口径）：

```swift
func test_threeWindows() { XCTAssertEqual(NestedGauge.nestedLengths(trackWidth: 100, remaining: [0.8,0.6,0.25]), [80,48,12]) }
func test_twoWindows() { XCTAssertEqual(NestedGauge.nestedLengths(trackWidth: 100, remaining: [0.6,0.25]), [60,15]) }
func test_nilBreaksChain() { let r = NestedGauge.nestedLengths(trackWidth: 100, remaining: [0.8,nil,0.25]); XCTAssertTrue(r[1].isNaN); XCTAssertTrue(r[2].isNaN) }
func test_nanAndInfinityBreakChain() { /* NaN / .infinity 同 nil */ }
func test_zeroOuterYieldsZeroInner() { XCTAssertEqual(NestedGauge.nestedLengths(trackWidth: 100, remaining: [0,0.5]), [0,0]) }
func test_zeroWidth() { XCTAssertEqual(NestedGauge.nestedLengths(trackWidth: 0, remaining: [0.8,0.6]), [0,0]) }
```

- [ ] Step 2: 运行确认失败。Step 3: 实现（含 `isFinite` 校验、断链传播）。Step 4: 运行 → PASS。Step 5: Commit `feat(P1): recursive nested length pure function`.

### Task P1-3: 几何与轴变换（track/fill 分离、双锚点、无刘海退化）

**Files:** Create `Domain/GaugeGeometry.swift`；Test `DomainTests/GaugeGeometryTests.swift`

**Interfaces:** Produces `GaugeGeometry` 结构 + `GaugeGeometry.layout(mode:anchor:direction:screenFrame:menuBarHeight:notchEdges:) -> [GaugeGeometry]`；`GaugeGeometry.fillRect(forLength:u0:) -> CGRect`（spec §2.2）。

- [ ] Step 1: 写测试：
  - notch 双侧左右**镜像长度相等、方向对称**；
  - outerEdge 双侧方向相反；
  - `single` 双向正确；
  - 无刘海 → 中线分区、`gap == 0`；
  - `trackRect` 在 notch 模式下**横贯整屏**（不裁到刘海）。
- [ ] Step 2: 失败 → Step 3: 实现轴变换 `screen_x = anchorX + u × sideLength × (growsTowardRight ? +1 : -1)` → Step 4: PASS → Step 5: Commit `feat(P1): gauge geometry with track/fill separation`.

### Task P1-4: CALayer 渲染器（唯一渲染器）

**Files:** Create `Overlay/GaugeLayerRenderer.swift`, `Overlay/ThemePalette.swift`, `Overlay/BaselineMarkerLayer.swift`；Test `OverlayTests/GaugeLayerRendererTests.swift`

**Interfaces:**
- Consumes: `NestedGauge`, `GaugeGeometry`, `QuotaWindow`, `ProviderPalette`。
- Produces: `GaugeRendering.render(windows:geometry:palette:baseline:) -> CALayer`；`ProviderPalette`（spec §2.5）。

- [ ] Step 1: 写测试（可断言层结构，不渲染像素）：
  - 嵌套层数量 == 窗口数；
  - 外层 frame ⊇ 内层 frame（同锚点）；
  - `remainingFraction == nil` 时**不生成**该层（断链）；
  - `track` 层用黑色 ~35–40% alpha；
  - 基准线层存在且位置按 spec §2.6 乘积公式（`test_baseline_projectsWithOuterProduct`）。
- [ ] Step 2: 失败 → Step 3: 实现（先画外层后画内层；fill 独立 clip；`cornerRadius` 按 `fullBleed`）→ Step 4: PASS → Step 5: Commit `feat(P1): CALayer gauge renderer`.

### Task P1-5: Fixture 状态源 + 真实渲染器预览

**Files:** Create `Data/Fixtures/FixtureSnapshots.swift`；Modify `Overlay/MenuBarOverlayController.swift`（支持注入快照）；Test `OverlayTests/FixtureRenderTests.swift`

**Interfaces:** Produces `FixtureSnapshots.all: [String: [QuotaWindow]]`，键 `full/weekLow/sessionLow/allZero/missing/stale/reset/agentRunning/agentWaiting/notchless`。

- [ ] Step 1: 写测试断言每个 Fixture 经**同一个** `GaugeLayerRenderer` 能产出层树且无崩溃。
- [ ] Step 2: 失败 → Step 3: 实现 Fixture 常量 + Controller 注入路径 → Step 4: PASS。
- [ ] Step 5: 实机验证：菜单栏依次切 9 个 Fixture，截图存 `docs/preview/`。
- [ ] Step 6: Commit `feat(P1): fixtures rendered through real renderer`.

### Task P1-6: 看门狗 + 生命周期

**Files:** Create `Overlay/BandWatchdog.swift`；Modify `Overlay/MenuBarOverlayController.swift`；Test `OverlayTests/BandWatchdogTests.swift`

**Interfaces:** Produces `BandWatchdog.needsReassert(managedBands:onScreenBands:) -> Bool`、`MenuBarOverlayController.reassert()`、`onScreenBandCount() -> Int`（spec / 参考文档 §7.1）。

- [ ] Step 1: 写测试：

```swift
func test_needsReassert_trueWhenMissing() { XCTAssertTrue(BandWatchdog.needsReassert(managedBands: 2, onScreenBands: 1)) }
func test_needsReassert_falseWhenEqual() { XCTAssertFalse(BandWatchdog.needsReassert(managedBands: 2, onScreenBands: 2)) }
func test_needsReassert_falseWhenNoManaged() { XCTAssertFalse(BandWatchdog.needsReassert(managedBands: 0, onScreenBands: 0)) }
```

- [ ] Step 2: 失败 → Step 3: 实现 5 秒 `Timer` + `onScreenBandCount()`（按 PID + 层级过滤）+ 监听 `didChangeScreenParameters` / `activeSpaceDidChange` / session lock/unlock / 外观变化 → Step 4: PASS。
- [ ] Step 5: 实机验证：手动移除窗口后看门狗补位；**日志确认不频繁闪烁**（数量相等时不动）。
- [ ] Step 6: Commit `feat(P1): band watchdog and lifecycle handling`.

### Task P1-7: 设置窗口骨架（4 Tab + 预览）

**Files:** Create `UI/SettingsWindow.swift`, `UI/AppearanceTab.swift`, `UI/StatusItemController.swift`, `Application/SettingsStore.swift`；Modify `AIUnderlayApp.swift`

**Interfaces:** Consumes `SettingsStore`（`Codable` 持久化 `DisplayConfiguration` 等）；Produces `NSStatusItem` 入口 + Appearance 可切 layout/anchor/direction/fixture。

- [ ] Step 1: 写测试：`SettingsStore` round-trip（含每显示器配置）。
- [ ] Step 2: 失败 → Step 3: 实现 StatusItem + 4 Tab 容器 + Appearance 实时驱动 Overlay → Step 4: PASS。
- [ ] Step 5: 实机验证：切 single/dual、两锚点、双向、9 个 Fixture 全部即时生效。
- [ ] Step 6: Commit `feat(P1): settings window with live preview`.

> **P1 结束 → 停下，请用户看真实效果并拍板信息密度。**

---

# P2 — 真实额度接入与 CLI 管理

> **P2 门禁**：① 外部 CLI 存在→不下载不覆盖 ② 无 CLI→确认后可装、装坏可回滚 ③ 未登录→引导设置而非重装 ④ 绝不造月额度 ⑤ 异常数据不静默夹取。

### Task P2-1: QuotaEngine 协议 + EngineManager 发现/选择
**Files:** Create `Data/QuotaEngine.swift`, `Data/QuotaEngineManager.swift`；Test `DataTests/QuotaEngineManagerTests.swift`
- [ ] 测试：外部兼容 CLI 不下载不覆盖；不兼容→提示托管/手动，不误报"未安装"；symlink 断链/无执行权限/超时/输出畸形/架构不匹配各有明确结果。实现后 Commit。

### Task P2-2: CodexBarCLIClient 接入引擎 + 兼容性矩阵
**Files:** Modify `Data/CodexBar/CodexBarCLIClient.swift`, `Data/QuotaEngineManager.swift`；Test 同上扩展
- [ ] 测试：`probe()` 区分 compatible/incompatible/notLoggedIn；`fetch()` 超时/取消/并发去重。Commit。

### Task P2-3: Usage Decoder（标准化，**Review Focus #1/#2**）
**Files:** Create `Data/CodexBar/CodexBarUsageDecoder.swift`；Test `DataTests/CodexBarUsageDecoderTests.swift`（读 `AIUnderlayTests/Fixtures/*.json`）
- [ ] 测试（spec §7.2 + Review Focus）：
  - `usedPercent` 越界（-5 / 150）/ NaN / 无穷 → `availability == .unavailable`，**不夹取**；
  - primary/secondary **颠倒** → 按 `windowMinutes` 识别周期（300=5h、10080=7d），**不把 primary 当 monthly**；
  - `tertiary` 新增 / 缺 `windowMinutes` / 空数组 / 错误响应 / 混合成功失败 / 增字段 → 互不破坏；
  - `pace.expectedUsedPercent` 存在/缺失；
  - 不同 accountKey 快照独立。
- [ ] 实现后 Commit `feat(P2): codexbar usage decoder with windowMinutes mapping`.

### Task P2-4: SnapshotCache + 刷新调度
**Files:** Create `Data/SnapshotCache.swift`, `Data/QuotaRefreshScheduler.swift`；Test `DataTests/SnapshotCacheTests.swift`
- [ ] 测试：stale 阈值；离线只显缓存并标"已过期"，**不冒充实时**；`resetAt` 变更→重算基准线；突增额度只标"可能重置"，不断言官方赠送。Commit。

### Task P2-5: 托管安装/更新/卸载（校验 + 回滚）
**Files:** Create `Data/CodexBar/CodexBarInstaller.swift`；Test `DataTests/CodexBarInstallerTests.swift`
- [ ] 测试：下载网络错误/校验失败/磁盘不足→回滚、旧版本继续工作；写 App 专属目录不碰 `/usr/local/bin`、不需 sudo；只清理自己安装的；**只有用户点击才下载**。Commit。

### Task P2-6: Providers/Engine 设置 Tab 接线
**Files:** Create `UI/ProvidersTab.swift`, `UI/EngineTab.swift`；Modify `UI/SettingsWindow.swift`
- [ ] 实现：Provider 列表（启用/来源/登录态/上次更新/支持的窗口/Test Connection）；Engine 显示路径版本 + 重检/安装/切换/卸载；共享配置改动前确认；`DistributionProfile.appStore` 时隐藏托管安装。Commit。

### Task P2-7: 端到端真实额度
- [ ] 实机：至少两家 Provider 真实额度显示在菜单栏；无 CLI 场景走确认安装；未登录走引导。记录到 progress。Commit。

---

# P3 — Agent 桥接与动效

> **P3 门禁**：① Hook 安装预览+确认+备份+可卸载，不破坏原配置 ② 无对话正文写盘 ③ 乱序/重复/重连不误判完成 ④ Codex 不支持细分状态标 unknown ⑤ 双 Provider 互不干扰。

### Task P3-1: Unix Socket 接收器
**Files:** Create `Agent/AgentEventReceiver.swift`；Test `AgentTests/AgentEventReceiverTests.swift`
- [ ] 测试：socket 权限 `0600`；只接受白名单元数据；畸形/超长输入不崩溃。Commit。

### Task P3-2: 事件适配器
**Files:** Create `Agent/AgentEventAdapter.swift`；Test `AgentTests/AgentEventAdapterTests.swift`
- [ ] 测试：Claude 原始 Hook → `AgentEvent`；**断言事件中不含 prompt/命令/正文**。Commit。

### Task P3-3: Session Reducer（**Review Focus #4**）
**Files:** Create `Agent/AgentSessionReducer.swift`；Test `AgentTests/AgentSessionReducerTests.swift`
- [ ] 测试：乱序/重复/退出/重连**不把过期事件翻成 completed**；2 running + 1 waitingApproval → 聚合 waitingApproval 且详情数正确；未知不算 idle。Commit。

### Task P3-4: Hook 安装协调器（最高风险）
**Files:** Create `Agent/HookSetupCoordinator.swift`；Test `AgentTests/HookSetupCoordinatorTests.swift`
- [ ] 测试（对**临时目录里的假 `settings.json`**）：预览 diff 生成；最小插入保留原有字节/已有 hooks；改前备份；卸载**只删自己条目**；**默认不安装**。Commit。

### Task P3-5: Agent 动效层 + 聚合
**Files:** Create `Overlay/AgentEffectLayer.swift`, `Agent/AgentActivityAggregator.swift`；Modify `Overlay/GaugeLayerRenderer.swift`, `UI/AppearanceTab.swift`
- [ ] 测试：聚合优先级 `error > waitingApproval > waitingInput > running > completed > idle`；Reduce Motion / 关动效时降级为静态端点；按 display 聚合。实现后 Commit。

### Task P3-6: 端到端 Agent
- [ ] 实机：Claude Code 真实 running/waiting 事件在菜单栏产生可观察动效；Codex 不支持状态标 unknown；双 Provider 互不干扰。Commit。

---

# P4 — 发布收尾

### Task P4-1: Diagnostics Tab
**Files:** Create `UI/DiagnosticsTab.swift`
- [ ] 显示窗口服务器高度/刘海/scale/Overlay 窗口数/CLI 路径版本/上次查询/Hook 状态；**脱敏**复制。Commit。

### Task P4-2: 多屏/Space/锁屏/睡眠 实机矩阵
- [ ] 按 spec §7.5 逐项验证并记录，未测项在 `docs/release-checklist.md` 明确标注。Commit。

### Task P4-3: 性能实测（不设杜撰门槛）
- [ ] 采样 CPU/内存/Energy：空闲、持续运行、睡眠唤醒、双屏；记录数值。Commit。

### Task P4-4: 发布材料
**Files:** Create `README.md`, `NOTICE`, `docs/privacy-and-permissions.md`, `docs/release-checklist.md`
- [ ] README（安装/CLI 来源/Provider 登录/权限/排障）；第三方许可证；隐私声明（不遥测、不采正文）。Commit。

### Task P4-5: 构建 Release
- [ ] 输出可运行 `.app`；有签名环境则 Developer ID 签名+公证；记录版本号与变更摘要。Commit。

---

## 执行协议（每阶段结束产出固定格式）

① 完成项 ② 关键源码路径 ③ 实际构建/测试命令与结果 ④ 真实数据接入结论 ⑤ Agent 能力与限制 ⑥ 实机测试与未测项 ⑦ 上游版本/许可 ⑧ 已知问题/下版优先级 ⑨ App 路径。

## 停止点（用户确认门禁）

- **P0 后**：汇报原型 + 实测高度 + 能力报告 → 用户确认再进 P1。
- **P1 后**：用户看真实渲染效果 → 拍板信息密度 → 再进 P2。
- 每阶段门禁不通过，不得进入下一阶段。
