# AIUnderlay 主题

主题**只描述外观**：颜色、透明度、材质、提醒光。它不能改变
`Error > Waiting > Unread` 的优先级，不能编造额度窗口，也不能影响任何监控数据。
这也是为什么 AI Agent 可以自己写主题，而不需要改 Swift 代码。

## 放在哪里

一个文件一个主题：

```
~/Library/Application Support/com.lingsmbp.aiunderlay/Themes/<anything>.json
```

保存后 App 会**热重载**（防抖 300ms）。JSON 有错时：报告原因、跳过该主题；
如果出错的正是当前主题，会继续用上一次正常的版本，不会闪回默认。

内置主题（Selected Glass V5、明亮示例）在代码里，不落盘，所以 App 更新不会覆盖你保存的主题。

## 版本

| schemaVersion | 词汇 | 说明 |
| --- | --- | --- |
| 1 | `quotaLayers` / `states` | 经典写法，**继续可用**，行为不变 |
| 2 | 追加 `material` / `signals` / `attention`、`quotaBaseColor`、`agentThemeColor`、`exhaustedTrack*` | 默认导出格式 |

v1 文件不会被自动改写；只有你（或 Agent）主动写出 v2 才会升级。未知版本会被拒绝，
而不是猜测字段含义。机器可读定义见 [`theme.schema.json`](theme.schema.json)。

## 三类颜色必须分开写

| 角色 | 字段 | 默认 | 影响范围 |
| --- | --- | --- | --- |
| 额度色 | `providers.<id>.quotaBaseColor` 或 `quotaLayers` | codex `#69BFFF`、claude `#FFB08A` | 只有额度填充本身 |
| 玻璃染色 | `providers.<id>.agentThemeColor` | codex `#62AC96`、claude `#FFFFFF` | 只有玻璃材质，绝不改额度与状态光 |
| 状态光源 | `signals.running/error/waiting/unread.lightColor` | `#D9EEFF` / `#FF7596` / `#FFE1A0` / `#64F1BD` | 全局语义，优先级固定 |

## 字段

| 作用域 | 字段 |
| --- | --- |
| global | `trackColor`、`trackOpacity`、`baselineColor`、`baselineOpacity`、`baselineEnabled`、`exhaustedTrackColor`、`exhaustedTrackOpacity` |
| providers.<id> | `quotaLayers`（**外层→内层**，最多 3 层）、`quotaBaseColor`、`agentThemeColor`、`spectrumColor`、`spectrumOpacity` |
| states.waiting / states.error | `overlayColor`、`overlayOpacity`、`spectrumColor`、`borderColor`、`borderWidth` |
| signals.running/error/waiting/unread | `lightColor` |
| material | `blurRadiusTarget`(0–32)、`ambientGlow`、`grain`、`rayDensity`、`quotaOpacity`、`agentThemeStrength`（后五项 0–1） |
| attention | `topLineHeight`(0–6)、`bottomRibbonHeight`(0–10)、`sweepSecondsError` / `sweepSecondsWaiting` / `sweepSecondsUnread`(1–60) |

- 颜色写法：`#RRGGBB`、`RRGGBB`、`#RGB`、`#RRGGBBAA`。
- **只写你要覆盖的字段**，没写的沿用内置默认（Selected Glass V5）。
- `quotaLayers` 与 `quotaBaseColor` 二选一：写了每一层就用每一层，
  只写 base 时按文档化的亮度阶梯生成 outer/middle/inner。
- `ambientGlow = 0` 时 `agentThemeStrength` 独立生效（V4 的“染色全消失”bug 已修）。
- 近白染色（例如 claude `#FFFFFF`）只做**渲染端**可读性上限，存储的 HEX 不会被改。
- 无数据 ≠ 0%：未知/未登录显示中性槽，不会画成“额度用完”的黑色。

## 用 AI 生成主题

设置 → 主题 → **复制给 AI 的指令**，把那段话连同目标色板粘给 AI 即可。
两份现成样例：[`examples/selected-glass-v5.json`](examples/selected-glass-v5.json)（v2）、
[`examples/vivid.json`](examples/vivid.json)（v1）。
