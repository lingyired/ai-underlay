import SwiftUI

/// Root settings view: a six-tab container. Hosted by `SettingsWindowController`.
public struct SettingsRootView: View {
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var themes: ThemeStore

    public init() {
        self.store = AppCoordinator.shared?.settings ?? SettingsStore()
        self.themes = AppCoordinator.shared?.themes ?? ThemeStore()
    }

    public var body: some View {
        TabView {
            AppearanceTab(store: store)
                .tabItem { Label("外观", systemImage: "paintbrush") }
            ThemeTab(settings: store, themes: themes)
                .tabItem { Label("主题", systemImage: "swatchpalette") }
            ProvidersTab(store: store)
                .tabItem { Label("服务商", systemImage: "square.stack.3d.up") }
            EngineTab()
                .tabItem { Label("引擎", systemImage: "gearshape.2") }
            AgentTab()
                .tabItem { Label("Agent", systemImage: "bolt.badge.clock") }
            DiagnosticsTab()
                .tabItem { Label("诊断", systemImage: "stethoscope") }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
