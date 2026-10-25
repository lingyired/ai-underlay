import SwiftUI

/// Material controls display the resolved, clamped renderer inputs. Writing one
/// slider records only that field, so the rest continue following the theme.
struct ThemeTabMaterialView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var themes: ThemeStore
    let reportStatus: ((text: String, warning: Bool)) -> Void
    @State private var expanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                HStack {
                    Text("每项都显示渲染器实际采用的数值。调整任意一项后，它才会成为个人覆盖。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if hasOverrides {
                        Button("跟随当前主题", action: restoreAll)
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                slider(ThemeTab.softnessLabel, field: .softness)
                Text("往左更清晰，往右更柔和；0 为清晰，17 为 V5 默认，32 最柔。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                slider("环境泛光", field: .ambientGlow)
                slider("颗粒质感", field: .grain)
                slider("光线密度", field: .rayDensity)
                slider("额度层不透明度", field: .quotaOpacity)
                slider("主题色强度", field: .themeStrength)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label("玻璃材质", systemImage: "circle.lefthalf.filled")
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func slider(
        _ label: String,
        field: ThemeTabPreviewState.MaterialField
    ) -> some View {
        let source = ThemeTabPreviewState.source(
            for: field,
            theme: themes.activeTheme,
            appearance: settings.settings.appearance
        )
        let value = field.value(in: ThemeTabPreviewState.material(
            theme: themes.activeTheme,
            appearance: settings.settings.appearance
        ))
        return HStack(spacing: 10) {
            Text(label)
            Slider(
                value: Binding(
                    get: {
                        field.value(in: ThemeTabPreviewState.material(
                            theme: themes.activeTheme,
                            appearance: settings.settings.appearance
                        ))
                    },
                    set: { newValue in
                        settings.update {
                            ThemeTabPreviewState.write(newValue, for: field, to: &$0.appearance)
                        }
                        reportStatus(ThemeTabPreviewState.statusAfterMutation(
                                success: "\(label)已更新为 \(field.display(newValue))。",
                                persistenceError: settings.persistenceError
                            ))
                    }
                ),
                in: field.range,
                step: field.step
            )
            .accessibilityLabel(label)
            Text(field.display(value))
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
            Text(source.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
            if source == .personal {
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
        .help(
            field == .softness
                ? ThemeTab.softnessNote
                : "显示当前渲染器实际采用的值"
        )
    }

    private func restoreAll() {
        settings.update {
            $0.appearance = ThemeTabPreviewState.ResetScope.material.apply(to: $0.appearance)
        }
        reportStatus(ThemeTabPreviewState.statusAfterMutation(
                success: ThemeTabPreviewState.ResetScope.material.confirmation,
                persistenceError: settings.persistenceError
            ))
    }

    private var hasOverrides: Bool {
        ThemeTabPreviewState.ResetScope.material.hasOverrides(
            in: settings.settings.appearance
        )
    }

    private var summary: String {
        if hasOverrides {
            return "部分参数为个人设置；数值与渲染器实际结果一致。"
        }
        return "跟随当前主题；展开后可调整柔化、泛光与强度。"
    }
}
