import SwiftUI

/// Progressive color controls. Every swatch reads the same resolver output the
/// renderer reads, and every restore action is scoped to its own value group.
struct ThemeTabColorsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var themes: ThemeStore
    let reportStatus: ((text: String, warning: Bool)) -> Void
    @State private var expanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                providerTints
                Divider()
                quotaColors
                Divider()
                signalColors
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label("自定义颜色", systemImage: "paintpalette")
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var providerTints: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupHeader("服务商玻璃主题色", scope: .providerTints)
            colorRow("Codex", field: .glassTint(providerId: "codex"))
            colorRow("Claude", field: .glassTint(providerId: "claude"))
            Text("玻璃主题色只改变对应服务商的表面颜色，不影响额度颜色、状态灯或另一侧。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var quotaColors: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupHeader("额度颜色", scope: .quotaColors)
            colorRow("Codex", field: .quotaBase(providerId: "codex"))
            colorRow("Claude", field: .quotaBase(providerId: "claude"))
            colorRow("用尽底色", field: .exhaustedTrack)
            Text("额度颜色独立于玻璃主题色；使用后的区域保持该底色，真实剩余额度不会被改写。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            groupHeader("单服务商双侧拆分", scope: .splitColors)
            colorRow("5 小时侧", field: .split(role: .session))
            colorRow("周额度侧", field: .split(role: .weekly))
            Text("仅在启用一家服务商的双侧拆分布局中使用。5 小时侧默认偏色，周额度侧沿用服务商额度色。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var signalColors: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupHeader("状态灯颜色", scope: .signalColors)
            colorRow("运行中", field: .signal(key: .running))
            colorRow("故障", field: .signal(key: .error))
            colorRow("等待你", field: .signal(key: .waiting))
            colorRow("未读完成（仅预览）", field: .signal(key: .unread))
            Text("未读完成目前仅提供示例预览。状态灯按“故障 > 等待你 > 未读完成”显示；有任务运行时，动效会继续。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func colorRow(
        _ label: String,
        field: ThemeTabPreviewState.ColorField
    ) -> some View {
        let providerId = field.providerId ?? previewProviderId
        let fallback = ThemeTabPreviewState.fallbackColor(
            for: field,
            theme: themes.activeTheme,
            providerId: providerId,
            appearance: settings.settings.appearance
        )
        let source = ThemeTabPreviewState.source(
            for: field,
            appearance: settings.settings.appearance,
            theme: themes.activeTheme
        )
        return HStack(spacing: 10) {
            ColorPicker(
                label,
                selection: Binding(
                    get: {
                        Color(ThemeTabPreviewState.effectiveColor(
                            for: field,
                            theme: themes.activeTheme,
                            providerId: providerId,
                            appearance: settings.settings.appearance
                        ))
                    },
                    set: { color in
                        let resolved = RGBAColor(color, fallback: fallback)
                        settings.update {
                            ThemeTabPreviewState.write(resolved, for: field, to: &$0.appearance)
                        }
                        reportStatus(ThemeTabPreviewState.statusAfterMutation(
                                success: "\(label)颜色已更新。",
                                persistenceError: settings.persistenceError
                            ))
                    }
                )
            )
            Spacer(minLength: 8)
            Text(source.label)
                .font(.caption)
                .foregroundStyle(source == .invalidPersonal ? .orange : .secondary)
            if field.isOverridden(in: settings.settings.appearance) {
                Button("跟随主题") {
                    settings.update {
                        ThemeTabPreviewState.clear(field, from: &$0.appearance)
                    }
                    reportStatus(ThemeTabPreviewState.statusAfterMutation(
                            success: "\(label)已恢复为当前主题。",
                            persistenceError: settings.persistenceError
                        ))
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func groupHeader(
        _ title: String,
        scope: ThemeTabPreviewState.ResetScope
    ) -> some View {
        let appearance = settings.settings.appearance
        return HStack {
            Text(title)
                .font(.headline)
            Spacer()
            if scope.hasOverrides(in: appearance) {
                Button("恢复本组") {
                    settings.update {
                        $0.appearance = scope.apply(to: $0.appearance)
                    }
                    reportStatus(ThemeTabPreviewState.statusAfterMutation(
                            success: scope.confirmation,
                            persistenceError: settings.persistenceError
                        ))
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var previewProviderId: String {
        let enabled = AIUnderlayKit.supportedProviders.filter {
            settings.settings.enabledProviders.contains($0)
        }
        return enabled.first ?? AIUnderlayKit.supportedProviders.first ?? "codex"
    }

    private var summary: String {
        ThemeTabPreviewState.ResetScope.providerTints.hasOverrides(in: settings.settings.appearance)
            || ThemeTabPreviewState.ResetScope.quotaColors.hasOverrides(in: settings.settings.appearance)
            || ThemeTabPreviewState.ResetScope.splitColors.hasOverrides(in: settings.settings.appearance)
            || ThemeTabPreviewState.ResetScope.signalColors.hasOverrides(in: settings.settings.appearance)
            ? "部分颜色为个人设置；可逐项或按分组恢复。"
            : "玻璃、额度、拆分与状态灯颜色彼此独立。"
    }
}
