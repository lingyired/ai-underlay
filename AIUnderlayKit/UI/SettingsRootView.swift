import SwiftUI

/// Root settings view. The sidebar separates everyday controls from tools
/// used mainly for setup and troubleshooting.
public struct SettingsRootView: View {
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var themes: ThemeStore
    @State private var selection: SettingsPage? = .appearance

    public init() {
        self.store = AppCoordinator.shared?.settings ?? SettingsStore()
        self.themes = AppCoordinator.shared?.themes ?? ThemeStore()
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("日常") {
                    ForEach(SettingsPage.daily) { page in
                        sidebarRow(page)
                    }
                }

                Section("高级") {
                    ForEach(SettingsPage.advanced) { page in
                        sidebarRow(page)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("AI Underlay")
            .navigationSplitViewColumnWidth(min: 176, ideal: 196, max: 236)
            .accessibilityLabel("设置页面")
            .frame(minHeight: 360, maxHeight: .infinity)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder
    private var detail: some View {
        let page = selection ?? .appearance

        VStack(spacing: 0) {
            if let error = store.persistenceError {
                persistenceBanner(error)
            }
            if let fixture = store.settings.previewFixture {
                previewBanner(fixture)
            }

            SettingsPageHeader(page: page)
            Divider()

            pageContent(page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarRow(_ page: SettingsPage) -> some View {
        Label(page.title, systemImage: page.symbol)
            .tag(page)
            .accessibilityLabel(page.title)
            .accessibilityHint(page.subtitle)
    }

    @ViewBuilder
    private func pageContent(_ page: SettingsPage) -> some View {
        switch page {
        case .appearance:
            AppearanceTab(store: store)
        case .theme:
            ThemeTab(settings: store, themes: themes)
        case .providers:
            ProvidersTab(store: store)
        case .engine:
            EngineTab()
        case .downloads:
            DownloadsTab(store: store)
        case .agent:
            AgentTab()
        case .diagnostics:
            DiagnosticsTab()
        }
    }

    private func persistenceBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("设置尚未保存")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Button("重试保存") {
                store.save()
            }
            .buttonStyle(.bordered)
            .help("再次尝试把当前设置写入磁盘")
            .accessibilityHint("修改仍会立即生效；重试会再次保存")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func previewBanner(_ key: String) -> some View {
        let option = SettingsPreviewCatalog.option(for: key)

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("正在预览：\(option.title)")
                    .font(.callout.weight(.semibold))
                Text("当前菜单栏使用模拟数据，不代表你的真实额度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("退出预览") {
                store.update { $0.previewFixture = nil }
            }
            .buttonStyle(.bordered)
            .help("让菜单栏立即恢复实时额度")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.09))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance
    case theme
    case providers
    case engine
    case downloads
    case agent
    case diagnostics

    var id: String { rawValue }

    static let daily: [SettingsPage] = [.appearance, .theme, .providers]
    static let advanced: [SettingsPage] = [.engine, .downloads, .agent, .diagnostics]

    var title: String {
        switch self {
        case .appearance: return "外观与布局"
        case .theme: return "主题与颜色"
        case .providers: return "服务商"
        case .engine: return "运行引擎"
        case .downloads: return "下载监控"
        case .agent: return "Agent 集成"
        case .diagnostics: return "诊断"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance:
            return "调整菜单栏布局、覆盖层和离线预览；修改会立即生效。"
        case .theme:
            return "选择玻璃外观，并设置额度、双侧拆分和状态信号的颜色。"
        case .providers:
            return "选择要获取额度的服务商，并检查连接状态。"
        case .engine:
            return "检查本机连接、兼容性和网络代理。"
        case .downloads:
            return "统计落地页网盘按钮的下载次数，并查看实时状态。"
        case .agent:
            return "连接 Codex 与 Claude Code，让菜单栏显示 Agent 状态。"
        case .diagnostics:
            return "查看覆盖层运行信息，复制已脱敏的排障记录。"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: return "paintbrush"
        case .theme: return "swatchpalette"
        case .providers: return "square.stack.3d.up"
        case .engine: return "gearshape.2"
        case .downloads: return "arrow.down.circle"
        case .agent: return "bolt.badge.clock"
        case .diagnostics: return "stethoscope"
        }
    }
}

private struct SettingsPageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: page.symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(.title2.weight(.semibold))
                Text(page.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
