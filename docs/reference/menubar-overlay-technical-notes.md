# macOS 菜单栏覆盖层绘制技术方案

> 从 WandelBar 的 overlay 实现中提炼，供新项目直接复用。
> 结论先行：**不要改壁纸**，用无边框穿透窗口自己画；菜单栏高度必须问窗口服务器要；进度条用 CALayer 而不是 Core Image。

---

## 1. 方案概览

要在菜单栏区域绘制自定义内容（背景、进度条、额度条、状态指示），有三条路：

| 方案 | 做法 | 结论 |
| --- | --- | --- |
| A. 改壁纸 | 渲染一张处理过的整屏图，用 `NSWorkspace.setDesktopImageURL` 设为桌面 | 有致命限制：视频/动态壁纸没有可读静帧，换上去等于永久冻结；锁屏、全屏 Space 行为复杂 |
| B. 覆盖窗口 | 无边框、点击穿透、位于桌面与菜单栏之间的 `NSWindow` | **推荐**。壁纸完全不动，支持任意壁纸（含视频），实时性好 |
| C. 私有 API | SkyLight 注入 | 不稳定，系统更新即挂 |

新项目直接走 B。下面全部是 B 的实现细节。

### 1.1 三条绘制路径（按优先级）

```
                   ┌─ 有可读静帧壁纸 → 精确路径：复用壁纸渲染器，只显示条带区域像素
覆盖窗口的绘制 ────┤
                   └─ 无可读静帧（视频/动态壁纸）→ 兜底路径：NSVisualEffectView 背景模糊
                   
                   独立叠加层：进度条 / 额度条（CALayer，画在以上两者之上）
```

三条路径可以共存，各自独立。**进度条这类"叠加信息"永远走第三条，不要混进前两条。**

---

## 2. 窗口配置（最关键的一段代码）

```swift
@MainActor
final class MenuBarBandWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: .borderless,
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear          // 必须，否则整块不透明
        hasShadow = false
        ignoresMouseEvents = true         // 点击穿透，不抢菜单栏事件
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isReleasedWhenClosed = false

        // 关键：层级 = 桌面图标之上、菜单栏之下。
        // 这样菜单栏自己的图标/文字仍然画在我们上面，不需要做任何避让。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        // 跟随所有 Space，切 Space 不重建；不参与 Cmd+Tab 循环。
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
}
```

### 2.1 层级数值参考（实测，macOS 26/27）

| 常量 | 实测值 | 含义 |
| --- | --- | --- |
| `kCGDesktopWindowLevel` | -2147483623 | 桌面壁纸 |
| `kCGDesktopIconWindowLevel` | -2147483603 | 桌面图标 |
| **本方案使用** | **-2147483602** | 图标之上 |
| `kCGNormalWindowLevel` | 0 | 普通 App 窗口 |
| `kCGMainMenuWindowLevel` | 24 | 菜单栏本身 |

选 `desktopIconWindow + 1` 而不是更高的层级，原因：**层级一旦高于菜单栏，就会挡住菜单栏图标**，你就得自己做避让。放在下面，系统帮你处理一切。

### 2.2 多屏

每块屏一个窗口，按 `display.id` 建索引管理：

```swift
@MainActor
final class MenuBarOverlayController {
    private var windows: [String: MenuBarBandWindow] = [:]

    func update(_ configurations: [OverlayBandConfiguration]) {
        var seen: Set<String> = []
        for configuration in configurations {
            seen.insert(configuration.display.id)
            guard let settings = configuration.settings else {
                windows[configuration.display.id]?.orderOut(nil)   // nil 表示这块屏不画
                continue
            }
            let window = windows[configuration.display.id] ?? {
                let created = MenuBarBandWindow()
                windows[configuration.display.id] = created
                return created
            }()
            window.apply(...)
        }
        // 显示器拔掉的残留窗口要清掉
        for (id, window) in windows where !seen.contains(id) {
            window.orderOut(nil)
            windows.removeValue(forKey: id)
        }
    }
}
```

窗口坐标（AppKit 左下原点）：

```swift
setFrame(
    NSRect(
        x: display.frame.minX,
        y: display.frame.maxY - totalHeight,   // 贴屏幕顶边
        width: display.frame.width,
        height: totalHeight
    ),
    display: false
)
```

---

## 3. 菜单栏几何：必须问窗口服务器

### 3.1 陷阱：AppKit 在非主屏上测不出菜单栏

实测（MacBook 内置屏 + XV272U 外接屏）：

| 来源 | 内置屏 | 外接屏 |
| --- | --- | --- |
| `visibleFrame` 反推 | 33 | **0** |
| `safeAreaInsets.top` | 32 | **0** |
| `auxiliaryTopLeftArea` | 有（32pt） | **nil** |
| `CGWindowListCopyWindowInfo` layer 24 | **33** | **30** |

原因：菜单栏是系统级的一个面，macOS **只把它算进承载菜单栏那块屏的 `visibleFrame`**，其他屏一律返回 0。

### 3.2 正确做法

```swift
enum MenuBarWindowProbe {
    static let menuBarLevel = 24   // kCGMainMenuWindowLevel

    static func onScreenMenuBarBounds() -> [CGRect] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == menuBarLevel,
                  let dict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { return nil }
            return rect
        }
    }
}
```

**不需要任何权限**——窗口的 bounds 和 layer 是公开的，只有窗口 *标题* 才需要录屏权限。免签名的本地构建、沙盒 App 都能用。

### 3.3 坐标系转换

窗口服务器用的是**左上原点**，AppKit 是**左下原点**，且原点在 (0,0) 那块屏的左上角：

```swift
static func quartzFrame(for display: DisplaySnapshot, primaryMaxY: CGFloat) -> CGRect {
    CGRect(
        x: display.frame.minX,
        y: primaryMaxY - display.frame.maxY,   // 关键：Y 翻转
        width: display.frame.width,
        height: display.frame.height
    )
}

// primaryMaxY 取 frame.origin == .zero 那块屏的 maxY
let primaryMaxY = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY ?? 0
```

按 `x + width` 匹配到对应屏，取高度：

```swift
static func menuBarHeight(forQuartzFrame quartz: CGRect, menuBarWindowBounds: [CGRect]) -> CGFloat? {
    let matching = menuBarWindowBounds.filter {
        abs($0.minX - quartz.minX) < 1 && abs($0.width - quartz.width) < 1
    }
    guard let height = matching.map(\.height).max(), height > 0 else { return nil }
    return max(height, 24)
}
```

### 3.4 缓存

`CGWindowListCopyWindowInfo` 是一次窗口服务器往返。屏幕快照（`DisplaySnapshot`）在循环里被频繁创建，所以加 500ms 缓存：

```swift
private static let lock = NSLock()
nonisolated(unsafe) private static var cachedBounds: [CGRect] = []
nonisolated(unsafe) private static var cachedAt = Date.distantPast
```

### 3.5 刘海几何

刘海屏上 macOS 会给出刘海两侧的可用区域：

```swift
screen.auxiliaryTopLeftArea    // 刘海左侧区域
screen.auxiliaryTopRightArea   // 刘海右侧区域

var notchEdges: (left: CGFloat, right: CGFloat)? {
    guard let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea,
          r.minX > l.maxX else { return nil }   // 没刘海返回 nil
    return (l.maxX, r.minX)
}
```

实测内置屏：左侧 `(0, 1085, 771.5, 32)`，右侧 `(956.5, 1085, 771.5, 32)` → 刘海宽 185pt。

---

## 4. 精确路径：复用渲染器，不要重写

**核心原则：如果另一条路径已经能画出正确的像素，覆盖层就只负责"显示这些像素"，不要用另一套 API 复刻一遍。**

### 4.1 错误示范

用 `NSVisualEffectView` + `CALayer` 手工复刻"模糊 → 去色 → 着色 → 纹理 → 渐变遮罩 → 阴影"六层。实测偏差：

```
pt    正确值   复刻值   偏差
14.0   80.9    111.1   +30
24.0   46.3    119.9   +74     ← 该暗的地方完全没暗
30.0  102.2     68.8   -33     ← 阴影画错位置
```

原因：`NSVisualEffectView` 的模糊强度不可调（只有固定档位）、`compositingFilter` 在 behind-window 混合层上行为不可靠、几何容易错位。**复刻必错。**

### 4.2 正确做法

把渲染器的"渲染整屏图"这一步抽出来，两条路径共用：

```swift
extension WallpaperRenderer {
    /// 完整的处理后桌面图。壁纸路径和覆盖层路径都从这里开始，不可能漂移。
    func treatedImage(sourceURL: URL, display: DisplaySnapshot,
                      desktopOptions: DesktopRenderOptions,
                      settings: WallpaperEffectSettings) throws -> CGImage {
        let base = try makeScreenSizedImage(sourceURL: sourceURL, display: display,
                                           desktopOptions: desktopOptions)
        return try applyTopEffect(to: base, display: display, settings: settings)
    }

    /// 只裁条带 + 阴影区域。
    func bandImage(..., heightPoints: CGFloat) throws -> CGImage {
        let treated = try treatedImage(...)
        let scale = display.backingScaleFactor
        let cropHeight = min(treated.height, max(1, Int((heightPoints * scale).rounded())))
        return treated.cropping(to: CGRect(x: 0, y: 0,
                                           width: treated.width, height: cropHeight))!
    }
}
```

显示时 1:1 贴上去，不做任何缩放：

```swift
final class MenuBarBandImageView: NSView {
    func show(_ image: CGImage, in rect: NSRect) {
        let scale = window?.backingScaleFactor ?? 2
        imageLayer.contentsScale = scale    // 一个像素对一个物理像素
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.frame = rect
    }
}
```

实测结果：**逐行偏差 ≤ 1.1 灰阶**（仅 JPEG 编码舍入），下沿完全一致。

### 4.3 用测试锁住"像素相等"

不要只断言"看起来差不多"，直接断言字节相等：

```swift
let treated = try renderer.treatedImage(...)
let band = try renderer.bandImage(..., heightPoints: height)
let expected = treated.cropping(to: CGRect(x: 0, y: 0,
                                           width: treated.width, height: band.height))!
#expect(expected.dataProvider?.data as Data? == band.dataProvider?.data as Data?)
```

这条测试的价值：以后任何人想"顺手优化一下"覆盖层，会立刻被拦住。

---

## 5. 兜底路径：NSVisualEffectView

只在壁纸完全不可读时使用（视频/动态壁纸）。做法是**用 behind-window 混合模式模糊窗口背后的东西**：

```swift
let effect = NSVisualEffectView()
effect.material = .underWindowBackground
effect.blendingMode = .behindWindow     // 模糊的是窗口背后的内容，不是自己的内容
effect.state = .active
effect.maskImage = fadeMask             // 渐隐用 maskImage 做
```

### 5.1 两个坑

1. **不要把 mask 加在含 `NSVisualEffectView` 的父层上**。给视觉效果的父 view 设 `layer.mask` 会让窗口服务器不再合成背景模糊，直接变透明。正确做法：blur 单独一个容器用 `maskImage`，其余图层放另一个容器上用 `layer.mask`。

2. **不要重复赋同一张 mask 图片**。每个刷新周期重新赋值会触发 AppKit 的 layout 递归，日志里刷：

```
It's not legal to call -layoutSubtreeIfNeeded on a view which is already being laid out.
```

按 key 缓存，只在实际变化时重建：

```swift
let maskKey = "\(bandHeight)x\(fadeHeight)"
if maskKey != appliedMaskKey {
    let mask = Self.fadeMask(bandHeight: bandHeight, fadeHeight: fadeHeight)
    blurViews.forEach { $0.maskImage = mask }
    appliedMaskKey = maskKey
}
```

### 5.2 模糊强度只有档位

`NSVisualEffectView` 每种 material 的模糊强度是固定的。想模拟"半径可调"只能叠层：

```swift
static func blurPassCount(blurRadiusPoints: Double) -> Int {
    switch blurRadiusPoints {
    case ..<1: return 0     // 不模糊
    case ..<11: return 1
    case ..<21: return 2
    default: return 3
    }
}
```

这是近似，不是等价。能用精确路径就别走这条。

---

## 6. 进度条 / 额度条的绘制

**用 CALayer，不要用 Core Image，也不要用 SwiftUI。** 理由：改一个百分比应该是一帧内重画几层，而不是重跑整条渲染管线。

### 6.1 几何模型：trackRect 与 rect 分离

这是踩过坑之后的关键抽象：

```swift
struct GaugeSegment {
    var rect: CGRect        // 填充允许覆盖的范围（刘海模式下止步于刘海边缘）
    var trackRect: CGRect   // 底槽范围（永远是整条菜单栏）
    var usedFraction: Double
    var color: TintColor
    var fillsFromLeft: Bool
    var isFullBleed: Bool
}
```

**为什么底槽必须整条铺满：刘海是带圆角的物理开孔。** 如果底槽也裁到刘海边缘，那两个圆角处就会露出壁纸，视觉上就是"底色不对"。

所以刘海模式下的正确结构是：

```
[========== 深色底槽，横贯全屏 ==========]
[== 左填充 ==]  (刘海)  [== 右填充 ==]
```

### 6.2 两种版式

```swift
enum QuotaGaugeStyle { case fullBar, notchSplit }
```

- `fullBar`：一段，从左边生长，`trackRect == rect`，直角（全宽铺满时圆角会露出壁纸）
- `notchSplit`：两段，各自贴自己的屏幕边缘，**填充方向从外缘向刘海**，`trackRect` 共享同一个全宽矩形

刘海间隙取 **0**：刘海本身是不透明黑块，往里退让只会在无刘海屏上凭空多出一条缝。

无刘海屏上 `notchEdges == nil`，退化成以中线分左右，两半严丝合缝。

### 6.3 绘制

```swift
let track = CALayer()
track.frame = segment.trackRect
track.cornerRadius = segment.isFullBleed ? 0 : trackRect.height / 2
track.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.38)  // 深色底，保证亮壁纸上可读
track.borderWidth = segment.isFullBleed ? 0 : 1

let fill = CALayer()
fill.frame = QuotaGaugeGeometry.fillRect(for: segment)   // 从外缘生长
fill.cornerRadius = ...
fill.backgroundColor = brandColor.cgColor(alpha: 0.95)
fill.shadowColor = brandColor.cgColor(alpha: 1)          // 同色辉光，读起来像"发光"而不是"涂色块"
fill.shadowOpacity = 0.7
fill.shadowRadius = 7
```

**深色底槽是必须的**：只靠品牌色低透明度做 track，在亮壁纸上完全看不见（实测第一版就是这样被否掉的）。

### 6.4 全宽铺满的尺寸

```swift
static func barHeight(menuBarHeight: CGFloat) -> CGFloat {
    min(max(menuBarHeight * 1.0, 12), 40)   // 高度 = 菜单栏本身
}
static let horizontalInset: CGFloat = 0      // 边到边
```

"菜单栏就是进度条"的观感要求：**高度占满、左右无边距、直角收边**。

---

## 7. 健壮性

### 7.1 看门狗：`NSWindow.isVisible` 会骗你

换壁纸、切 Space、插拔显示器时，系统可能**静默丢掉**桌面层级的窗口，而 `window.isVisible` 仍然返回 `true`。App 自己完全不知道，效果就"用着用着消失了"。

解法：**问窗口服务器实际有几条带子在屏幕上**。

```swift
nonisolated static func onScreenBandCount() -> Int {
    let bandLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    let pid = ProcessInfo.processInfo.processIdentifier
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return windows.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid
            && ($0[kCGWindowLayer as String] as? Int) == bandLevel
    }.count
}

// 5 秒一次
func reassert() {
    let managed = windows.values.filter(\.isVisible)
    guard !managed.isEmpty else { return }
    guard MenuBarBandWatchdog.needsReassert(
        managedBands: managed.count,
        onScreenBands: onScreenBandCount()
    ) else { return }              // 数量对得上就什么都不做，不会闪
    managed.forEach { $0.orderFrontRegardless() }
}
```

判定逻辑抽成纯函数便于测试：

```swift
static func needsReassert(managedBands: Int, onScreenBands: Int) -> Bool {
    managedBands > 0 && onScreenBands < managedBands
}
```

### 7.2 生命周期

| 事件 | 处理 |
| --- | --- |
| 屏幕参数变化 | `NSApplication.didChangeScreenParametersNotification` → 重建窗口 |
| Space 切换 | `NSWorkspace.activeSpaceDidChangeNotification` → 重算（全屏 Space 要隐藏） |
| 会话锁定/解锁 | `NSWorkspace.sessionDidResignActive/BecomeActive` |
| 全屏 Space | `.canJoinAllSpaces` 会跟过去，**必须手动隐藏**（全屏时没有菜单栏） |

全屏判定：

```swift
let isFullscreen = sourceResolver.activeSpaceContext(for: display)?.isFullscreen == true
let settings = isFullscreen ? nil : normalSettings   // nil → 该屏不画
```

### 7.3 渲染必须在后台

渲染整屏图是重活，必须离开主线程：

```swift
Task { [weak self] in
    let rendered = await Task.detached(priority: .userInitiated) {
        Self.renderBands(inputs: renderInputs, ...)   // 捕获不可变值，避免数据竞争
    }.value
    guard let self, self.generationRevision == revision else { return }  // 丢弃过期结果
    self.overlayController.update(rendered)
}
```

用 `generationRevision` 计数器丢弃过期渲染结果，避免"快速拖滑块时旧结果覆盖新结果"。

---

## 8. 踩坑清单（逐条）

| # | 坑 | 现象 | 解法 |
| --- | --- | --- | --- |
| 1 | 外接屏 `visibleFrame` 不含菜单栏 | 条带比菜单栏矮 3pt，露一条边 | 用窗口服务器 layer 24 的窗口矩形 |
| 2 | 用 CALayer 复刻 Core Image 合成 | 亮度差 30~75 灰阶 | 复用渲染器输出，只做裁剪与显示 |
| 3 | 空字符串 Space UUID | 所有报空 UUID 的屏共用一个设置桶，"This Space" 失效 | 空键视为"无 Space"，读写时规范化 |
| 4 | 重复赋同一张 `maskImage` | AppKit layout 递归警告刷屏 | 按 key 缓存，变化才重建 |
| 5 | 给视觉效果父层设 `layer.mask` | 背景模糊整个失效 | blur 用 `maskImage`，其他图层用 `layer.mask` |
| 6 | 底槽裁到刘海边缘 | 刘海圆角处露出壁纸，"底色不对" | 底槽整条铺满，只裁填充 |
| 7 | 刘海留间隙 | 无刘海屏上中间一条缝 | gap = 0 |
| 8 | 圆角收边 | 全宽条看起来像悬浮胶囊 | 全宽时直角 |
| 9 | 只靠品牌色低透明度做底槽 | 亮壁纸上完全看不见 | 加黑色 35~40% 深色底 |
| 10 | 信任 `window.isVisible` | 效果"用着用着没了" | 问窗口服务器计数，看门狗补位 |
| 11 | 窗口层级高于菜单栏 | 挡住菜单栏图标 | 放 `desktopIconWindow + 1` |
| 12 | 权限顾虑 | 以为要录屏权限 | bounds/layer 免权限，只有窗口标题要 |

---

## 9. 新项目落地清单

### 9.1 最小可用骨架

```
MenuBarOverlayController      // 每屏一个窗口，生命周期 + 看门狗
├─ MenuBarGeometry            // 菜单栏高度、刘海、坐标系转换
├─ BandWindow                 // NSWindow 子类，窗口配置
│   ├─ ContentView            // 承载下面三个
│   │   ├─ BandView           // 兜底：背景模糊
│   │   ├─ BandImageView      // 精确：渲染器输出的条带
│   │   └─ GaugeView          // 叠加：进度条 / 额度条 / 指示器
└─ Renderer                   // 离屏渲染（若需要）
```

### 9.2 依赖的系统 API

| API | 用途 | 权限 |
| --- | --- | --- |
| `CGWindowListCopyWindowInfo` | 菜单栏高度、窗口存在性检测 | 无 |
| `CGWindowLevelForKey` | 窗口层级 | 无 |
| `NSScreen.auxiliaryTop{Left,Right}Area` | 刘海几何 | 无 |
| `NSVisualEffectView` (.behindWindow) | 背景模糊 | 无 |
| `NSScreen.visibleFrame` | 参考，**不要**用来测非主屏菜单栏 | 无 |

**整个方案不需要任何权限申请**，这对免签名本地构建和沙盒分发都很友好。

### 9.3 测试策略

三条不可省略的测试：

1. **几何纯函数**：菜单栏高度匹配、坐标系翻转、刘海避让、无刘海退化
2. **像素相等**：复用渲染器时断言字节相等（防止未来"顺手优化"）
3. **看门狗判定**：注入 `onScreenBandCounter` 模拟窗口服务器丢窗口

### 9.4 建议的实现顺序

1. 无边框穿透窗口，画一个纯色矩形，确认层级正确、不挡菜单栏图标
2. 接入菜单栏高度测量，多屏验证
3. 加看门狗，观察日志确认补位逻辑
4. 上真正的绘制内容（进度条优先，用 CALayer）
5. 需要像素级背景时，才接入渲染器复用

第 1、2 步就能暴露 80% 的问题，不要跳过。

---

## 10. 一句话总结

> 用低于菜单栏、高于桌面图标的穿透窗口自己画；菜单栏高度问窗口服务器；能复用渲染器就绝不复刻；进度条用 CALayer；底槽铺满、只裁填充；用一个 5 秒看门狗对抗会静默丢窗口的系统。

---

## 11. 兼容性分析

### 11.1 已验证环境

| 项目 | 值 |
| --- | --- |
| macOS | 27.0.1（build 26A434） |
| 开发工具 | Xcode 27 / Swift 6.4 |
| 架构 | Apple Silicon (arm64) |
| 显示器 | 内置刘海屏（1728pt @2x）+ 外接无刘海屏（2048pt @2x） |
| 本仓库部署目标 | macOS 14.0 |

**只在这一个 macOS 大版本上验证过。** 下面区分"结构上安全"和"未验证"。

### 11.2 公开 API 的最低系统版本

覆盖层方案用到的**全部是公开 API**，最低要求 macOS 12：

| API | 最低版本 | 用途 |
| --- | --- | --- |
| `CGWindowLevelForKey` / `kCGMainMenuWindowLevel` | 10.0 | 窗口层级、菜单栏层级 |
| `CGWindowListCopyWindowInfo` | 10.5 | 菜单栏高度、窗口存在性 |
| `NSWindow.collectionBehavior` | 10.6 | 跟随所有 Space |
| `NSVisualEffectView` + `.behindWindow` | 10.10 | 兜底背景模糊 |
| `.underWindowBackground` material | 10.14 | 模糊材质 |
| `NSScreen.auxiliaryTopLeftArea / auxiliaryTopRightArea` | **12.0** | 刘海几何 |
| `String(localized:)` | **12.0** | 本地化 |

👉 **部署目标定 macOS 12 就够**，不需要跟系统的"最新版本"。这比大多数人的预期要宽松。

### 11.3 私有 API：覆盖层本身零依赖

这点很重要：

| 功能 | 是否用私有 API |
| --- | --- |
| 覆盖窗口、层级、多屏 | ❌ 纯公开 API |
| 菜单栏高度测量 | ❌ 纯公开 API |
| 刘海几何 | ❌ 纯公开 API |
| 背景模糊 | ❌ 纯公开 API |
| 进度条 / 额度条绘制 | ❌ 纯公开 API |
| **按 Space 存独立设置** | ✅ 需要 SkyLight（`dlopen` + `CGSCopyManagedDisplaySpaces`） |
| **识别全屏 Space** | ✅ 同上 |

也就是说：**如果新项目只做"菜单栏上画东西"，可以完全不碰私有 API**，从而具备上架 App Store 的可能。只有需要"按 Space 区分""识别全屏"时才引入 SkyLight。

### 11.4 私有 API 消失时会怎样

好消息：**是优雅降级，不是崩溃**。

```swift
static let symbols: Symbols? = {
    guard let handle = dlopen(".../SkyLight.framework/SkyLight", RTLD_LAZY),
          let main = dlsym(handle, "CGSMainConnectionID"),
          let copy = dlsym(handle, "CGSCopyManagedDisplaySpaces") else {
        return nil          // 符号没了就是 nil，不 crash
    }
    ...
}()

func spaceContext(forDisplayUUID uuid: String?) -> ActiveSpaceContext? {
    guard let uuid, let symbols = Self.symbols else { return nil }   // 全部降级
    ...
}
```

降级后的行为：

- `isFullscreen` 判定为 `false` → 全屏 Space 里条带**不会**自动隐藏（外观瑕疵，不影响功能）
- `spaceUUID` 为 `nil` → 回退到全局设置，按 Space 的独立设置失效（功能降级，不影响绘制）

**新项目如果不需要这两个能力，直接不要引入 SkyLight**，就没有这个风险。

### 11.5 硬编码值的处理

| 值 | 处理 | 风险 |
| --- | --- | --- |
| 菜单栏窗口层级 | ✅ 用 `CGWindowLevelForKey(.mainMenuWindow)`，不写 24 | 无（跟随系统常量） |
| 条带窗口层级 | ✅ `desktopIconWindow + 1`，相对值 | 低 |
| 菜单栏高度下限 24pt | ⚠️ 仍是硬编码兜底 | 低（只在测不到时生效） |

**教训：任何"系统常量"都优先用 API 取，不要抄数值。** 我第一版把 24 写死了，虽然实测就是 24，但一旦 Apple 改了这个常量，写死的版本会静默失效（找不到菜单栏窗口 → 一直走兜底路径 → 高度算错，且没有任何报错）。

### 11.6 未验证的场景（新项目要重点测）

| 场景 | 风险 | 预期行为 / 应对 |
| --- | --- | --- |
| **macOS 14 / 15** | 中 | layer-24 菜单栏窗口的假设未在旧系统验证。测不到会走兜底高度，不崩 |
| **菜单栏自动隐藏**（系统设置里开启） | 中 | 菜单栏滑走后条带**会留在原地**，视觉上悬空。需要监听并跟随隐藏 |
| **Stage Manager** | 中 | 桌面层窗口在 Stage Manager 下的行为未测，可能被裁剪或跟随异常 |
| **Mission Control / 切桌面动画** | 低 | `.stationary` 让它不参与动画，但实际观感未验证 |
| **混合缩放**（1x + 2x 显示器） | 低 | 按屏取 `backingScaleFactor`，理论上正确，未实测 1x 屏 |
| **显示器旋转** | 低 | 用 `frame.width/height`，理论上跟随，未测 |
| **macOS 大版本升级** | 中 | 菜单栏层级、刘海 API 语义、窗口丢弃行为都可能变 |
| **App Store 审核** | — | 只做覆盖层则可上架；引入 SkyLight 后被拒概率高 |
| **高效能/低电量模式** | 低 | 看门狗 5 秒一次的窗口查询开销可忽略 |
| **外接屏热插拔** | 低 | 有 `didChangeScreenParameters` 重建 + 残留窗口清理 |

### 11.7 已经内建的容错

不管上面哪一条出问题，这些机制保证**不会崩、最多是外观不对**：

```
测不到菜单栏高度     → 回退到所有屏里最大的 visibleFrame 测量值
读不到 SkyLight     → 回退到全局设置，不识别全屏
菜单栏窗口找不到     → menuBarHeight 返回 nil → 走上面的兜底
窗口被系统丢掉       → 5 秒看门狗问窗口服务器，数量不足就补位
渲染结果过期         → generationRevision 计数丢弃
显示器被拔掉         → 残留窗口清理
没有刘海             → notchEdges == nil → 退化成中线分左右
临时壁纸读不到       → 走 NSVisualEffectView 兜底路径
```

### 11.8 给新项目的兼容性建议

1. **部署目标定 macOS 12**（刘海 API 的下限），不需要更高
2. **先做纯覆盖层，不加 Space 逻辑** —— 零私有 API、零权限、可上架
3. **优先用 API 取系统常量**，不要抄数值（`.mainMenuWindow` 而不是 `24`）
4. **每个"测不到"的分支都要有兜底**，并且兜底要比正常路径保守（宁可高度多一点，不要露白）
5. **上架前把 SkyLight 相关代码彻底删掉**，而不是用条件编译绕过——审核会看符号表
6. 在旧系统上跑一遍第 9.4 节的第 1、2 步，确认层级和高度两项基础能力
