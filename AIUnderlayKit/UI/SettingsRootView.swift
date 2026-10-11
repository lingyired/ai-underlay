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
                .tabItem { Label("外观", systemImage: "paintbrush") }
            ProvidersTab()
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
