import SwiftUI
import AIUnderlayKit

/// Root settings window. The four tabs are filled in across P1–P4.
public struct SettingsWindow: View {
    @ObservedObject private var store: SettingsStore

    public init() {
        // The coordinator is created before the settings scene is shown.
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
        .frame(width: 640, height: 480)
    }
}