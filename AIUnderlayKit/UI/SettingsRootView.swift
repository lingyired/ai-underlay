import SwiftUI

/// Root settings view: a five-tab container. Hosted by `SettingsWindowController`.
public struct SettingsRootView: View {
    @ObservedObject private var store: SettingsStore

    public init() {
        self.store = AppCoordinator.shared?.settings ?? SettingsStore()
    }

    public var body: some View {
        TabView {
            AppearanceTab(store: store)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ProvidersTab()
                .tabItem { Label("Providers", systemImage: "square.stack.3d.up") }
            EngineTab()
                .tabItem { Label("Engine", systemImage: "gearshape.2") }
            AgentTab()
                .tabItem { Label("Agent", systemImage: "bolt.badge.clock") }
            DiagnosticsTab()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(minWidth: 620, minHeight: 460)
    }
}
