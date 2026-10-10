import SwiftUI
import AIUnderlayKit

/// Root settings window. The four tabs are filled in across P1–P4.
public struct SettingsWindow: View {
    public init() {}

    public var body: some View {
        TabView {
            Text("Providers")
                .tabItem { Label("Providers", systemImage: "square.stack.3d.up") }
            Text("Engine")
                .tabItem { Label("Engine", systemImage: "gearshape.2") }
            Text("Appearance")
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            Text("Diagnostics")
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 620, height: 460)
    }
}
