# 产品化版本验收

> 后续 Codex 无 Hook 改造与最新预览版见
> [codex-hook-free-validation.md](codex-hook-free-validation.md)。
> 下文 Hook 检查和 500 项测试为前一阶段记录。

完成日期：2026-10-18（Asia/Shanghai）。工作从 2026-10-17 夜间开始。

分支：`codex/product-settings-polish`。基线：`db27b5e`。

## 可运行版本

固定预览应用：`build/Productization/AIUnderlay.app`。

```sh
open "/Users/lingsmbp/Documents/aiwork/ai-underlay/build/Productization/AIUnderlay.app"
```

再次打开应用或按 `⌘,` 可以进入设置。应用为本地 Debug 构建，没有发布、签名
分发、公证、提交、合并或推送。源码改动留在新分支工作区；原有 `.superpowers/`
未跟踪内容保留。

## 自动验证

| 检查 | 最终结果 | 证据 |
|---|---|---|
| `xcodegen generate` | 通过，新增 UI 和测试文件均进入工程 | `AIUnderlay.xcodeproj/project.pbxproj` |
| `Scripts/test.sh -derivedDataPath build/Productization/DerivedData` | 500 项，497 通过，3 按条件跳过，0 失败 | `build/Productization/tests-final.log`，最终测试结束于 2026-10-18 00:13:04 |
| Debug `xcodebuild ... build` | `BUILD SUCCEEDED` | `build/Productization/build.log` |
| `Scripts/check-domain-purity.sh` | `OK` | 最终执行退出码 0 |
| `git diff --check` | 通过 | 最终执行退出码 0 |

三个跳过项都是需显式环境变量启动的图片导出测试：
`AuroraAlignDumpTests`、`GlassPreviewTests`、`V5FidelityDumpTests`。本轮没有修改
Domain 或 Overlay 渲染文件，因此未额外生成这三组离线图片。

新回归覆盖设置保存失败后重试、损坏设置备份、停止旧连接后的迟到结果、刷新
生命周期、近期缓存强制失效、代理协议与端口/凭据校验、主题按服务商解析、
恢复范围隔离与材质参数有效值。

构建仍有既有编译提示和 XCTest 期间的系统服务日志；没有将零失败表述为零警告。

## 原生窗口检查

使用本机实际构建应用，通过原生辅助功能树与窗口截图检查，非 HTML 或离线
渲染图冒充实机 UI。

| 流程 | 实际观察 |
|---|---|
| 设置入口 | 旧版本系统 Settings 菜单可复现空白窗口；新版本 `⌘,` 打开正式侧栏设置窗口 |
| 页面组织 | 六页均可进入；日常/高级分组、统一标题、折叠项与禁用提示可见 |
| 服务商连接 | 实际 Codex 连接检查返回“1 个服务商取得有效额度”；未启用的 Claude 保持关闭 |
| 离线预览 | 选择“Agent 正在运行”后出现持续横幅；切到运行引擎仍保留；退出后诊断显示“实时”、Codex valid 和两个额度窗口 |
| 代理输入 | 输入 `not-a-proxy` 后显示协议错误并禁用保存；仅修改草稿，未保存测试代理 |
| Hook 配置 | 生成预览前“应用 Hook”禁用；预览后仅对应 Codex 的按钮启用；随后取消，未修改真实 Hook 配置 |
| 主题 | 从内置默认切到“明亮示例”，显示两项个人覆盖仍保留；随后切回原主题 |
| 诊断 | 可见显示器、覆盖窗口、实时/预览、服务商、刷新和保存状态，不展示代理地址或会话内容 |

检查期间临时选择的主题与预览均已恢复，代理草稿已清空；保留原有服务商、
布局、颜色与动效偏好。没有安装、更新或卸载用户真实 Hook，没有改全局系统
辅助功能或外观设置。

## 验证边界

- 原生检查环境为一个无刘海显示器、深色外观；外接多屏、刘海硬件、浅色外观、
  VoiceOver、系统 Reduce Motion 动态切换及最小窗口尺寸缩放尚未专项实机验收。
- 设置窗口与真实 Codex 数据经过检查；菜单栏弹窗的新增空状态和缓存提示主要
  由模型测试、代码审查与构建覆盖，没有把它们宣称为全部实机交互验收。
- Hook 写入、无 CLI 与磁盘写入失败路径使用自动测试/审查覆盖，没有为了验收
  删除实际 CLI、修改真实 Agent 配置或破坏用户设置目录。
- 长时间 CPU、内存、系统菜单点击穿透和所有渲染场景仍沿用既有测试边界；
  不是本轮完成的硬件性能验收。

## 交付导航

问题与可行方案见 `2026-10-17-product-review.md`；完整执行计划见
`../superpowers/plans/2026-10-17-product-settings-polish.md`。布局、主题、连接三个
子任务均指定 `group/auto-deepseek-v4-1-flash`、推理等级 `max` 并已完成。
