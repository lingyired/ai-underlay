# Codex 无 Hook 版本验收

完成日期：2026-10-18（Asia/Shanghai）。分支：`codex/product-settings-polish`。
本轮在既有产品化改动上继续，没有提交、合并、推送或发布。

## 当前行为

1. Codex 默认自动连接本机 Desktop；实时连接覆盖的会话优先采用明确生命周期
   与待处理请求，其余会话继续读取本地索引和 rollout 日志。额度仍来自 CodexBar。
2. Codex Hook 不再参与状态合并，设置页没有 Codex 安装、预览或应用 Hook 按钮。
   旧条目仅在证明有本应用标记后提供默认折叠的手动清理入口。
3. 断线或不兼容时回退日志，界面说明待答/批准覆盖可能不完整；断线不能生成
   完成，也不能直接抹掉已观察到的待处理请求。每 30 秒重连一次。
4. Claude 保留可选增强 Hook。刷新和清理都只处理自有 handler，保留共享 matcher
   组中其他工具的 handler 与字段；先备份，备份失败则中止写入。
5. 原生 Swift 适配层来自 MIT Codex Pacer，不增加 Python 依赖。许可证全文随 app
   打包。原始 IPC 帧仅在内存解析，状态中不保留提问、回答、命令或输出正文。

## 自动验证

| 检查 | 结果 | 证据 |
|---|---|---|
| `xcodegen generate` | 通过，新适配层和测试均进入工程 | 工程文件 |
| `Scripts/test.sh -derivedDataPath build/CodexHookFree/DerivedData` | 535 项：532 通过、3 条件跳过、0 失败；结束于 12:36:32 | `build/CodexHookFree/tests-final.log` 与 xcresult |
| Debug build | `BUILD SUCCEEDED` | `build/CodexHookFree/build.log` |
| Domain purity、diff whitespace | 通过 | `Scripts/check-domain-purity.sh`、`git diff --check` |
| Status-item hit area | 固定 36pt；图标居中，较宽符号自动扩展 | `PanelGeometryTests` 2 项 |
| MIT 许可证打包 | 构建产物中存在全文 | `Contents/Resources/CodexPacer-LICENSE.txt` |

三个跳过项仍为需环境变量启用的图片导出测试，未修改 Domain/Overlay 渲染。
本次新增协议测试 11 项、状态/优先级测试 11 项；Hook 与设置回归也纳入全套测试。
关键覆盖包括异步提问期间仍可运行、明确回复才清空等待、批准阻塞、终止与尾部
补丁、下一个 turn、长任务心跳、owner 断开/重连、revision gap 与批次原子回退、
targetClientIds 隔离、内部会话过滤、保守日志回退和生命周期先于 attention 的帧序。
保留项目既有编译警告与 XCTest 系统服务日志，不把零失败描述为零警告。

## 本机原生检查

运行实际 Debug app，通过辅助功能树和原生窗口截图检查，未使用 HTML 或离线
渲染模拟应用。最初进程为 PID 29457，路径为
`build/CodexHookFree/AIUnderlay.app/Contents/MacOS/AIUnderlay`；最终重新打包后
再次启动检查同一路径（最终 PID 37734，框架 SHA-256 与最终构建产物一致）。

| 流程 | 实际观察 |
|---|---|
| 设置入口 | `⌘,` 打开六页侧栏设置 |
| Codex 自动检测 | 卡片显示“自动检测已连接”和“自动检测，无需 Hook”；无 Codex 安装/应用按钮 |
| 实时数据覆盖 | 诊断报告显示实时连接覆盖 3 个会话；Codex 运行 3、等待 0，真实额度 valid、2 个窗口 |
| 旧 Hook | 仅出现默认折叠的旧版清理；展开可见手动移除按钮与备份说明，随后折叠，未执行移除 |
| Claude | 保留独立的可选预览/应用流程；预览前应用禁用；未安装/更新/移除 |
| 真实配置完整性 | `~/.codex/hooks.json`、`~/.claude/settings.json` 检查前后 SHA-256 完全相同 |

没有为验证主动制造真实批准或提问请求，没有修改 Codex/Claude 配置、账户、
服务商选择、主题或布局。状态迁移与损坏配置的写入测试均使用临时目录。

## 验证边界

- 真实 Desktop 连接、会话覆盖与原生布局已检查；待答、批准、断线和协议变更
  路径由合成协议/状态测试验证，没有宣称已在每种宿主实测。
- Codex Desktop IPC 为内部协议，后续仍可能变化；日志回退用于维持基础检测，
  不能承诺 CLI/IDE/远程环境的完整等待状态。当前仅连接本机。
- 沿用单显示器、无刘海、深色外观验收边界；长时间性能、多屏、刘海与 VoiceOver
  不属于本轮新增实机结论。

## 运行版本

打开 `build/CodexHookFree/AIUnderlay.app`，进入“Agent 集成”即可查看自动检测。
设计见 `../superpowers/plans/2026-10-18-codex-without-hooks.md`，协议归属见
`codex-ipc-port.md`，设置细节见 `codex-hook-free-ui.md`。
