import Foundation

/// Themes that ship inside the app. They are never written to disk, so an app
/// update can add or change them without touching anything the user saved.
public enum ThemePresets {
    /// A brighter, more saturated reference theme. The colors come from the
    /// product consensus (§7.3) as a starting point, not as a brand lock-in —
    /// copy this file's shape to make your own.
    public static let vivid = ThemeDocument(
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

    public static let all: [ThemeDocument] = [vivid]

    /// Instructions an agent (or a person) can follow to author a theme without
    /// reading any Swift. Copied to the clipboard from the Theme tab.
    public static let authoringGuide = """
    你正在为 AIUnderlay 编写主题（只改外观，不改任何监控数据）。
    1. 主题是一个 JSON 文件，放在 ~/Library/Application Support/\(AIUnderlayKit.bundleIdentifier)/Themes/ 下，一个文件一个主题。
    2. 必须包含 schemaVersion（当前为 1）、id、name。id 只能用小写字母、数字、点、下划线或短横线。
    3. 颜色用 "#RRGGBB" 或 "#RRGGBBAA"。可选字段：global（trackColor/trackOpacity/baselineColor/baselineOpacity/baselineEnabled）、
       providers（codex / claude：quotaLayers 外层→内层、spectrumColor、spectrumOpacity）、
       states（waiting / error：overlayColor、overlayOpacity、spectrumColor、borderColor、borderWidth）。
    4. 只需要写你要覆盖的字段；没写的沿用内置默认色。
    5. 不允许改变 Error > Waiting > Normal 的优先级，不允许编造额度窗口，不允许改变任何数据。
    6. 保存后 App 会自动热重载；如果 JSON 有错，会保留上一个正常主题并在设置里显示原因。
    """

    /// The JSON an agent or user can start from when writing a new theme.
    public static var exampleJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(vivid), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
