import Foundation

/// Themes that ship inside the app. They are never written to disk, so an app
/// update can add or change them without touching anything the user saved.
public enum ThemePresets {
    /// The user's selected look, materialised as a v2 theme document so it can
    /// be exported, copied, or handed to an AI agent as a starting point.
    /// These are exactly the V5 values the user exported — this preset IS the
    /// built-in default, so selecting it changes nothing.
    public static let selectedGlassV5 = ThemeDocument(
        schemaVersion: 2,
        id: "selected-glass-v5",
        name: "Selected Glass V5（用户选定）",
        global: ThemeDocument.Global(
            baselineColor: "#FFFFFF",
            baselineOpacity: 0.9,
            baselineEnabled: true,
            exhaustedTrackColor: "#000000",
            exhaustedTrackOpacity: 1.0
        ),
        providers: [
            "codex": ThemeDocument.Provider(quotaBaseColor: "#69BFFF", agentThemeColor: "#62AC96"),
            "claude": ThemeDocument.Provider(quotaBaseColor: "#FFB08A", agentThemeColor: "#FFFFFF"),
        ],
        signals: ThemeDocument.Signals(
            running: .init(lightColor: "#D9EEFF"),
            error: .init(lightColor: "#FF7596"),
            waiting: .init(lightColor: "#FFE1A0"),
            unread: .init(lightColor: "#64F1BD")
        ),
        material: ThemeDocument.Material(
            blurRadiusTarget: 17,
            ambientGlow: 0,
            grain: 0,
            rayDensity: 1.0,
            quotaOpacity: 1.0,
            agentThemeStrength: 1.0
        ),
        attention: ThemeDocument.Attention(
            topLineHeight: 2,
            bottomRibbonHeight: 5,
            sweepSecondsError: 4,
            sweepSecondsWaiting: 5,
            sweepSecondsUnread: 7
        )
    )

    /// A brighter, more saturated reference theme. The colors come from the
    /// product consensus (§7.3) as a starting point, not as a brand lock-in —
    /// copy this file's shape to make your own.
    public static let vivid = ThemeDocument(
        schemaVersion: 1,
        id: "builtin-vivid",
        name: "明亮示例",
        global: ThemeDocument.Global(
            trackColor: "#253043",
            trackOpacity: 0.40,
            baselineColor: "#FFFFFF"
        ),
        providers: [
            "codex": ThemeDocument.Provider(quotaLayers: ["#4361EE", "#48C7FF"], spectrumColor: "#D5F6FF"),
            "claude": ThemeDocument.Provider(quotaLayers: ["#F66A42", "#FFB071"], spectrumColor: "#FFF0C2"),
        ],
        states: [
            "waiting": ThemeDocument.StateStyle(
                overlayColor: "#FFAA22", overlayOpacity: 0.20,
                spectrumColor: "#FFC247", borderColor: "#FFE15C", borderWidth: 2
            ),
            "error": ThemeDocument.StateStyle(
                overlayColor: "#FF355E", overlayOpacity: 0.22,
                spectrumColor: "#FF5578", borderColor: "#FF526A", borderWidth: 2
            ),
        ]
    )

    public static let all: [ThemeDocument] = [selectedGlassV5, vivid]

    /// Instructions an agent (or a person) can follow to author a theme without
    /// reading any Swift. Copied to the clipboard from the Theme tab.
    public static let authoringGuide = """
    你正在为 AIUnderlay 编写主题（只改外观，不改任何监控数据）。
    1. 主题是一个 JSON 文件，放在 ~/Library/Application Support/\(AIUnderlayKit.bundleIdentifier)/Themes/ 下，一个文件一个主题。
    2. 必须包含 schemaVersion（当前为 2；旧版 1 仍可读取）、id、name。id 不能包含路径分隔符。
    3. 三类颜色互不混用，请分开写：
       · providers.<id>.quotaBaseColor —— 额度颜色（codex 默认 #69BFFF，claude 默认 #FFB08A）；
         也可以给 providers.<id>.quotaLayers（外层→内层，最多 3 层）直接指定每一层的颜色。
       · providers.<id>.agentThemeColor —— 该 Provider 玻璃表面的染色（只影响材质，不影响额度与状态光）。
       · signals.running/error/waiting/unread.lightColor —— 状态光源色（全局语义）。
    4. global 可写：exhaustedTrackColor/exhaustedTrackOpacity（用完的额度底色，默认纯黑）、
       trackColor/trackOpacity（无数据时的中性槽）、baselineColor/baselineOpacity/baselineEnabled。
    5. material 可写：blurRadiusTarget(0-32)、ambientGlow、grain、rayDensity、quotaOpacity、agentThemeStrength（后五项 0-1）。
    6. attention 可写：topLineHeight(0-6)、bottomRibbonHeight(0-10)、sweepSecondsError/Waiting/Unread(1-60)。
    7. 只需要写你要覆盖的字段；没写的沿用内置默认（即 Selected Glass V5）。
    8. 不允许改变 Error > Waiting > Unread 的优先级，不允许编造额度窗口，不允许改变任何数据。
    9. 保存后 App 会自动热重载；如果 JSON 有错，会保留上一个正常主题并在设置里显示原因。
    """

    /// The JSON an agent or user can start from when writing a new theme.
    public static var exampleJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(selectedGlassV5), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
