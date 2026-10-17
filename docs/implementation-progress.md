# Implementation Progress

Updated at the end of every task. Status values: `DONE`, `PARTIAL`, `BLOCKED`, `TODO`.

## P0 — Feasibility Spike

| Task | Status | Notes |
|---|---|---|
| P0-1 工程骨架 | DONE | xcodegen project, Kit framework + app shell, smoke tests pass |
| P0-2 穿透覆盖窗口 | DONE | Band renders behind menu bar, icons on top; evidence `docs/preview/p0-band-menubar.png` |
| P0-3 菜单栏几何 | DONE | Window-server height + Quartz flip + notch, 7 unit tests. See ledger below. |
| P0-4 CLI 探测 + Fixture | DONE | Discovery + client + real desensitized fixtures (CodexBar 0.58.0) |
| P0-5 Agent 能力报告 | DONE | `docs/agent-capability-report.md`; event whitelist types added |

**P0 gate result:** static band visible behind the menu bar without occluding
icons or intercepting clicks; real menu bar height read (30pt); real CodexBar
CLI detected and JSON captured; agent capability matrix written. **P0 complete.**

## P1 — Domain / Renderer / Mock

| Task | Status | Notes |
|---|---|---|
| P1-1 Domain models | DONE | QuotaWindow/Snapshot/AgentSession/DisplayConfiguration/AppSettings + purity guard |
| P1-2 NestedGauge | DONE | chain-break on unknown, 8 tests |
| P1-3 GaugeLayout | DONE | abstract axis, notch/outerEdge, midline fallback, 9 tests |
| P1-4 Renderer | DONE | single GaugeLayerRenderer, baseline projection, end-cap, 8 tests |
| P1-5 Fixtures | DONE | 11 fixtures drive the real renderer (11th added 2026-10-13: `agentError`) |
| P1-6 Watchdog | DONE | needsReassert pure fn + 5s timer + lifecycle observers |
| P1-7 Settings UI | DONE | 4 tabs, live Appearance controls, NSStatusItem entry |

Evidence: `docs/preview/p1-*.png` (dual weekLow, dual full, single full).
Total tests: 74 passing.

## P2 — 真实额度接入

| Task | Status | Notes |
|---|---|---|
| P2-1/2 QuotaEngine + Manager | DONE | discovery/selection, incompatible-only state, injectable paths |
| P2-3 Usage Decoder | DONE | windowMinutes mapping, out-of-range→unavailable (no clamp), positional fields |
| P2-4 Cache + Scheduler | DONE | stale threshold, minute-level refresh, in-flight de-dup |
| P2-5 Managed installer | DONE | SHA-256 verify, rollback, App Store profile disables it |
| P2-6 Providers/Engine tabs | DONE | live provider table, engine detection, uninstall |
| P2-7 Live end-to-end | DONE | real codex quota rendered from CLI; claude unauthenticated → empty track |

**Fix during P2:** live mode previously fell back to a fixture before the first
snapshot arrived (~7s CLI fetch), which could be mistaken for real data. Now
live mode shows empty tracks until a real snapshot arrives. Evidence:
`docs/preview/p2-live-codex.png`.

Tests: 97 passing.

## P3 — Agent 桥接

| Task | Status | Notes |
|---|---|---|
| P3-1 Socket receiver | DONE | Unix socket 0600, line framing, defensive parsing, verified bound at runtime |
| P3-2 Adapters | DONE | Claude full mapping; Codex maps unknown → unknown (no invented waiting) |
| P3-3 Session reducer | DONE | stale-event rejection, aggregation priority, unknown counted |
| P3-4 Hook installer | DONE | preview → confirm → backup → marker-scoped uninstall |
| P3-5 Agent effects | DONE | endpoint dot, pulse, reduce-motion suppression |
| P3-6 E2E | DONE | real socket event → dot; visual evidence `docs/preview/p3-agent-waiting.png` |

Note: real Claude Code hook wiring requires the user to install hooks via the
Agent tab (not done automatically). The socket path is verified working with a
synthetic event.

Tests: 122 passing.

## P4 — 发布收尾

| Task | Status | Notes |
|---|---|---|
| P4-1 Diagnostics tab | DONE | measured geometry, window counts, desensitized copy |
| P4-2 Docs | DONE | README, NOTICE, privacy-and-permissions, release-checklist |
| P4-3 Release build | DONE | `xcodebuild -configuration Release` succeeds |
| P4-4 Settings window | DONE | explicit NSWindow host (accessory app); all 5 tabs render |
| P4-5 Hardware matrix | PARTIAL | single display verified; multi-display/notch/macOS14-15 pending |

**Release artifact:** `AIUnderlay.app` (Release, ad-hoc). Developer ID signing
and notarization are pending a signing identity.

Evidence: `docs/preview/p4-settings.png`. Total tests: 122 passing.

## P5 — Agent 动态特效（2026-10-13）

| Task | Status | Notes |
|---|---|---|
| P5-1 频谱柱动效 | DONE | `RunningEffect.spectrum` 为**新增**第 5 个选项；既有 4 个动效与默认值不变。柱从菜单栏下边缘向上生长，全量 Core Animation |
| P5-2 速度→节奏 | DONE | `SpectrumRhythm` 纯函数 0.34–1.10 Hz；`nil` 测速 = 下限（真实 TPS 数据源未接入）。下限可由「外观 → Agent 动效节奏」调整，见 P6-13 |
| P5-3 等待/故障边框 | DONE | waiting 黄、error 红的上下列细边框；原呼吸蒙层/脉冲保留 |
| P5-4 预览与文档 | DONE | 新增 `agentError` 样例；`docs/superpowers/specs/2026-10-13-agent-dynamic-effects-design.md` |
| P5-5 主题 JSON 引擎 | DONE | 版本化 JSON + schema + 示例；`ThemeStore` 载入/校验/热重载（目录 + 每文件 vnode 双层监听，300ms 防抖）；坏文件跳过并保留上一个正常主题；设置新增「主题」页 |
| P5-6 主题接线 | DONE | 主题只覆盖它写明的字段；`Error > Waiting > Normal` 优先级仍在代码里；`spectrumColor` 在「运行中颜色 = 跟随主题」（新默认）时生效 |
| P5-7 多维信号（修 Running+Waiting） | DONE | `AgentSignals` 取代单一 `dominant` 状态：活动/等待/故障/完成四维独立计数，等待+运行同时成立。渲染改为 `AgentEffectPlan`（§5.2 组合矩阵），橙色/红色频谱与警示边框可同时出现。新增离线样例 `agentRunningWaiting`、`agentRunningError` |

Evidence: `docs/preview/p5-agent-spectrum.png`、`p6-agent-waiting-borders.png`、
`p7-agent-error-borders.png`、`p8-theme-hot-reload-1.png`、`p9-theme-hot-reload-2.png`.
`p10-agent-running-waiting.png`、`p11-agent-running-error.png`. Total tests: 265 passing.

## P6 — Glass Spectrum 统一重构（2026-10-14）

依据 `AIUnderlay-Glass-Spectrum-Refactor-Codex-Plan-2026-10-14.md`（用户选定 V5 参数）。
分支 `codex/glass-spectrum-unified-renderer`，基线 `363d675`。

| Task | Status | Notes |
|---|---|---|
| P6-1 单一渲染引擎 | DONE | 删除 `RunningEffect`/`RunningEffectColor` 与其分支、`AgentEffectLayer`、旧 `GaugeLayerRenderer`；新增 `GlassQuotaRenderer` / `GlassSpectrumRenderer` / `AttentionLightRenderer` / `GlassLayerHost` |
| P6-2 稳定图层树 | DONE | 命名槽位 + `reconcile`；重复 100 次渲染图层数与 `animationStarts` 不变；每 Lane ≤6 个动画层 |
| P6-3 黑底嵌套额度 | DONE | 已知额度画 V5 黑色底（0.78→0.98），未知/过期画中性槽（不等于 0%）；染色只裁到外层填充长度 |
| P6-4 信号语义 | DONE | `Error > Waiting > Unread` 固定优先级 + Running 独立布尔；运行中光场取最高优先级颜色；无测速时用最慢节奏 |
| P6-5 主题 v2 + 迁移 | DONE | `schemaVersion: 2`（`material`/`signals`/`attention`/`quotaBaseColor`/`agentThemeColor`/`exhaustedTrack*`）；v1 文件继续可读；旧设置 `runningEffect=none → reduceMotion`、`runningEffectColor → signals.running` |
| P6-6 离线视觉证据 | DONE | `GlassPreviewTests` 渲染 13 张 PNG 到 `docs/preview/glass-spectrum/`，并像素校验黑底与染色裁切 |
| P6-7 Unread 输入契约 | PARTIAL | `AgentSignals.unreadCount` 作为输入契约 + fixtures（`agentUnread`/`agentRunningUnread`/`agentAllSignals`）；真实完成账本仍在未合并的 `codex/unread-completion-attention-ribbon` 分支，生产保持 0 |
| P6-8 NSVisualEffectView 尖刺 | TODO | 默认路径为"渲染玻璃"（不采样桌面）；30 分钟真机模糊/CPU 尖刺未执行 |
| P6-9 光幕基线 | DONE | 射线立在轨道下边缘（Quartz `y = 0`），所有柱底共线、只有波峰起伏；修正首版把幕帘挂在上边缘的问题，`test_rayCurtain_standsOnTheBottomEdge` 逐像素守卫 |
| P6-10 Attention 三段渐变方向 | DONE | V5 的 `.hint` / `.edge-bottom` / 上向阴影都是**底部最强**：wash `to top`、ribbon `180deg transparent→alert`、glow 贴 ribbon 向上衰减。首版三条渐变 y 方向全部写反，下半条出现硬边"厚板"，现已翻正并有结构测试守卫 |
| P6-11 双侧各自裁剪 | DONE | 底槽仍是整屏一条（不露壁纸），但每条 lane 只画自己那半：`GaugeGeometry.trackBounds` 在中线切分，bed/顶底描边按 `trackBounds` 画，光幕与 attention 带按 `fillBounds` 画。此前只配一个 Provider 时，另一侧的空 lane 与运行中光幕会盖满整条菜单栏，也有逐像素守卫（`test_dualLanes_*HalfPixelIdentical`、`test_emptyNeighbourLane_*`） |
| P6-12 设置生效延迟 | DONE | 根因是 `@Published` 在 `willSet` 发布：订阅 `$settings` 又回读 `store.settings` 的 sink 拿到的是**旧值**，于是每次切换都晚一拍、要等下一次无关刷新才补上。`SettingsStore.changes` 在赋值并落盘之后发布，coordinator 与弹窗改用它；守卫：`test_changesPublisher_*`、`test_updatePersistsBeforeNotifying` |
| P6-13 基准节奏可调 | DONE | 原先把基准写死在代码里，只能改代码再编译。现在 `AppSettings.motionFloorFrequencyHz` 经 coordinator 落到 `LaneRenderSpec.spectrumFloorHz`，「外观 → Agent 动效节奏」用滑杆 + 4 个预设（2.9/2.0/1.4/1.1 秒一圈）实时对比；`SpectrumRhythm.clampedFloor` 把越界值夹到 0.15–1.10 Hz，坏设置也不会变成频闪或静止。守卫：`test_userFloor_*`、`test_baselineTempo_*`、`test_motionFloor_*` |
| P6-14 光幕画面对比度 | DONE | 离屏预览有 80 级明暗差，真机菜单栏只有 24 级：band 窗口在菜单栏之下，系统菜单栏材质吃掉约 40% 对比度。射线幕新增静态深色底（自下而上 45%→透明、不参与动画、Reduce Motion 保留），射线基准波高 0.20→0.32、不透明度 0.46 起、白核 1.16→1.3pt。真机实测明暗差 24→约 50。守卫：`test_curtainStandsOnAStaticDarkScrim` |
| P6-15 两处扫光可关 | DONE | 「横穿扫光」（`showTravelingLight`）关掉只隐藏两条宽光场，射线幕照常呼吸；「状态灯带扫光」（`showAttentionSweep`）关掉保留顶线/底带/辉光，只去掉来回的亮带。开关走 `LaneRenderSpec` 且**不重建图层**，切换即时生效（图层保留、只切 hidden 与动画）。守卫：`test_travelingLightDisabled_*`、`test_sweepDisabled_keepsTheStaticAlert`、`test_*Toggle_appliesToTheLiveLayer(s)`、`test_sweepToggles_*` |
| P6-16 服务商总开关 + 单提供商双侧拆分 | DONE | 「服务商」页每家一个 `enabledProviders` 总开关，独立于 CodexBar 上游启用：关掉的 provider 不请求、不显示（overlay/dashboard/刷新计划一致），重新打开立即取数；上游状态与登录状态照常展示。「外观」页新增 `dualWindowSplit`（仅双侧 + 只启用一家时可用）：5 小时窗口放选定一侧、其余窗口（周/月）嵌套在另一侧，两侧共用同一提供商的配色与动效（`LanePlanResolver` / `WindowSplit` 纯域解析，live 与 fixture 共用同一组合管线）。守卫：`LanePlanTests`、`SettingsStoreTests.test_providerSwitches_*`、`test_unknownSplitValue_fallsBackToNone`、旧文件缺键默认全开不拆分 |
| P6-17 拆分两侧不同色 | DONE | 原先单提供商拆分后两侧共用同一配色，一眼分不出 5 小时与周额度。现在配色按**角色**而非物理左右走：5 小时那侧把 Provider 的本色相偏转 30°（`SplitLaneColors.sessionHueShift`），周额度侧沿用本色；翻转拆分方向时颜色跟着窗口走。「主题 → 额度颜色 → 拆分」可分别覆盖两侧（`GlassAppearance.splitQuotaBaseColors`，设置级、不写主题文件），一侧选色不影响另一侧。未拆分/两家各占一侧/单条一律不受影响（`LanePlan.splitRole(for:)` 只在两侧同 Provider 时给出角色）。守卫：`LanePlanTests.test_splitRole_*` / `test_splitColors_*`、`ThemeResolverTests.test_splitRole*`、`SettingsStoreTests.test_splitQuotaColors_*`、`GlassPreviewTests.test_splitSidesRasteriseTwoDifferentQuotaColours`（像素级：5 小时侧与周额度侧必须不同色，且未拆分的那条像素不变） |

Evidence: `docs/preview/glass-spectrum/*.png`（30pt，2x，含关闭扫光的对照图与
`split-*-side-32pt-2x.png` 拆分两侧对照）。Total tests: 482 passing
(3 skipped = opt-in PNG dumps), `Scripts/check-domain-purity.sh` OK。

Known limits: 真实 TPS 未接入（光场始终跑设置里的基准节奏）；
Unread 仅 fixtures；
真机 30/32/34pt 与多显示器仍需人工确认。

## Hardware verification ledger

Items that can only be confirmed on a real Mac session (to be filled during
manual verification):

| Item | Verified | Value observed |
|---|---|---|
| Band window level correct, no menu bar occlusion | ☑ | icons/text stay on top; screenshot `docs/preview/p0-band-menubar.png` |
| Menu bar height (internal display) | ☑ | 30 pt (window server layer 24), `Scripts/probe-menubar.swift` |
| Menu bar height (external display) | ☐ | no external display attached during this session |
| Notch edges detected | ☑ (no-notch path) | single display has no notch; `auxTopLeft/Right = nil` → midline fallback required |

Session machine: single built-in display 2048×1152 pt @2x, menu bar level = 24.
No external display was attached, so the multi-display / non-primary-height
case is verified by unit test only (`test_height_picksMatchingDisplayNotGlobalMax`),
not on hardware. To be re-checked with an external display attached.
