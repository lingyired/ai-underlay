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
                Picker("运行中动效", selection: binding(\.runningEffect)) {
                    Text("呼吸灯").tag(RunningEffect.breathing)
                    Text("扫光").tag(RunningEffect.sweep)
                    Text("端点脉冲").tag(RunningEffect.dot)
                    Text("频谱柱").tag(RunningEffect.spectrum)
                    Text("无").tag(RunningEffect.none)
                }
                .disabled(!store.settings.showAgentEffects)
                Picker("运行中颜色", selection: binding(\.runningEffectColor)) {
                    Text("绿（工作中）").tag(RunningEffectColor.green)
                    Text("白").tag(RunningEffectColor.white)
                    Text("蓝").tag(RunningEffectColor.blue)
                    Text("橙").tag(RunningEffectColor.orange)
                    Text("紫").tag(RunningEffectColor.purple)
                }
                .disabled(!store.settings.showAgentEffects)
                Text("状态靠颜色区分：运行=绿、等待=琥珀/橙、错误=红、完成=青。此处只改“运行中”的颜色。")
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
