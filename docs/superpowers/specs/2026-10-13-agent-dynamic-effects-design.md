# Agent 动态特效 — 设计（Design Spec）

> 日期：2026-10-13
> 状态：已实现并验证（频谱柱 / 等待与故障边框 / 主题 JSON 引擎）
> 上游共识：`AIUnderlay-Agreed-Product-Spec-2026-10-13.md`（下称「共识 spec」）
> 本文性质：记录本轮"新增动态特效、现有特效不变"的设计取舍、已验证结果与未决项。

---

## 0. 本轮范围

用户要求：**参考共识 spec 新增动态特效，现有特效保持不变。**

据此定下的原则：

1. **纯增量**。`呼吸灯`、`扫光`、`端点脉冲`、`无` 四个既有运行中动效的代码路径、
   视觉与默认值（默认 `呼吸灯`）均不修改；频谱是下拉里的**第 5 个选项**。
2. **waiting / error 的既有表现不被替换**，只按共识 spec §5.3 追加警示边框。
3. 共识 spec §11 明确「不应由 Agent 擅自锁定」的项（默认主题色值、主题 Schema
   字段名）**本轮不锁**，留待用户拍板。

## 1. 已实现

### 1.1 运行中动效：频谱柱（`RunningEffect.spectrum`）

对应共识 spec §5.3「Running / Active」与 §6.2「速度 → 频率」。

- **几何**：等宽柱从菜单栏**下边缘向上**生长，覆盖该 Provider 的填充区
  （`fillBounds`），并在 `trackRect` 内裁切，因此不会越界到刘海或对侧。
- **动画**：每根柱一个 `CALayer` + `bounds.size.height` 的 `CAKeyframeAnimation`，
  全量在 Core Animation 里跑，不做逐帧 CPU 更新（共识 spec §9）。
- **节奏**：`SpectrumRhythm.frequencyHz` = `0.18 + 0.44 * sqrt(min(TPS,160)/160)`，
  即 0.18–0.62 Hz。**速度只改节奏，不改高度**；`nil`（没有测速数据）= 最慢节奏，
  不会因为"没测到速度"就停跳（共识 spec §6.2）。
- **波形**：`SpectrumRhythm.wave(index:)` 给每根柱确定性的相位、整数倍速与
  振幅，因此波形可复现、可单测，且循环无缝。
- **减弱动效**：`reduceMotion` 时柱子静止但仍显示（保留静态可辨认的信号）。
- **颜色**：沿用「运行中颜色」设置，不新增颜色开关。

### 1.2 等待 / 故障：上下列警示边框

对应共识 spec §5.3 与 §7.2 的 `borderColor` / `borderWidth`。

- `waitingInput` / `waitingApproval`：**黄色**边框（`attentionBorder`）。
- `error`：**红色**边框（`failureBorder`）。
- 边框画在该 Provider 的填充区上、下两条细线；`scale` 单/双侧模式都适用。
- 原「整条呼吸蒙层 / 脉冲」**保留不变**，边框是额外的独立图层，
  Reduce Motion 下依然可辨认。

### 1.3 配套

- 新增离线预览样例 `agentError`，不用真实 Provider 就能看红色故障态。
- 新增 `SpectrumRhythmTests`、`FixtureSnapshotsTests`，并更新 `AgentEffectTests`。
- 新增截图：`docs/preview/p5-agent-spectrum.png`、`p6-agent-waiting-borders.png`、
  `p7-agent-error-borders.png`。

## 2. 验证

- `Scripts/test.sh`：**226 tests, 0 failures**（本轮 +17）。
- `Scripts/check-domain-purity.sh`：OK。
- 真机菜单栏截图（单条模式，1440pt 宽）：
  - 频谱柱连续跳动；间隔 0.8s 连拍三帧像素哈希各不相同 → 确认在动。
  - 等待态：上、下两条黄色边框可见（放大核对底部边框）。
  - 故障态：顶部红色边框 + 红色蒙层可见。

## 3. 未做 / 待你确认

| 项 | 状态 | 说明 |
|---|---|---|
| 主题 JSON 引擎（共识 spec §7.3） | **DONE** | 用户确认「字段名照抄 §7.3 示例」。见 §5。 |
| TPS → 频率的真实数据 | **接缝已就绪** | 仓库当前没有采集 output tokens/s（CodexBar `sessions --json` 未提供）。`SpectrumRhythm` 已支持 `outputTPS`，现在按最慢节奏跑；接入数据源即可生效。 |
| 「Active + Waiting → 橙色频谱」（共识 spec §5.2） | **DONE** | 见 §6。原先每个 Provider 只有一个 dominant state，导致「有人等 + 有人跑」时频谱消失；现已改为四维信号。 |
| Recovering 的动画 | **未做** | §11 列为待 UX 验证。 |

## 6. 多维信号：Running 与 Waiting 同时成立（2026-10-13 bug 修复）

**问题**（用户实测反馈）：等待阶段同时有其他 Agent 在跑时，频谱柱不出现。

**根因**：`AgentActivityAggregator.Aggregate` 把同一 Provider 的所有会话压成一个按优先级
互斥的 `dominant` 状态（`AIUnderlayKit/Agent/AgentSessionReducer.swift`）。Waiting 优先级
高于 Running，于是「1 个等待 + N 个运行」只剩 `waitingApproval`，移动动效根本没被触发。
共识 spec §4.1 早就禁止这种压平：*"聚合层不应只产出一个互斥的 dominantState"*。

**修法**：

1. 新增 `AgentSignals`：`activeCount` / `waitingApprovalCount` / `waitingInputCount` /
   `errorCount` / `completedCount` / `unknownCount`，四个维度独立计数；`primaryState`
   只留给「只能显示一个」的地方（弹窗摘要、诊断）。
2. 新增纯数据 `AgentEffectPlan`，实现共识 spec §5.2 的组合矩阵：
   Error > Waiting > Active > Completed 决定**颜色与边框**，`hasActive` 决定**动不动**。
   两者互不覆盖，所以「等待 + 运行」= 橙色频谱继续跳动 **且** 黄色上下边框。
3. 渲染入口从 `make(state:)` 改为 `make(signals:)`（`make(state:)` 仍保留，内部转成信号）。
4. `agentSignature()` 把四维计数都纳入重绘判据 —— 否则 Waiting 数变化时会漏重绘。
5. 离线样例新增 `agentRunningWaiting`、`agentRunningError`，矩阵不用真 Provider 就能看。

**回归保护**：新增测试覆盖组合矩阵、单状态与 plan 的一致性（该测试在实现过程中真的抓出了
两个回归：waitingInput 的琥珀色被统一成橙色、completed 的青色没有随计划传递），
以及「未知态既不动也不红」。

## 4. 下一步建议

1. 找到可用的 TPS 来源（Codex/Claude 会话日志或 CodexBar 新字段）→ 接上 `outputTPS`。
2. 把 Waiting / Error / Recovering 的动画细节按真实使用做一轮调参。
3. 设置页里的图形化取色器（当前是「编辑 JSON + 热重载 + 复制给 AI」）。

## 5. 主题 JSON 引擎（本轮补做）

共识 spec §7.3 的方向全部落地，字段名按 §7.3 示例：

- **模型**：`ThemeDocument`（`schemaVersion: 1` / `id` / `name` / `global` / `providers` /
  `states`），纯 Foundation，可单测。
- **校验**：颜色（`#RGB` / `#RRGGBB` / `#RRGGBBAA`）、透明度 0…1、`quotaLayers` 最多 3 层、
  `borderWidth` 0…10、id 不含路径分隔符。**未知 schemaVersion 直接拒绝**，不猜测。
- **存放**：`~/Library/Application Support/<bundle>/Themes/*.json`，一个文件一个主题；
  内置主题在代码里，App 更新不会覆盖用户文件。
- **热重载**：目录监听（新增/删除/改名）+ **每个文件的 vnode 监听**（内容修改）双层，
  300ms 防抖。只监听目录会漏掉「原地编辑已有文件」，这是实现时实测发现的坑。
- **失败回退**：坏文件跳过并显示原因；若坏的正是当前主题，继续渲染上一个正常版本。
- **边界**：主题只能改外观。`Error > Waiting > Normal` 的优先级在 `AgentEffectStyle` 里，
  主题文件无法表达优先级，也无法编造额度层。
- **接线**：`ThemeResolver` 只覆盖主题写明的字段；用户显式选择的「运行中颜色」优先于主题。
  `runningEffectColor` 新默认是 `theme`（跟随主题），没有主题时解析为内置绿色 —— 视觉不变。
- **上下文**：`docs/theme/theme.schema.json`、`docs/theme/examples/vivid.json`、
  `docs/theme/README.md`，设置页可一键复制给 AI 的写作指令。
