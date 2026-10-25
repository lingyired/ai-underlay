# Codex 无 Hook 的 Agent 设置记录

日期：2026-10-18。范围：`AIUnderlayKit/UI/AgentTab.swift`、
`AIUnderlayKit/UI/AgentSettingsLogic.swift`、`HookSetupCoordinator.hasManagedEntries()`
及对应测试。Codex 的实时状态枚举 `CodexRuntimeStatus`（`connecting` /
`connected` / `fallback`）与 `AppCoordinator.codexRuntimeStatus` 由主任务提供，
本任务只观察，不重复定义；`SettingsRootView`、`DiagnosticsTab`、README 与
coordinator 集成也归主任务。

## 实施

| 原问题 | 当前行为 |
|---|---|
| Codex 需要安装并信任 Hook 才能获得及时状态 | Codex 卡片改为自动检测：观察 `AppCoordinator.codexRuntimeStatus`，连接中显示进度、已连接与日志兜底显示枚举的 `title`/`detail`；Codex 的预览、安装和应用按钮全部移除 |
| 应用会写入 `~/.codex/hooks.json` | 不再有 Codex 安装入口。仅当文件里存在带本应用标记（`--managed-by=com.lingsmbp.aiunderlay`）的条目时，显示默认折叠的「旧版 Hook 清理」，由用户显式点击移除；失败用 `do/catch` 显示真实原因，文件不可读时不提供清理 |
| `refreshStates` 只要文件存在就报「需要更新 Hook」 | 改用归属判断：`isInstalled()` 为真显示已安装；仅当 `hasManagedEntries()` 证明存在本应用条目（例如旧版本写入、命令已过期）才显示需要更新；两者都不成立显示未安装 |
| 界面文案使用 IPC、socket、JSON 等实现术语 | 核心流程只说明：Codex Desktop 运行时为实时检测，未运行时回退日志、只能覆盖有限的等待状态，无需 Hook |
| Claude Code 仍需要可选的增强检测 | Claude 保留独立的预览 → 应用 → 移除流程，签名和文件合并规则不变 |

## 归属检测

`HookSetupCoordinator.hasManagedEntries() throws -> Bool` 只读扫描设置文件的
`hooks` 对象，任何事件下带有本应用标记的条目都算数，因此旧版本写入、命令文本
已过期的条目也能被识别，用于旧版清理入口。文件不存在返回 `false`；文件不可读
或不是有效 JSON 抛出 `HookError.malformedSettings`，由调用方决定降级方式
（Agent 页对 Codex 不显示清理，对 Claude 显示「无法读取设置」）。`loadSettings`
把所有 JSON 解析失败都归一为 `malformedSettings`，界面因此显示“设置文件不是
有效的 JSON”，而不是误报为权限问题。

## 边界

1. 不新增任何自动写入：Codex 路径只读；Claude 的安装/移除仍要求预览和显式点击。
2. 清理改为处理器级过滤：只删除 `hooks` 数组里带标记的命令处理器，保留同一
   matcher 组的其他处理器和字段；只有被清空的组才会移除。写入前先备份，备份
   复制失败则中止清理、不写文件；`install()` 同样不再忽略备份失败。
   `preview()`/`install()` 刷新过期命令时也只重写自有的命令处理器，不再整组
   替换，matcher 字段与第三方处理器保持不变。
3. 状态展示不做本地缓存或推测：`connecting` / `connected` / `fallback` 直接来自
   coordinator 的实际发布值。
4. 真实 `~/.codex`、`~/.claude` 不参与任何测试；测试全部使用临时目录。
5. 新增源码使用目录通配的项目结构，需要在构建前运行一次 `xcodegen generate`；
   本轮未运行 xcodegen、构建或应用。

## 测试

- `HookSetupCoordinatorTests` 新增：缺文件、仅有他人 Hook 与配置、旧版本自有
  条目、Codex 安装/卸载生命周期、provider 互不串扰、损坏 JSON 归一为
  `malformedSettings`；清理只删带标记的处理器（共享 matcher 组保留）、清理前
  备份、备份失败时中止且不改文件；预览/安装刷新过期命令时同样保留共享
  matcher 组。
- `AgentSettingsLogicTests` 新增：已安装优先、普通已存在文件不算安装、
  自有但过期条目算需要更新。
- 既有 14 个预览、安装、卸载与冲突保留测试未改。
