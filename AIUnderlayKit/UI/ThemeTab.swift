import SwiftUI

/// Appearance-only theme settings. Personal values intentionally outrank the
/// selected theme, which outranks the built-in V5 look.
public struct ThemeTab: View {
    /// Pinned by `ThemeTabTests`: this describes rendered glass softening, never
    /// a system backdrop-blur radius.
    public static let softnessLabel = "材质柔化"
    public static let softnessNote =
        "原生绘制材质的柔化（0 清晰 / 17 默认 / 32 最软）；不采样桌面背景，泛光与颗粒为 0 时同样生效。"

    @ObservedObject var settings: SettingsStore
    @ObservedObject var themes: ThemeStore
    @State private var status: ThemeTabStatusMessage?
    @State private var confirmingResetAll = false

    public init(settings: SettingsStore, themes: ThemeStore) {
        self.settings = settings
        self.themes = themes
    }

    public var body: some View {
        Form {
            themeSection
            if let error = themes.lastError {
                themeErrorSection(error)
            }
            ThemeTabColorsView(
                settings: settings,
                themes: themes,
                reportStatus: reportStatus
            )
            ThemeTabMaterialView(
                settings: settings,
                themes: themes,
                reportStatus: reportStatus
            )
            ThemeTabFileToolsView(
                themes: themes,
                reportStatus: reportStatus
            )
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let status {
                ThemeTabStatusView(
                    status: status,
                    persistenceError: settings.persistenceError,
                    retrySave: retrySave,
                    dismiss: { self.status = nil }
                )
            }
        }
        .confirmationDialog(
            "恢复全部外观为当前主题？",
            isPresented: $confirmingResetAll,
            titleVisibility: .visible
        ) {
            Button("恢复全部外观", role: .destructive) {
                restoreAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清除所有个人颜色和材质，但会保留当前主题、服务商开关与真实额度数据。")
        }
    }

    private var themeSection: some View {
        Section {
            Picker("主题", selection: themeSelection) {
                Text("Selected Glass V5（内置默认）")
                    .tag(String?.none)
                ForEach(pickerThemes, id: \.id) { theme in
                    Text(theme.name)
                        .tag(String?.some(theme.id))
                }
                if let unavailableID {
                    Text("所选主题（暂时不可用）")
                        .tag(String?.some(unavailableID))
                }
            }

            LabeledContent("当前显示") {
                Text(activeThemeDisplayName)
                    .multilineTextAlignment(.trailing)
            }

            Label(personalLabel, systemImage: personalOverrideCount == 0
                  ? "checkmark.circle"
                  : "paintpalette.fill")
                .foregroundStyle(.secondary)

            Text("切换主题会保留你的个人设置。有效的个人颜色与材质会继续覆盖新主题；需要查看主题原貌时，可在各分组中恢复。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if selectedThemeUnavailable {
                Label("所选主题暂时无法载入，当前使用内置外观。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if personalOverrideCount > 0 {
                Button("恢复全部外观…") {
                    confirmingResetAll = true
                }
            }
        } header: {
            Text("主题与个人外观")
        }
    }

    private func themeErrorSection(_ error: String) -> some View {
        Section {
            Label("部分主题没有载入", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("有问题的主题不会参与显示；如果它正在使用，会保留上一次正常版本。你的个人外观不会因此被修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pickerThemes: [ThemeDocument] {
        themes.themes.filter { theme in
            theme != ThemePresets.selectedGlassV5
                || settings.settings.activeThemeId == ThemePresets.selectedGlassV5.id
        }
    }

    private var unavailableID: String? {
        guard let id = settings.settings.activeThemeId,
              !themes.themes.contains(where: { $0.id == id })
        else {
            return nil
        }
        return id
    }

    private var selectedThemeUnavailable: Bool {
        settings.settings.activeThemeId != nil && themes.activeTheme == nil
    }

    private var activeThemeDisplayName: String {
        themes.activeTheme?.name ?? (
            settings.settings.activeThemeId == nil
                ? "Selected Glass V5（内置默认）"
                : "所选主题（暂时不可用）"
        )
    }

    private var personalOverrideCount: Int {
        ThemeTabPreviewState.overrideCount(in: settings.settings.appearance)
    }

    private var personalLabel: String {
        personalOverrideCount == 0
            ? "当前外观与主题一致"
            : "\(personalOverrideCount) 项个人自定义优先于主题"
    }

    private var themeSelection: Binding<String?> {
        Binding(
            get: { settings.settings.activeThemeId },
            set: { id in
                let preserved = personalOverrideCount
                settings.update { $0.activeThemeId = id }
                updateStatus(
                    ThemeTabPreviewState.statusAfterMutation(
                        success: preserved == 0
                            ? "已切换主题，外观已立即更新。"
                            : "已切换主题；\(preserved) 项个人自定义仍保留，并会继续优先于主题。",
                        persistenceError: settings.persistenceError
                    )
                )
            }
        )
    }

    private func restoreAll() {
        settings.update {
            $0.appearance = ThemeTabPreviewState.ResetScope.all.apply(to: $0.appearance)
        }
        updateStatus(
            ThemeTabPreviewState.statusAfterMutation(
                success: ThemeTabPreviewState.ResetScope.all.confirmation,
                persistenceError: settings.persistenceError
            )
        )
    }

    private func retrySave() {
        settings.save()
        updateStatus(
            settings.persistenceError == nil
                ? ("设置已保存。", false)
                : ThemeTabPreviewState.statusAfterMutation(
                    success: "",
                    persistenceError: settings.persistenceError
                )
        )
    }

    private func reportStatus(_ value: (text: String, warning: Bool)) {
        updateStatus(value)
    }

    private func updateStatus(_ value: (text: String, warning: Bool)) {
        status = ThemeTabStatusMessage(text: value.text, warning: value.warning)
    }
}
