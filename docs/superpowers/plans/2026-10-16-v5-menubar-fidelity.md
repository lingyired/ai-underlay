# AIUnderlay：V5 菜单栏视觉复刻执行计划

日期：2026-10-16（Asia/Shanghai）。执行模型：`group/auto-deepseek-v4-1-flash`。

用户已明确授权：先写计划，然后直接交给上述模型实施；由代理自行做产品与实现判断，无需等待用户回答。不要只回复计划、建议或请求确认，完成代码、可运行构建、验证与早晨可审阅的视觉证据。

## 1. 执行入口与基线

专用工作区：`/Users/lingsmbp/.codex/worktrees/v5-menubar-fidelity/ai-underlay`。

分支：`codex/v5-menubar-fidelity`。起点：`551e647d0a6fe6a6e9790bad87a96249cafe0689`，来自上一轮 `codex/glass-spectrum-motion-visibility`。当前原始 checkout 的 main 仍是 `a2725dc`，比这轮工作旧；不能从 main 重新实现、覆盖或遗漏中间修复。

先读取用户的 AGENTS 指令、`/Users/lingsmbp/.codex/RTK.md` 与适用仓库规范。开始时检查本工作区 `git status`，保留本计划。只在本分支实施；保留其它 worktree 和 `.superpowers/`。此次交付本地可审阅差异及构建，不推送、不合并、不发版；没有明确提交授权时也不自行提交。

参考的优先级：

1. 用户最新要求是还原参考里的菜单栏视觉。当前消息没有附件、可见 Page 或链接，因此明确采用已在仓库保存的 `docs/visual-reference/AIUnderlay-Glass-Material-Lab-v5.html`，以 Aurora Glass 为主要视觉方向；Acrylic 只作为材质差异对照，不新增模式系统。
2. `docs/visual-reference/glass-experiment-v5-selected.json` 是用户之前选定的参数。它优先于 HTML 初始化 defaults；保留用户后续去白边、去顶部内阴影的修正。目标是参考的视觉语言和动态形态，不是重引入已明确拒绝的白边。
3. 实施前读 `docs/visual-reference/glass-motion-visibility/validation.md` 和 `docs/visual-reference/glass-fidelity/{execution-status,validation,blur-spike}.md`。其中数量、PID、历史路径不是本轮验证结果。
4. 本轮策划已直接查看 `glass-motion-visibility/live/live-traveling-on-cycle.png`，并核对 HTML/CSS/Canvas 源码及当前 Swift。旧截图显示射线已经会独立起伏，但仍偏粗、偏白、像发光竖柱；不要重复上一轮只解决“它会动”的工作。

执行环境的浏览器安全策略已拒绝 `file://` 本地 HTML 导航。不得通过转成本地 HTTP、换浏览器、原始 CDP 或其它方式绕过这次拒绝。可继续读取本地源码、查看已有 PNG，生成和查看原生渲染证据。没有获准取得的新浏览器参考图时，明确记录“V5 源码/参数对照，未新增浏览器截图”，不能声称完成浏览器与原生逐像素一致验证。

## 2. 设计决定与成功标准

选择在现有原生 CALayer / 缓存帧序列渲染器上精修。另两种方案——嵌入 WebView 复播 Demo、全面重写为 Metal——会扩大范围并引入系统菜单栏层级或性能变量，这次不采用。保留一种运行光谱引擎。

视觉目标是：深色但有透光层次的玻璃底，清晰而克制的嵌套额度色，细密且底部扎根的光线，随横向波包独立变化的高度和明暗，局部而柔和的反光，以及与运行光谱共存的状态灯带。不能靠整条增白或单一透明度来制造“玻璃”。

| 部分 | 目标行为与验收 |
| --- | --- |
| 额度 | 周/短时额度长度继续来自 NestedGauge；Codex 蓝、Claude 暖铜；外暗内亮；已耗尽区保持黑，unknown 保持中性，绝不模拟额度 |
| 玻璃 | 主题色只负责玻璃染色和反光；颜色有纵向深浅，避免整条灰白、顶部白线或凹槽内阴影；柔化滑块改变实际输出 |
| 射线 | 底部统一基线、尖端柔和；局部光峰改变射线本体的高度和 alpha，远离光峰的区域较暗；避免粗白栅栏、锁步伸缩和循环停顿 |
| 光场 | 主峰+较弱次峰，局部 screen 类合成；白色仅用于细小高光。关闭横穿扫光仍有独立起伏，不能整条静止 |
| 状态 | Error > Waiting > Unread；Running 独立存在。Waiting/Error/Unread-only 不启动运行光谱，混合状态同时可见运行与提示；禁止将 completed 冒充持久 Unread |
| 系统 | 不盖住菜单文字、不抢点击；双 Lane 不串色、不越刘海，屏幕/scale 切换能更新；Reduce Motion 下清除持续动画（包括 mask） |

选定参数：blur 17、ambientGlow 0、grain 0、rayDensity 100、quotaOpacity 100、agentThemeStrength 100；Codex glass `#62ac96`、Claude glass `#ffffff`；额度 `#69bfff` / `#ffb08a`；Running `#d9eeff`、Error `#ff7596`、Waiting `#ffe1a0`、Unread `#64f1bd`。白色主题不等于全幅白色蒙层。

HTML 的默认 ambient/glow 并非当前用户选择。主交付采用 selected JSON 与当前用户覆盖值。另生成一组带适量 ambient 的纯 fixture 对照，帮助判断材质，不能偷偷修改真实用户设置。V5 speed=48 的公式是 `0.18 + 0.44 * sqrt(0.48)`，约 0.485 Hz；现有 Swift 注释把它说成约 0.70 Hz 不精确，应纠正文档。保留用户实际节奏；对齐静态形状时使用归一化时相，比较动画时分别注明真实秒数，不为追求一致而取消节奏设置。

## 3. 阶段 A：建立本轮可比较基线

预计 10–20 分钟，不是承诺完成时间。开始后不等待用户。

检查 `GlassQuotaRenderer`、`GlassMaterialRenderer`、`SpectrumWaveModel`、`GlassSpectrumRenderer`、`AttentionLightRenderer`、`GlassLayerHost`、`LaneRenderSpec` 和现有预览测试。先确认已经具备：逐 ray 波形、缓存帧动画、闭环 keyTimes、softness 输出、两个扫光开关、设置落定后刷新、去顶部白边。

在 `docs/visual-reference/v5-menubar-fidelity/` 建立本轮 `execution-status.md` 与 `validation.md`，记录基线 SHA、实际参数、软件/屏幕条件和命令。渲染本轮 before 到 `build/v5-menubar-fidelity/before/`，保留少量代表性 PNG；不要把旧目录/旧预览当作本轮 before。

固定 fixture：Codex 82/55、Claude 67/36，双 Lane 为主要对照；补单 Lane。参数必须与 selected JSON 一致。统一逻辑宽度、30/32/34pt 高度、1x/2x，时相 0/0.25/0.5/0.75，并至少记录一个完整周期。渲染器实际支持什么写清什么，优先复用已有 sampler。

出口：有可重现基线、逐项差距表和具体待改文件，不因为全量测试历史通过而跳过视觉比较。

## 4. 阶段 B：还原射线、光场与时间变化

预计 30–60 分钟。优先文件：`SpectrumWaveModel.swift`、`GlassSpectrumRenderer.swift`，以及本轮需要的针对性测试。

从 V5 `repaint` 逐项核对射线密度、像素宽度、底部 alpha、高光宽度、焦点 sigma、半径上限和两道光场权重。V5 Aurora：`n=max(24,round(w/8.5*(0.55+density*1.25)))`；软 halo 宽 4.2 CSS px，core 宽 1.16 CSS px；半径 `min(w*0.28,205)`；射线高度 `h*(0.22+0.52*crest+0.28*focused)`；两波权重 0.61/0.39。参考是单位核对起点，不是要求不加判断地替换常量。

特别检查当前模型取消 205pt 半径上限、按整个宽度扩峰、把两个时间频率硬改为整数后对形状/运动的影响。区分空间相位与时间相位。V5 时间系数 1.25/0.82 和主/次光峰速度 0.78/−0.31 不组成一秒短循环；若需要提升还原度，应采用有预算的较长超周期或经验证的周期近似，并把运动误差写出。不能把四张帧图一循环就称为复刻，也不能为精确无穷时序堆积大量位图。

先解决射线偏粗、整体过白、底部亮线连成栅栏的问题，再微调幅度。以 1x 与 2x 的实际像素对齐，区分 pt、CSS px 和 device px。状态色仍来自 signal lights；Provider phase 可不同，状态语义不混用。

保持 `showTravelingLight=false` 时 crest 停留但波形继续变化；`showAttentionSweep=false` 不影响 Running；TPS 只调节奏，不改色和幅度。切换设置、尺寸或 signal 时不无故重置动画起点。

保留缓存和播放架构。不得每 ray 一个 layer，不引入逐帧主线程绘图、随机纹理刷新或 display link。基线缓存预算为 16MiB，要实测单序列与总缓存而非仅检查常量；连续 animation layer 预算按整个 Lane（含 mask/ambient/attention）计算。超宽/2x 必须真实守住字节预算；有明确证据才调整预算，并在报告解释取舍。

出口：固定时相的高度/亮度确实改变，1x/2x 细线清楚，局部峰可见，完整周期无明显顿停，traveller 开关不破坏起伏，动画/缓存预算有实测值。

## 5. 阶段 C：校准玻璃、额度与状态层

预计 25–50 分钟。优先文件：`GlassQuotaRenderer.swift`、`GlassMaterialRenderer.swift`、`AttentionLightRenderer.swift`；仅必要时涉及 resolved spec/defaults。

按底槽 → 额度 → glass tint/反射 → 射线 → hint/边缘灯带的顺序检查实际合成。不要叠加多层白色来补偿菜单栏系统合成。保留 `551e647` 去除白色顶段和 envTop 的修正，不以忠实复刻为由还原用户刚拒绝的效果。

额度嵌套长度、外暗内亮和已耗尽黑区不可改变；小于 1pt 的真实额度只用独立 cap 辅助识别，不能扩大真实填充。glass tint、ambient、rays 都不能重新点亮已耗尽区域或相邻 Provider。

检查 softness 0/17/32 的真实输出差异，以及 selected 的 ambient=0/grain=0 是否确实关闭对应贡献。渲染玻璃反光的预模糊与桌面 backdrop blur 是不同能力；继续利用已有实验结论，不声称预模糊等于真实背景采样。除非本轮已有可验证且性能合格的公开 API 路径，不重新探索私有 CGS、系统权限或窗口层级黑魔法。

Waiting 的黄色顶部线及底部暖灯带属于状态语义，应保留；与已删除的无状态白边区分。核查 Error/Waiting/Unread-only 与 Running+attention 共存，颜色和可见区域相互独立。优先只调整渲染器，不扩展 Hook/Inbox/数据采集。

出口：selected 参数下视觉完整；白主题不过曝；0%、未知、stale、0/100 配额、单/双 Lane 与关闭扫光均合理；设置键及热刷新兼容。

## 6. 阶段 D：自动化、实机条件与性能验证

预计 15–35 分钟，硬件缺失只阻塞对应检查，不阻塞独立工作。所有命令在本轮专用 worktree 中执行：

```bash
xcodegen generate
./Scripts/check-domain-purity.sh
TEST_RUNNER_GLASS_PREVIEW_DUMP=1 TEST_RUNNER_GLASS_PREVIEW_OUTPUT="$PWD/build/v5-menubar-fidelity/after" ./Scripts/test.sh -derivedDataPath build/DerivedData
xcodebuild -project AIUnderlay.xcodeproj -scheme AIUnderlay -destination 'platform=macOS' -derivedDataPath build/DerivedData build
git diff --check
```

先检查预览测试读取 `GLASS_PREVIEW_*` 的既有 Xcode 环境传递方式。上面 `TEST_RUNNER_` 前缀是 runner 传递机制，必须确认确实产生了本轮 after PNG，不能仅看到测试退出 0。若当前机制需要调整命令，记录实际有效命令。只为真实回归写测试，不为颜色常量或实现细节凑数量。

必须覆盖：Known 0 的黑区、unknown/stale、双区裁切、1x/2x、两扫光开关独立、Idle/Reduce Motion/teardown 清理、keyframe 闭环、复用与实际缓存字节、theme/settings round-trip。测试完再有代码变更，只重跑相关检查和必需的完整交付检查。

实际菜单栏验证优先使用用户当前设置与真实状态。需要可控 fixture 时，先审查现有 live-capture.sh：它会写 settings 并重启 app；必须使用独立配置或有备份、trap、checksum 校验的短暂替换，结束恢复精确原文件。不能迁移/覆盖用户持久主题或 Agent 数据，也不能杀其它项目进程。默认不覆盖 /Applications 内安装版本；可运行本分支 Debug app 并记录恢复入口。

若屏幕锁定、录屏权限缺失或硬件不可用，继续离线验证，不开安全权限，不叫醒用户。将“原生离线”“fixture 驱动的真实菜单栏”“真实 Agent 状态”分开标记。做不到实机录屏就直说，不能用 `CALayer.render(in:)` 伪称 WindowServer 合成验收。

可用条件下记录至少 8 秒实际菜单栏：Running、Running+Waiting、traveller off，并检查菜单点击穿透、文字可读性、即时设置切换。前后用相同屏幕/参数各采 60 秒 CPU/RSS；有时间再扩到 300 秒。WindowServer 全局值只能作为混杂指标，不宣称是本 app 独占 GPU。没有同条件 before 的数字，不能给“性能提升”结论。

出口：所有实际命令及数量均来自本轮日志；失败/skip 有原因；构建存在；剩余硬件项目明确。

## 7. 阶段 E：早晨可审阅交付

预计 10–15 分钟。生成 `docs/visual-reference/v5-menubar-fidelity/review.md`，让用户用 2 分钟看懂结果。

包含：本轮分支/基线/HEAD、改动文件和原因；相同参数 before/after 联系图（原尺寸与放大裁切）；0/0.25/0.5/0.75 四时相对照；可用时 8 秒以上录屏；Debug app 绝对路径和启动方法；实际测试/构建/性能结果；仍存在的视觉差距和未验证项目。少量代表性 PNG 留在文档目录，大矩阵和视频保留 build 路径，避免无意义重写 148 张历史预览。

报告不能只写“所有测试通过、完美复刻”。分别标为实现状态、自动化状态、实机状态、视觉差距；用户的最终人工审美验收留到早晨，不把自己看过截图当作用户已认可。

每个阶段结束更新 `execution-status.md` 的实际进度、改动、日志和下一步，保证中断后可续接。连续三次修复同一问题失败时停止该错误路径，写出具体位置、证据、可疑假设和下一项区分性检查；继续其它独立工作，不反复盲调 alpha。

完成后在接收执行的聊天中直接给出简洁结果和 review.md 链接，不要请求“是否继续”。
