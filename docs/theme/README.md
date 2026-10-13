# AIUnderlay 主题

主题**只描述外观**：颜色、透明度、边框、频谱色。它不能改变
`Error > Waiting > Normal` 的优先级，不能编造额度窗口，也不能影响任何监控数据。
这也是为什么 AI Agent 可以自己写主题，而不需要改 Swift 代码。

## 放在哪里

一个文件一个主题：

```
~/Library/Application Support/com.lingsmbp.aiunderlay/Themes/<anything>.json
```

保存后 App 会**热重载**（防抖 300ms）。JSON 有错时：报告原因、跳过该主题；
如果出错的正是当前主题，会继续用上一次正常的版本，不会闪回默认。

内置主题（「明亮示例」）在代码里，不落盘，所以 App 更新不会覆盖你保存的主题。

## 字段

机器可读定义见 [`theme.schema.json`](theme.schema.json)，可复制示例见
[`examples/vivid.json`](examples/vivid.json)。要点：

| 作用域 | 字段 |
| --- | --- |
| global | `trackColor`、`trackOpacity`、`baselineColor`、`baselineOpacity`、`baselineEnabled` |
| providers.<id> | `quotaLayers`（**外层→内层**，最多 3 层）、`spectrumColor`、`spectrumOpacity` |
| states.waiting / states.error | `overlayColor`、`overlayOpacity`、`spectrumColor`、`borderColor`、`borderWidth` |

- 颜色写法：`#RRGGBB`、`RRGGBB`、`#RGB`、`#RRGGBBAA`。
- **只写你要覆盖的字段**，其余的沿用内置默认色。
- `spectrumColor` 只在「运行中颜色 = 跟随主题」时生效（这是默认值）；
  如果你在设置里明确选了一个颜色，你的选择优先。

## 用 AI 生成主题

设置 → 主题 → **复制给 AI 的指令**，把那段话连同目标色板粘给 AI 即可。
