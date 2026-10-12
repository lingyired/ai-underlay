# Agent 动态特效 — 设计（Design Spec）

> 日期：2026-10-13
> 状态：已实现并验证（频谱柱 / 等待与故障边框）；主题引擎待确认
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
| 主题 JSON 引擎（共识 spec §7.3） | **未做** | §11 明确「主题 Schema 的最终字段名与层级」及「默认主题色值」**不该由 Agent 擅自锁定**。实现前需要你定：字段名是否照抄 §7.3 示例、默认色板取哪套。 |
| TPS → 频率的真实数据 | **接缝已就绪** | 仓库当前没有采集 output tokens/s（CodexBar `sessions --json` 未提供）。`SpectrumRhythm` 已支持 `outputTPS`，现在按最慢节奏跑；接入数据源即可生效。 |
| 「Active + Waiting → 橙色频谱」（共识 spec §5.2） | **未做** | 需要先落地四维度（Health/Attention/Activity/Performance）模型；当前每个 Provider 仍是单一 dominant state。 |
| Recovering 的动画 | **未做** | §11 列为待 UX 验证。 |

## 4. 下一步建议

1. 你确认主题引擎的两项未决参数 → 落地 `ThemeDocument` + 热重载 + `theme.schema.json`。
2. 找到可用的 TPS 来源（Codex/Claude 会话日志或 CodexBar 新字段）→ 接上 `outputTPS`。
3. 把 Waiting / Error / Recovering 的动画细节按真实使用做一轮调参。
