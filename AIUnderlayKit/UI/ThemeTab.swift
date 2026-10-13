import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 主题设置。主题**只描述外观**：颜色、边框、频谱色。它不能改变
/// `Error > Waiting > Normal` 的优先级，也不能影响任何监控数据。
///
/// 主题以 JSON 存在 Application Support 里，App 更新不会覆盖；文件改动会热重载。
public struct ThemeTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var themes: ThemeStore
    @State private var status = ""

    public init(settings: SettingsStore, themes: ThemeStore) {
        self.settings = settings
        self.themes = themes
    }

    public var body: some View {
        Form {
            Section("主题") {
                Picker("当前主题", selection: themeSelection) {
                    Text("内置默认（不覆盖任何颜色）").tag(String?.none)
                    ForEach(themes.themes, id: \.id) { theme in
                        Text(theme.name).tag(String?.some(theme.id))
                    }
                }
                Text("只写你要覆盖的字段；没写的沿用内置默认色。额度长度、告警优先级与数据都不受主题影响。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("文件") {
                Text(themes.directoryURL.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("打开主题文件夹") {
                        NSWorkspace.shared.open(themes.directoryURL)
                    }
                    Button("重新载入") {
                        themes.reload()
                        status = "已重新载入 \(themes.themes.count) 个主题"
                    }
                    Button("导出示例主题…") { exportExample() }
                    Button("复制给 AI 的指令") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(ThemePresets.authoringGuide, forType: .string)
                        status = "指令已复制，可直接粘给 AI Agent"
                    }
                }
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            if let error = themes.lastError {
                Section("有问题") {
                    Text(error)
                        .font(.caption.monospaced())
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                    Text("有错的主题不会被使用；如果它正是当前主题，会继续用上一次正常的版本。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Selecting a theme writes to settings; the coordinator then repaints.
    private var themeSelection: Binding<String?> {
        Binding(
            get: { settings.settings.activeThemeId },
            set: { id in settings.update { $0.activeThemeId = id } }
        )
    }

    private func exportExample() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(ThemePresets.vivid.id).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(ThemePresets.exampleJSON.utf8).write(to: url, options: .atomic)
            status = "已导出到 \(url.lastPathComponent)"
        } catch {
            status = "导出失败：\(error.localizedDescription)"
        }
    }
}
