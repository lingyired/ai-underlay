# 设置布局产品化记录

日期：2026-10-17（完成于 2026-10-18）。范围：`SettingsRootView.swift`、`SettingsWindowController.swift`、
`AppearanceTab.swift` 和新增的 `SettingsPreviewCatalog.swift`。未修改
`SettingsStore`、其他设置页、渲染器、`LanePlanResolver` 或数据模型。

## 审计

- 原根视图用六个等高标签组织页面，固定宽高窗口没有
  `NSWindow.StyleMask.resizable`。外观页把布局、覆盖层、动效和调试样例放在
  同一条长表单里，重要依赖也主要藏在 footer 中。
- 布局依赖没有完整反映到控件状态：关闭覆盖层后仍有可调的动效参数；关闭
  Agent 动效或开启 Reduce Motion 后，节奏和扫光仍可调整，但不会显示。
- 预览直接使用 `full`、`agentAllSignals` 等持久化键。界面没有全局预览提示，
  用户离开外观页后容易把样例额度误认为自己的真实额度。
- 单条布局固定选择 `supportedProviders` 顺序里第一家启用的服务商，也就是
  Codex 优先；弹窗则列出所有启用的服务商。不能仅靠调整
  `enabledProviders` 数组顺序改变单条显示对象。
- 无拆分模式把同一服务商的窗口嵌套在同侧；设置界面不需要承诺具体绘制层级，
  只说明窗口会留在同一侧。
- 隐藏菜单栏图标后，当前 `AppDelegate` 的再次打开路径会打开设置窗口，这是
  恢复图标的实际入口。
- `SettingsStore.save()` 失败时仅内存设置生效。根视图需要持续显示真实错误，
  并在重试成功前避免任何“已保存”暗示。

## 本次调整

1. 使用原生 `NavigationSplitView` 与 `.listStyle(.sidebar)`，把外观、主题和
   服务商放在「日常」，把运行引擎、Agent 集成和诊断放在「高级」。六个页面
   全部保留，每个页面有统一标题和简短说明。
2. 设置窗口改为可缩放，默认内容尺寸 `980 × 700`，最小尺寸 `760 × 480`；
   再次打开最小化窗口时会先还原。
3. 外观页按「菜单栏排列」「菜单栏覆盖层」「Agent 动效」「离线预览」分组。
   无效的布局、拆分和动效控件会禁用，并在控件附近或 tooltip 中说明原因。
4. 动效微调折叠在 DisclosureGroup 中。关闭覆盖层、关闭 Agent 状态动效、
   开启 App 内减弱动效，或 macOS 开启「减弱动态效果」时，微调参数禁用。
   OS Reduce Motion 只影响显示与控制可用性，不改写已保存的应用内偏好。
5. 预览下拉仍保存原始 fixture key，但显示可理解的中文名称和一句具体说明。
   预览横幅固定在其他页面内容上方，可一键恢复实时额度。
6. 根视图读取 `store.persistenceError`，持续显示「设置尚未保存」横幅和
   「重试保存」按钮；`theme` 等页面自己的反馈仍各自负责即时操作结果。
7. 单条布局说明明确写出“Codex 优先”，以及 Claude-only 的操作：到「服务商」
   关闭 Codex，只保留 Claude Code。没有新增选择模型，也没有伪造可切换的 UI。
8. 隐藏图标提示指明再次打开 App 会进入设置。无拆分标签与说明只写“同侧嵌套”，
   不在设置页重复描述渲染层级。
9. 窗口最小高度最终设为 `480`，宽度下限保持 `760`。长表单与 Hook 预览使用
   滚动区域，减少小屏幕下固定窗口尺寸的限制。
10. 原生 AX 检查后，布局控件不再共用按“当前布局”推导的辅助文案：双侧起点
    永远说明自己只在双侧布局可用，单条方向永远说明自己只在单条布局可用。
    Tooltip 只描述控件功能与可用条件，不根据 Toggle 的当前值宣称“已生效”。

## 保留边界

- 所有控件继续使用现有 `AppSettings` 键和 `SettingsStore.update`；没有新增设置
  字段、第二套存储或 fixture key 映射。
- 真实额度、Provider 开关、双侧拆分默认色与个人覆盖链、状态优先级、渲染器、
  `SettingsStore.changes` 的发布语义均未改变。
- 预览仍走 `FixtureSnapshots` 和真实渲染路径。界面翻译只发生在显示层。

## 验证

本子任务只在共享工作区修改上述文件，没有运行 `xcodegen generate`、完整测试、
Debug 构建或启动 App，由主任务统一执行这些集成步骤。

已执行：

- 四个改动文件 `swiftc -parse` 通过。
- 使用最小依赖桩分别 typecheck `AppearanceTab`、`SettingsRootView` 和
  `SettingsWindowController`，通过。
- 核对 `FixtureSnapshots.allKeys` 与中文目录：17/17，无遗漏、无多余、无重复。
- 改动文件 `git diff --check` 通过。

尚待集成验证：

- 完整 Xcode 测试和 Debug 构建。
- 实际窗口缩放、侧栏选择、深色外观和 VoiceOver。
- 系统 Reduce Motion 开关后的原生窗口行为。
- 真实菜单栏预览横幅与退出预览后的实时数据恢复。

上述为子任务交付时的阶段记录；主任务的最终检查与剩余边界见同目录
`validation.md`。
