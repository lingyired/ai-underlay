import SwiftUI

/// 外观设置。每次改动都会通过 coordinator 重新渲染真实的覆盖层，因此你在菜单栏
/// 看到的就是真实渲染结果。
public struct AppearanceTab: View {
    @ObservedObject var store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("布局") {
                Picker("模式", selection: binding(\.layout)) {
                    Text("双侧（左右各一个）").tag(LayoutMode.dual)
                    Text("单条（整条菜单栏）").tag(LayoutMode.single)
                }
                Picker("锚点（双侧）", selection: binding(\.anchor)) {
                    Text("刘海边缘").tag(AnchorMode.notch)
                    Text("屏幕外缘").tag(AnchorMode.outerEdge)
                }
                Picker("方向（单条）", selection: binding(\.singleDirection)) {
                    Text("从左到右").tag(SingleBarDirection.leadingToTrailing)
                    Text("从右到左").tag(SingleBarDirection.trailingToLeading)
                }
            }

            Section("覆盖层") {
                Toggle("启用覆盖层", isOn: binding(\.overlayEnabled))
                Toggle("显示基准线", isOn: binding(\.showBaseline))
                Toggle("显示 Agent 动效", isOn: binding(\.showAgentEffects))
                Text("只有一套视觉引擎：Glass Spectrum（玻璃光谱）。运行时光幕移动，error > waiting > unread 用统一结构的状态灯带提示；颜色、材质与状态灯色都在“主题”页配置。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("减弱动效", isOn: binding(\.reduceMotion))
                Toggle("显示菜单栏图标", isOn: binding(\.statusItemVisible))
            }

            Section("预览（离线样例）") {
                Picker("样例", selection: binding(\.previewFixture)) {
                    Text("实时数据").tag(String?.none)
                    ForEach(FixtureSnapshots.allKeys, id: \.self) { key in
                        Text(key).tag(String?.some(key))
                    }
                }
                Text("样例数据走的是真实渲染器，无需登录任何服务商。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.settings.statusItemVisible) { _, visible in
            AppCoordinator.shared?.applyStatusItemVisibility(visible)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
