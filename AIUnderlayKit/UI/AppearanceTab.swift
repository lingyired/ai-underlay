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

            motionSection

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

    /// The Glass Spectrum tempo the menu bar actually runs at. Real tokens/s is
    /// not wired yet, so this floor *is* the visible speed — the slider is the
    /// fastest way to compare candidates before one is baked in as the default.
    private var motionSection: some View {
        Section {
            LabeledContent("基础节奏") {
                HStack(spacing: 8) {
                    Slider(
                        value: motionFloorBinding,
                        in: SpectrumRhythm.minimumFloorFrequencyHz...SpectrumRhythm.ceilingFrequencyHz
                    )
                    Text(Self.motionReadout(store.settings.motionFloorFrequencyHz))
                        .font(.caption.monospacedDigit())
                        .frame(width: 124, alignment: .trailing)
                }
            }
            LabeledContent("波浪强度") {
                HStack(spacing: 8) {
                    Slider(
                        value: motionIntensityBinding,
                        in: SpectrumRhythm.minimumMotionIntensity...SpectrumRhythm.maximumMotionIntensity
                    )
                    Text(Self.intensityReadout(store.settings.motionIntensity))
                        .font(.caption.monospacedDigit())
                        .frame(width: 124, alignment: .trailing)
                }
            }
            HStack {
                ForEach(Self.motionPresets, id: \.hz) { preset in
                    Button(preset.label) {
                        store.update { $0.motionFloorFrequencyHz = preset.hz }
                    }
                    .help("\(String(format: "%.2f", preset.hz)) Hz · \(String(format: "%.1f", 1 / preset.hz)) 秒/圈")
                }
            }
            Text(Self.tempoStatus(store.settings))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("使用推荐运动设置") {
                    store.update {
                        $0.motionFloorFrequencyHz = SpectrumRhythm.floorFrequencyHz
                        $0.motionIntensity = SpectrumRhythm.motionIntensityDefault
                        $0.showTravelingLight = true
                    }
                }
                .help("会把基础节奏设为 \(String(format: "%.2f", SpectrumRhythm.floorFrequencyHz)) Hz（\(String(format: "%.1f", 1 / SpectrumRhythm.floorFrequencyHz)) 秒/圈）、波浪强度设为 \(String(format: "%.2f", SpectrumRhythm.motionIntensityDefault))，并打开「横穿扫光」。不动状态灯带扫光，也不动主题、布局和额度设置。")
                Button("恢复默认") {
                    store.update {
                        $0.motionFloorFrequencyHz = nil
                        $0.motionIntensity = nil
                    }
                }
            }
            Toggle("横穿扫光", isOn: binding(\.showTravelingLight))
            Toggle("状态灯带扫光", isOn: binding(\.showAttentionSweep))
        } header: {
            Text("Agent 动效节奏")
        } footer: {
            Text("一个完整循环的时长：默认 \(String(format: "%.2f", 1 / SpectrumRhythm.floorFrequencyHz)) 秒，越小越快（上限 \(String(format: "%.2f", SpectrumRhythm.ceilingFrequencyHz)) Hz，约 \(String(format: "%.1f", 1 / SpectrumRhythm.ceilingFrequencyHz)) 秒/圈）。真实 tok/s 尚未接入，所以这里就是菜单栏的实际速度；接入后它只会成为速度曲线的下限，不影响颜色和亮度。\n关掉「横穿扫光」只是不再有横扫过去的高光，射线自身仍按波浪起伏；关掉「状态灯带扫光」保留顶线与底带，只去掉在其中来回的亮带。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private struct MotionPreset {
        var hz: Double
        var label: String { String(format: "%.1f 秒", 1 / hz) }
    }

    private static let motionPresets: [MotionPreset] = [
        MotionPreset(hz: SpectrumRhythm.tempoPresets[0]),
        MotionPreset(hz: SpectrumRhythm.tempoPresets[1]),
        MotionPreset(hz: SpectrumRhythm.tempoPresets[2]),
        MotionPreset(hz: SpectrumRhythm.tempoPresets[3]),
    ]

    private static func motionReadout(_ hz: Double?) -> String {
        let resolved = SpectrumRhythm.clampedFloor(hz)
        return String(format: "%.2f Hz · %.1f 秒/圈", resolved, 1 / resolved)
    }

    private static func intensityReadout(_ intensity: Double?) -> String {
        String(format: "%.2f", SpectrumRhythm.clampedIntensity(intensity))
    }

    /// Which tempo is actually on screen right now: the built-in baseline, the
    /// user's own value, and (once it exists) the measured-speed curve are
    /// three different things, and the settings page must not blur them.
    private static func tempoStatus(_ settings: AppSettings) -> String {
        let resolved = SpectrumRhythm.clampedFloor(settings.motionFloorFrequencyHz)
        let tempo = String(format: "%.2f Hz · %.1f 秒/圈", resolved, 1 / resolved)
        let source = settings.motionFloorFrequencyHz == nil
            ? "默认基础节奏"
            : "你保存的基础节奏"
        return "当前生效：\(source) \(tempo)，按基础节奏运行（真实 tok/s 尚未接入）。"
    }

    private var motionFloorBinding: Binding<Double> {
        Binding(
            get: { SpectrumRhythm.clampedFloor(store.settings.motionFloorFrequencyHz) },
            set: { hz in store.update { $0.motionFloorFrequencyHz = SpectrumRhythm.clampedFloor(hz) } }
        )
    }

    private var motionIntensityBinding: Binding<Double> {
        Binding(
            get: { SpectrumRhythm.clampedIntensity(store.settings.motionIntensity) },
            set: { value in store.update { $0.motionIntensity = SpectrumRhythm.clampedIntensity(value) } }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
