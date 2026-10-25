# 服务连接、引擎与 Agent 设置产品化记录

日期：2026-10-18。范围：`ProvidersTab.swift`、`EngineTab.swift`、
`AgentTab.swift`、`ConnectionSetupLogic.swift` 及其纯状态测试。没有修改
`AppCoordinator`、`SettingsStore`、额度模型、渲染器或既有 Hook API。

## 审计与实施

| 页面 | 原问题 | 当前行为 |
|---|---|---|
| 服务商 | 同步读取 `dataRevision` 和旧快照，`stale` 被写成“已登录”，点下测试就可能提前成功 | 观察真实的 `isRefreshingQuota` 发布值；必须看到 `true` 后才允许在 `false` 完成。检测中、应用关闭、上游关闭、未登录、不支持、不可用、过期和连接正常使用独立文案 |
| 服务商 | 目录元数据读取失败会遮住已经取得的真实快照；开关和上游操作可重叠 | 快照优先决定真实连接状态，目录仅补充上游状态；测试和上游启用互斥，所有异步任务显示进度并能防止重复触发 |
| 引擎 | 重新检测先写成功；代理不校验；托管安装是开发者占位；卸载吞错 | CLI 本地探测在 `startEngine()` 返回时立即呈现结果，与远端额度检查分开；代理限制为 HTTP/HTTPS/SOCKS5 并校验 host、port、路径和凭据；仅在管理文件存在时显示卸载；使用 `do/catch` 显示文件错误 |
| Agent | 基线文案暗示 Hook 是唯一活动来源；预览和安装使用 `try?` 后写成功 | 明确本地会话与 CLI polling 无需 Hook，Hook 只增强等待/错误时效；始终先预览再应用，安装、移除、预览和状态读取均执行 `do/catch`，没有自动写入 |
| Agent | 760×600 下预览与错误可能无法看到 | 整页使用外层 `ScrollView`，预览详情仍可展开并滚动 |

服务商与应用开关、CodexBar 上游开关、快照可用性、刷新生命周期仍是四个独立
概念。应用开关继续通过 `SettingsStore.update` 写入，未改持久化键、默认值或
发布语义。

## 状态规则

1. `ProviderConnectionStatus` 只将 `valid + 无本次错误` 识别为成功；`stale`、
   过期和失败永远不是“已登录”。
2. 真实快照可以在 catalog 不可用时继续展示；catalog 只用于显示名和上游
   enablement。
3. `ConnectionTestLifecycle` 要求先观察到刷新开始，再观察结束。仅点击按钮或
   读取旧快照不会完成检测。
4. `ProxyAddressValidator` 接受 `http`、`https`、`socks5`、`socks5h`，要求
   host 和 port；拒绝用户名、密码、控制字符、路径、query 与 fragment，错误
   文案不包含原始值。
5. Engine 的本地发现结果为“找到可用的 CodexBar CLI”，不声称已登录或额度
   可用；网络与登录状态由服务商页的真实刷新判断。
6. Agent 的 `HookSettingsStatus` 区分未安装、已安装、需要更新和读取失败；
   应用按钮只在当前 provider 的 preview 存在时可用。

## 回归边界

- 额度仍只来自 CodexBar 的真实 fetch；未引入 fixture、默认百分比、模拟额度
  或伪造吞吐。
- 应用级 provider 开关仍决定 scheduler 是否请求及 renderer 是否绘制。
- 双侧拆分颜色、主题解析、Reduce Motion、点击穿透和告警优先级未改。
- `HookSetupCoordinator.preview/install/uninstall/isInstalled` 的签名和文件
  合并规则保持不变；没有新增自动 Hook 修改。
- `SettingsStore.changes` 仍是设置写入的发布出口；本页未建立第二套设置状态。

## 验证

- `xcodebuild ... build`：完整 Debug 构建成功，包含父任务并行修改。
- `ConnectionSetupLogicTests`：8 个状态、生命周期和代理校验测试全部通过。
- `HookSetupCoordinatorTests`：14 个现有预览、安装、卸载与保留冲突配置测试
  全部通过。
- `git diff --check`：本任务文件通过。
- `xcodebuild test` 在未修改的 `ThemeTabTests.swift` 构造参数顺序处编译失败，
  因此本轮不算全量测试通过；上述 22 个测试直接对已构建的测试 bundle 运行成功。
- 未启动应用、未做真实设置窗口或菜单栏人工验收；本记录只覆盖编译和纯状态测试。

上述是子任务交付时的阶段记录。构造参数顺序已由主任务修复，最终全量测试、
构建和原生窗口结果以同目录 `validation.md` 为准。
