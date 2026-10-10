import SwiftUI

/// Live appearance controls. Every change re-renders the real overlay via the
/// coordinator, so what you see in the menu bar is the true renderer output.
public struct AppearanceTab: View {
    @ObservedObject var store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Layout") {
                Picker("Mode", selection: binding(\.layout)) {
                    Text("Dual (two sides)").tag(LayoutMode.dual)
                    Text("Single (full width)").tag(LayoutMode.single)
                }
                Picker("Anchor (dual)", selection: binding(\.anchor)) {
                    Text("Notch edge").tag(AnchorMode.notch)
                    Text("Screen edge").tag(AnchorMode.outerEdge)
                }
                Picker("Direction (single)", selection: binding(\.singleDirection)) {
                    Text("Left to right").tag(SingleBarDirection.leadingToTrailing)
                    Text("Right to left").tag(SingleBarDirection.trailingToLeading)
                }
            }

            Section("Overlay") {
                Toggle("Show baseline marker", isOn: binding(\.showBaseline))
                Toggle("Show agent effects", isOn: binding(\.showAgentEffects))
                Toggle("Reduce motion", isOn: binding(\.reduceMotion))
                Toggle("Show status bar icon", isOn: binding(\.statusItemVisible))
            }

            Section("Preview (offline fixtures)") {
                Picker("Fixture", selection: binding(\.previewFixture)) {
                    Text("Live data").tag(String?.none)
                    ForEach(FixtureSnapshots.allKeys, id: \.self) { key in
                        Text(key).tag(String?.some(key))
                    }
                }
                Text("Fixtures drive the real renderer — no login required.")
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
