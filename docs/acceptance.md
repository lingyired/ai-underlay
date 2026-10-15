# Acceptance Guide — Glass Spectrum（2026-10-14）

单引擎重构完成后的复核清单。自动化证据见
`docs/implementation-progress.md` P6 与 `docs/preview/glass-spectrum/`。

## 0. 构建与测试（约 3 分钟）

```bash
cd /Users/lingsmbp/.codex/worktrees/glass-spectrum/ai-underlay
xcodegen generate
Scripts/test.sh                    # expect: 384 tests, 0 failures, 1 skipped
Scripts/check-domain-purity.sh     # expect: OK
```

可选的离线视觉证据重生成（写入 `docs/preview/glass-spectrum/`）：

```bash
TEST_RUNNER_GLASS_PREVIEW_DUMP=1 Scripts/test.sh \
  -only-testing:AIUnderlayKitTests/GlassPreviewTests/test_dumpPreviewPNGsWhenRequested
```

## 1. 需要你确认的观感（真机）

启动开发构建后，用 **Settings → Appearance → Fixture** 逐个切换：

1. `glassV5` —— 用户选定的 V5 参数：codex 82%/55%、claude 67%/36%，黑色用完底色。
2. `agentRunning` / `agentRunningWaiting` / `agentRunningError` —— 光场是否
   够"玻璃"、running 时是否戴上最高优先级颜色。
3. `agentWaiting` / `agentError` / `agentUnread` —— 顶线 2pt、底部缎带 5pt
   是否可见但可读（额度不被遮住）。
4. `allZero` / `missing` / `stale` —— 用完＝纯黑，未知＝中性槽（**不能**看成 0%）。
5. `notchless`、双显示器（如有）—— 左右两侧几何是否镜像正确。

真机待测：30/32/34pt 菜单栏高度、多显示器、Reduce Motion 开关、
长时功耗（见 §4）。

## 2. 三色角色不要互相污染

在 **Settings → Theme** 里分别改：

| 改动 | 预期 | 不应发生 |
|---|---|---|
| Agent 玻璃染色（codex/claude） | 只有玻璃表面变色 | 额度颜色、信号光不变 |
| 额度颜色 | 只有填充变色 | 染色与信号光不变 |
| 四个信号光颜色 | 只有状态光变色 | 额度与染色不变 |

切到 `agentRunningWaiting`：光场应使用 waiting 的黄，而额度仍是蓝色。

## 3. 主题 v1 兼容

把旧主题 JSON（`docs/theme/examples/vivid.json`，schemaVersion 1）放进
`~/Library/Application Support/com.lingsmbp.aiunderlay/Themes/`：应正常加载并
保持旧观感；`runningEffect=none` 的旧 settings.json 应变成 Reduce Motion。
（自动测试：`ThemeDocumentTests`、`SettingsStoreTests`、`ThemeResolverTests`。）

## 4. 尚未验证（需要真机 / 你）

- **NSVisualEffectView 真模糊**：当前实现是"渲染玻璃"（不采样桌面背景）。
  plan 的 P0 尖刺（30 分钟观察模糊正确性与 CPU）**未执行**；在跑完之前，
  `blurRadiusTarget` 只是柔化目标值，不是真实 backdrop blur。
- **Unread 实数据**：`AgentSignals.unreadCount` 是输入契约，生产恒为 0；
  真实完成账本在未合并分支 `codex/unread-completion-attention-ribbon`。
- **真实 TPS**：未接入，光场按「外观 → Agent 动效节奏」里的基准节奏运行（不伪造 48%）。
- 多显示器 / 刘海 / macOS 14–15：仅单元测试覆盖，未在硬件验证。

## 5. 证据

| 文件 | 内容 |
|---|---|
| `docs/preview/glass-spectrum/codex-82-55-running.png` | V5 codex，运行中 |
| `docs/preview/glass-spectrum/claude-67-36-running.png` | V5 claude，运行中 |
| `docs/preview/glass-spectrum/all-zero-exhausted.png` | 0% = 纯黑底 |
| `docs/preview/glass-spectrum/unknown-missing.png` | 未知 = 中性槽 |
| `docs/preview/glass-spectrum/running-waiting.png` 等 | 组合矩阵 |
| `docs/preview/glass-spectrum/reduce-motion-running-error.png` | Reduce Motion 静态帧 |

## 6. 怎么运行

App 是 `LSUIElement`（无 Dock 图标）。启动后点菜单栏的 gauge 图标 →
**Settings…**。退出：同一菜单 → *Quit*，或 `pkill -x AIUnderlay`。
