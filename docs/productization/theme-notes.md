# 主题设置产品化记录

日期：2026-10-17。范围：`AIUnderlayKit/UI/ThemeTab.swift` 及其直接测试。未修改
`ThemeResolver`、`ThemeStore`、`SettingsStore` 或任何渲染器。

## 审计

- `ThemeStore` 的 `activeTheme` 是当前可渲染的主题文档；选择未知或暂时损坏的
  id 时，它会保留上一次正常文档，否则渲染器使用内置 V5。
- `ThemeResolver` 的固定优先级是“个人外观 > 主题文件 > V5 默认”。原界面用
  硬编码的 V5 / Provider 颜色作为取色器 fallback，因此即使主题已切换，色块仍
  可能显示默认值，而不是当前主题的解析值。
- 个人外观保存在 `settings.appearance`，切换 `activeThemeId` 不会清除它们。
  原界面既没有明确说明这层覆盖关系，也没有局部恢复入口。
- 材质滑块的 getter 读取的是个人字段或 V5 默认，未经过
  `GlassMaterialOverrides.resolve`。主题材质和渲染器 clamp 因而可能显示错误。
- 操作反馈只存在于表单末尾的文件工具区域，上方按钮成功后很难看到结果。
- 当前版本没有真实未读完成记录：`unread` 只可能来自 fixture signal。界面必须
  把它标为“仅预览”，不能暗示生产环境已经监控或通知未读完成。

## 本次调整

1. 顶部显示当前实际主题、个人覆盖数量和“个人设置优先于主题”的说明。主题
   切换只更新 `activeThemeId`，个人外观原样保留，并立即提示保留数量。
2. 自定义颜色拆为 Provider 玻璃色、额度色、单 Provider 双侧拆分色和状态灯色
   四个独立范围。每一项显示来源，可单项恢复；每个分组另有“恢复本组”。
3. 提供“恢复全部外观…”二次确认。该操作只清空个人外观，保留主题、Provider
   开关、额度数据和渲染状态。
4. 颜色 fallback 统一经 `ThemeResolver.glassTheme` 解析当前主题；拆分默认色仍
   经 `SplitLaneColors.baseColor` 从 Provider 的有效额度色推导。
5. 材质滑块经 `GlassMaterialOverrides.resolve` 读取当前有效值，受
   `GlassMaterialParameters.clamped` 同一规则约束；单项删除只移除对应字段。
6. 自定义颜色、玻璃材质与主题文件工具默认折叠。操作状态固定在表单顶部，
   保存失败时会区分“本次运行已生效但未保存”，并提供重试保存。
7. 界面按职责拆为 `ThemeTab`、颜色、材质、文件工具和状态提示文件；有效值、
   来源判断、单项写入与分组恢复统一由 `ThemeTabPreviewState` 提供，测试直接
   覆盖同一实现，不另写镜像逻辑。

## 保留边界

- 额度真实性、Provider 开关、额度长度、状态优先级与数据新鲜度逻辑未改。
- Provider 玻璃色、额度色、拆分色和信号色仍相互独立。
- “未读完成（仅预览）”仍通过 `ThemeResolver` 解析颜色，但文案明确披露真实
  生产未读监控与通知尚未接入。
- `ThemeTab.softnessLabel` 与 `ThemeTab.softnessNote` 的公开发布文案和测试契约
  保持不变。
- `SettingsStore.changes` 仍是所有写入的唯一发布出口；界面继续使用
  `settings.update`。

## 验证边界

- 新增纯状态回归测试覆盖各 Provider 的主题值、字段是否由主题提供、个人覆盖
  保留、分组恢复隔离与材质 resolved/clamp 行为。
- 本任务不运行 `xcodegen generate`、构建或测试；由主任务统一执行完整项目验证。
- 真实窗口视觉检查由主任务在统一构建版本上完成；本记录不把离线检查描述成
  WindowServer 或真实菜单栏验收。
