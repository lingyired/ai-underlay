import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 主题设置。主题**只描述外观**：颜色、材质、状态灯。它不能改变
/// `Error > Waiting > Unread` 的优先级，也不能影响任何监控数据。
///
/// 主题以 JSON 存在 Application Support 里，App 更新不会覆盖；文件改动会热重载。
/// 这里的手动取色不会改写内置主题或你的主题文件，而是保存在设置里，
/// 永远优先于主题文件 —— 改一个颜色不需要重新编译，也不会与热重载打架。
public struct ThemeTab: View {
    /// Copy pinned by `ThemeTabTests`: the slider must describe the rendered
    /// material softening, never claim a system backdrop-blur radius.
    public static let softnessLabel = "材质柔化"
    public static let softnessNote =
        "原生绘制材质的柔化（0 清晰 / 17 默认 / 32 最软）；不采样桌面背景，泛光与颗粒为 0 时同样生效。"

    @ObservedObject var settings: SettingsStore
    @ObservedObject var themes: ThemeStore
    @State private var status = ""
    @State private var materialExpanded = false

    public init(settings: SettingsStore, themes: ThemeStore) {
        self.settings = settings
        self.themes = themes
    }

    public var body: some View {
        Form {
            themeSection
            agentGlassSection
            quotaSection
            signalSection
            materialSection
            fileSection

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

    // MARK: - Sections

    private var themeSection: some View {
        Section("主题") {
            Picker("当前主题", selection: themeSelection) {
                Text("Selected Glass V5（内置默认）").tag(String?.none)
                ForEach(themes.themes, id: \.id) { theme in
                    Text(theme.name).tag(String?.some(theme.id))
                }
            }
            Text("只写你要覆盖的字段；没写的沿用内置 Selected Glass V5。额度长度、告警优先级与数据都不受主题影响。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var agentGlassSection: some View {
        Section("Agent 玻璃主题色") {
            providerColorRow("Codex", providerId: "codex",
                             dictionary: \.agentThemeColors,
                             fallback: { GlassDefaults.codexAgentTheme })
            providerColorRow("Claude", providerId: "claude",
                             dictionary: \.agentThemeColors,
                             fallback: { GlassDefaults.claudeAgentTheme })
            Button("恢复默认玻璃色") {
                settings.update { $0.appearance.agentThemeColors = [:] }
                status = "已恢复默认玻璃主题色"
            }
            Text("只给该 Provider 的玻璃表面染色；不影响额度颜色、状态灯色，也不影响另一侧。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var quotaSection: some View {
        Section("额度颜色") {
            providerColorRow("Codex", providerId: "codex",
                             dictionary: \.quotaBaseColors,
                             fallback: { ProviderPalette.codex.inner })
            providerColorRow("Claude", providerId: "claude",
                             dictionary: \.quotaBaseColors,
                             fallback: { ProviderPalette.claude.inner })
            Button("恢复默认额度色") {
                settings.update { $0.appearance.quotaBaseColors = [:] }
                status = "已恢复默认额度颜色"
            }
            Text("两层额度由统一亮度梯度生成：外层更暗、内层更亮、端点高光；用完的部分保持黑色。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var signalSection: some View {
        Section("信号光源（全部 Provider 共用）") {
            signalColorRow("Running（运行中）", key: .running, fallback: GlassDefaults.signalLights.running)
            signalColorRow("Error（故障）", key: .error, fallback: GlassDefaults.signalLights.error)
            signalColorRow("Waiting（等待你）", key: .waiting, fallback: GlassDefaults.signalLights.waiting)
            signalColorRow("Unread（未读完成）", key: .unread, fallback: GlassDefaults.signalLights.unread)
            Button("恢复默认信号色") {
                settings.update { $0.appearance.signalColors = [:] }
                status = "已恢复默认信号光源色"
            }
            Text("优先级固定：Error > Waiting > Unread > 无。Running 是独立维度：有任务就运动，颜色取最高优先级信号色。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var materialSection: some View {
        Section {
            DisclosureGroup("玻璃材质参数", isExpanded: $materialExpanded) {
                materialSlider(Self.softnessLabel, keyPath: \.blurRadiusTarget,
                               range: 0...32, `default`: GlassDefaults.material.blurRadiusTarget)
                Text(Self.softnessNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                materialSlider("环境泛光", keyPath: \.ambientGlow,
                               range: 0...1, `default`: GlassDefaults.material.ambientGlow)
                materialSlider("颗粒质感", keyPath: \.grain,
                               range: 0...1, `default`: GlassDefaults.material.grain)
                materialSlider("光线密度", keyPath: \.rayDensity,
                               range: 0...1, `default`: GlassDefaults.material.rayDensity)
                materialSlider("额度层不透明度", keyPath: \.quotaOpacity,
                               range: 0...1, `default`: GlassDefaults.material.quotaOpacity)
                materialSlider("主题色强度", keyPath: \.agentThemeStrength,
                               range: 0...1, `default`: GlassDefaults.material.agentThemeStrength)
                Button("恢复默认材质") {
                    settings.update { $0.appearance.material = nil }
                    status = "已恢复默认玻璃材质"
                }
            }
        } footer: {
            Text("材质参数保存在设置里并即时生效；泛光为 0 时主题色仍然可见（由玻璃染色层承载）。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fileSection: some View {
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
                Button("导出示例主题（V5）…") { exportExample() }
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
    }

    // MARK: - Rows

    private func providerColorRow(
        _ label: String,
        providerId: String,
        dictionary: WritableKeyPath<GlassAppearance, [String: String]>,
        fallback: @escaping () -> RGBAColor
    ) -> some View {
        ColorPicker(label, selection: colorBinding(dictionary: dictionary, key: providerId, fallback: fallback))
    }

    private func signalColorRow(_ label: String, key: SignalColorKey, fallback: RGBAColor) -> some View {
        ColorPicker(label, selection: colorBinding(dictionary: \.signalColors, key: key.rawValue, fallback: { fallback }))
    }

    private func materialSlider(
        _ label: String,
        keyPath: WritableKeyPath<GlassMaterialOverrides, Double?>,
        range: ClosedRange<Double>,
        `default`: Double
    ) -> some View {
        let binding = Binding<Double>(
            get: { settings.settings.appearance.material?[keyPath: keyPath] ?? `default` },
            set: { newValue in
                settings.update { s in
                    var material = s.appearance.material ?? GlassMaterialOverrides()
                    material[keyPath: keyPath] = min(max(newValue, range.lowerBound), range.upperBound)
                    s.appearance.material = material
                }
            }
        )
        return LabeledContent(label) {
            HStack(spacing: 8) {
                Slider(value: binding, in: range)
                Text(String(format: range.upperBound > 2 ? "%.0f" : "%.2f", binding.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Bindings

    private func colorBinding(
        dictionary: WritableKeyPath<GlassAppearance, [String: String]>,
        key: String,
        fallback: @escaping () -> RGBAColor
    ) -> Binding<Color> {
        Binding(
            get: {
                let stored = settings.settings.appearance[keyPath: dictionary][key]
                let resolved = stored.flatMap { RGBAColor(hex: $0) } ?? fallback()
                return Color(resolved)
            },
            set: { newColor in
                let resolved = RGBAColor(newColor, fallback: fallback())
                settings.update { $0.appearance[keyPath: dictionary][key] = resolved.hexString }
            }
        )
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
        panel.nameFieldStringValue = "\(ThemePresets.selectedGlassV5.id).json"
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
