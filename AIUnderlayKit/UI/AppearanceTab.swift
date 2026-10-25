import SwiftUI

/// 外观设置。所有控件都写入现有 `AppSettings`；预览样本仍调用真实渲染器。
public struct AppearanceTab: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var advancedMotionExpanded = false

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            layoutSection
            overlaySection
            motionSection
            previewSection
        }
        .formStyle(.grouped)
        .onChange(of: store.settings.statusItemVisible) { _, visible in
            AppCoordinator.shared?.applyStatusItemVisibility(visible)
        }
    }

    private var layoutSection: some View {
        Section {
            Picker("排列方式", selection: binding(\.layout)) {
                Text("双侧（左右各一条）").tag(LayoutMode.dual)
                Text("单条（整条菜单栏）").tag(LayoutMode.single)
            }
            .accessibilityHint("双侧可让两家服务商各占一侧；单条只显示一家。")

            Picker("双侧起点", selection: binding(\.anchor)) {
                Text("刘海边缘").tag(AnchorMode.notch)
                Text("屏幕外缘").tag(AnchorMode.outerEdge)
            }
            .disabled(store.settings.layout == .single)
            .help(anchorHint)
            .accessibilityHint(anchorHint)

            Picker("单条方向", selection: binding(\.singleDirection)) {
                Text("从左到右").tag(SingleBarDirection.leadingToTrailing)
                Text("从右到左").tag(SingleBarDirection.trailingToLeading)
            }
            .disabled(store.settings.layout == .dual)
            .help(singleDirectionHint)
            .accessibilityHint(singleDirectionHint)

            Text(layoutFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("单提供商拆分", selection: binding(\.dualWindowSplit)) {
                Text("不拆分（同侧嵌套）").tag(DualWindowSplit.none)
                Text("5 小时在左，其余在右").tag(DualWindowSplit.sessionLeft)
                Text("5 小时在右，其余在左").tag(DualWindowSplit.sessionRight)
            }
            .disabled(!windowSplitAvailable)
            .help(windowSplitAvailabilityReason ?? "把 5 小时与周额度分到刘海左右两侧。")
            .accessibilityHint(windowSplitAvailabilityReason ?? "把 5 小时与周额度分到刘海左右两侧。")

            if let reason = windowSplitAvailabilityReason {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("用于把同一家服务商的额度分开显示：5 小时在一侧，周或月额度在另一侧。选择「不拆分」时，周额度与 5 小时额度会在同侧嵌套。两侧颜色可在「主题与颜色」页分别设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("菜单栏排列")
        }
    }

    private var overlaySection: some View {
        Section {
            Toggle("启用菜单栏覆盖层", isOn: binding(\.overlayEnabled))
            Toggle("显示预期基准线", isOn: binding(\.showBaseline))
                .disabled(!store.settings.overlayEnabled)
                .help(baselineHint)
                .accessibilityHint(baselineHint)
            Toggle("显示菜单栏图标", isOn: binding(\.statusItemVisible))
                .accessibilityHint("关闭后菜单栏图标和右键菜单都会隐藏；再次打开 App 会打开设置。")
            if !store.settings.statusItemVisible {
                Text("图标隐藏后，右键菜单也不可用。双击 App、从启动台或 Finder 再次打开，会打开设置；开启「显示菜单栏图标」即可恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("显示 Agent 状态动效", isOn: binding(\.showAgentEffects))
                .disabled(!store.settings.overlayEnabled)
                .help(agentEffectsHint)
                .accessibilityHint(agentEffectsHint)
            Toggle("减弱动效", isOn: binding(\.reduceMotion))
                .disabled(!store.settings.overlayEnabled)
                .help(reduceMotionHint)
                .accessibilityHint(reduceMotionHint)
        } header: {
            Text("菜单栏覆盖层")
        } footer: {
            Text("关闭后暂停额度与 Agent 的菜单栏绘制；菜单栏图标和已保存设置保持不变。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var motionSection: some View {
        Section {
            DisclosureGroup("调整 Agent 动效", isExpanded: $advancedMotionExpanded) {
                if let reason = motionTuningDisabledReason {
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("基础节奏") {
                    HStack(spacing: 8) {
                        Slider(value: motionFloorBinding, in: motionFloorRange)
                        Text(Self.motionReadout(store.settings.motionFloorFrequencyHz))
                            .font(.caption.monospacedDigit())
                            .frame(width: 126, alignment: .trailing)
                    }
                }
                .disabled(!motionTuningAvailable)
                .help(motionTuningDisabledReason ?? "调整 Agent 运行时一个完整呼吸循环的速度。")

                LabeledContent("波浪强度") {
                    HStack(spacing: 8) {
                        Slider(value: motionIntensityBinding, in: motionIntensityRange)
                        Text(Self.intensityReadout(store.settings.motionIntensity))
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!motionTuningAvailable)
                .help(motionTuningDisabledReason ?? "调整光线的起伏幅度，不改变额度长度或颜色。")

                Toggle("横穿扫光", isOn: binding(\.showTravelingLight))
                    .disabled(!motionTuningAvailable)
                    .help(motionTuningDisabledReason ?? "Agent 运行时，沿额度轨道移动的高光。")
                    .accessibilityHint(motionTuningDisabledReason ?? "Agent 运行时，沿额度轨道移动的高光。")

                Toggle("状态灯带流动", isOn: binding(\.showAttentionSweep))
                    .disabled(!motionTuningAvailable)
                    .help(motionTuningDisabledReason ?? "在等待、错误或未读提醒中移动的亮带。")
                    .accessibilityHint(motionTuningDisabledReason ?? "在等待、错误或未读提醒中移动的亮带。")

                HStack {
                    Button("推荐设置") {
                        store.update {
                            $0.motionFloorFrequencyHz = SpectrumRhythm.floorFrequencyHz
                            $0.motionIntensity = SpectrumRhythm.motionIntensityDefault
                            $0.showTravelingLight = true
                        }
                    }
                    .help("恢复推荐节奏与波浪强度，并打开横穿扫光。")
                    .disabled(!motionTuningAvailable)

                    Button("恢复默认") {
                        store.update {
                            $0.motionFloorFrequencyHz = nil
                            $0.motionIntensity = nil
                        }
                    }
                    .disabled(!motionTuningAvailable)
                }

                Text(motionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Agent 动效")
        } footer: {
            Text("只有 Agent 运行时才持续运动。等待、错误和未读提醒仍有静态灯带；减弱动效会关闭持续运动。当前没有真实输出速度，基础节奏就是可见速度。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewSection: some View {
        Section {
            Picker("预览内容", selection: binding(\.previewFixture)) {
                Text("实时额度").tag(String?.none)
                ForEach(SettingsPreviewCatalog.options) { option in
                    Text(option.title).tag(Optional(option.key))
                }
            }
            .accessibilityHint("选择后，菜单栏会立即改用本机生成的样例数据。")

            if let key = store.settings.previewFixture {
                let option = SettingsPreviewCatalog.option(for: key)
                Text(option.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("预览保持到退出为止；顶部横幅可随时恢复实时额度。", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("选择一个场景后，菜单栏会立即切换，并在所有设置页面保留预览提示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("离线预览")
        } footer: {
            Text("预览沿用当前布局与主题，但样例中的额度和 Agent 状态都是虚构的。关闭覆盖层时不会显示预览。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Layout dependencies

    private var enabledProviders: [String] {
        AIUnderlayKit.supportedProviders.filter {
            store.settings.enabledProviders.contains($0)
        }
    }

    private var preferredSingleProvider: String? {
        enabledProviders.first
    }

    private var layoutFootnote: String {
        let provider = preferredSingleProvider.map(providerDisplayName) ?? "尚未启用"
        switch store.settings.layout {
        case .single:
            if enabledProviders.isEmpty {
                return "当前为单条布局，但还没有启用的服务商。请先到「服务商」页打开一家。"
            }
            if enabledProviders.count == 1 {
                return "单条布局显示当前唯一启用的服务商：\(provider)。若要改用另一家，请先到「服务商」页切换。"
            }
            return "单条布局固定优先显示 Codex（当前显示 \(provider)）。要用 Claude Code，请在「服务商」页关闭 Codex，只保留 Claude Code。"
        case .dual:
            if enabledProviders.count == 1 {
                return store.settings.dualWindowSplit == .none
                    ? "当前只启用 \(provider)，额度会嵌套在同一侧。再启用一家可让两家各占一侧；或启用「单提供商拆分」。"
                    : "当前只启用 \(provider)，已把额度分到双侧。再启用一家会让单提供商拆分失效。"
            }
            if enabledProviders.count > 1 {
                return "两家服务商会各自分占两侧；单条方向只影响单条布局。"
            }
            return "双侧布局当前没有可显示的服务商；请先在「服务商」页启用一家。"
        }
    }

    // MARK: - Split dependencies

    /// Splitting one provider's windows across two sides only applies in dual
    /// mode with exactly one provider enabled.
    private var windowSplitAvailable: Bool {
        store.settings.layout == .dual && enabledProviders.count == 1
    }

    private var windowSplitAvailabilityReason: String? {
        guard store.settings.layout == .dual else {
            return "仅双侧布局可用：先选择上方「双侧」。"
        }
        switch enabledProviders.count {
        case 0:
            return "先在「服务商」页启用一家服务商。"
        case 1:
            return nil
        default:
            return "仅启用一家服务商时可用；当前两家各占一侧，单提供商拆分没有作用。"
        }
    }

    // MARK: - Motion dependencies

    private var motionAvailabilityReason: String? {
        if !store.settings.overlayEnabled {
            return "覆盖层已关闭；重新打开覆盖层后才能使用动效。"
        }
        return nil
    }

    private var motionTuningAvailable: Bool {
        store.settings.overlayEnabled
            && store.settings.showAgentEffects
            && !store.settings.reduceMotion
            && !systemReduceMotion
    }

    private var motionTuningDisabledReason: String? {
        if let reason = motionAvailabilityReason {
            return reason
        }
        if !store.settings.showAgentEffects {
            return systemReduceMotion
                ? "Agent 状态动效已关闭；macOS「减弱动态效果」也已开启。重新打开 Agent 动效并关闭系统减弱效果后才能调整。"
                : "Agent 状态动效已关闭；重新打开后才能调整。"
        }
        if store.settings.reduceMotion {
            return systemReduceMotion
                ? "已开启「减弱动效」；macOS「减弱动态效果」也已开启。关闭两者后才能调整。"
                : "已开启「减弱动效」；关闭后才能调整。"
        }
        if systemReduceMotion {
            return "macOS「减弱动态效果」已开启；系统设置关闭前不能用应用内参数调整动效。你的应用内偏好不会被改写。"
        }
        return nil
    }

    private var motionFloorRange: ClosedRange<Double> {
        SpectrumRhythm.minimumFloorFrequencyHz...SpectrumRhythm.ceilingFrequencyHz
    }

    private var motionIntensityRange: ClosedRange<Double> {
        SpectrumRhythm.minimumMotionIntensity...SpectrumRhythm.maximumMotionIntensity
    }

    private var motionSummary: String {
        let tempo = Self.motionReadout(store.settings.motionFloorFrequencyHz)
        let source = store.settings.motionFloorFrequencyHz == nil
            ? "推荐节奏"
            : "自定义节奏"
        return "当前：\(source)，\(tempo)。当前没有真实输出速度，因此按这个节奏匀速运行。"
    }

    private var motionFloorBinding: Binding<Double> {
        Binding(
            get: { SpectrumRhythm.clampedFloor(store.settings.motionFloorFrequencyHz) },
            set: { hz in
                store.update {
                    $0.motionFloorFrequencyHz = SpectrumRhythm.clampedFloor(hz)
                }
            }
        )
    }

    private var motionIntensityBinding: Binding<Double> {
        Binding(
            get: { SpectrumRhythm.clampedIntensity(store.settings.motionIntensity) },
            set: { value in
                store.update {
                    $0.motionIntensity = SpectrumRhythm.clampedIntensity(value)
                }
            }
        )
    }

    private static func motionReadout(_ hz: Double?) -> String {
        let resolved = SpectrumRhythm.clampedFloor(hz)
        return String(format: "%.2f Hz · %.1f 秒/圈", resolved, 1 / resolved)
    }

    private static func intensityReadout(_ intensity: Double?) -> String {
        String(format: "%.2f", SpectrumRhythm.clampedIntensity(intensity))
    }

    private func providerDisplayName(_ id: String) -> String {
        switch id {
        case "codex": return "Codex"
        case "claude": return "Claude Code"
        default: return id
        }
    }

    private var anchorHint: String {
        store.settings.layout == .single
            ? "仅双侧布局可用；单条布局的起点由方向决定。"
            : "选择双侧额度条从刘海边缘还是屏幕外缘开始绘制。"
    }

    private var singleDirectionHint: String {
        store.settings.layout == .dual
            ? "仅单条布局可用；双侧布局的起点由上方的「双侧起点」决定。"
            : "选择单条额度从左向右还是从右向左增长。"
    }

    private var baselineHint: String {
        store.settings.overlayEnabled
            ? "在额度轨道上显示按时间推算的预期余额，便于比较实际消耗。"
            : "覆盖层已关闭；重新打开后才能显示预期基准线。"
    }

    private var agentEffectsHint: String {
        store.settings.overlayEnabled
            ? "在 Agent 运行时显示动态光效，并在等待、错误或未读完成时显示状态灯带。"
            : "覆盖层已关闭；重新打开后才能显示 Agent 状态动效。"
    }

    private var reduceMotionHint: String {
        store.settings.overlayEnabled
            ? "停止持续运动，保留静态额度、状态颜色和提醒灯带。"
            : "覆盖层已关闭；重新打开后才能调整动态效果。"
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
