import SwiftUI

/// Agent detection setup. Installation is always preview → confirm; the app
/// never touches `~/.claude/settings.json` on its own.
public struct AgentTab: View {
    @State private var preview: HookSetupCoordinator.ChangePreview?
    @State private var installed = false
    @State private var status = ""

    private let coordinator = HookSetupCoordinator()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Detection").font(.title2)
            Text("Detects Claude Code (and Codex where the host emits events) lifecycle so the menu bar can show running / waiting states. Nothing is installed until you confirm.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Preview hook changes") {
                    preview = try? coordinator.preview()
                    status = ""
                }
                Button(installed ? "Uninstall hooks" : "Install hooks") {
                    if installed {
                        try? coordinator.uninstall()
                        installed = coordinator.isInstalled()
                        status = "Removed only the app-managed hook entries."
                    } else {
                        try? coordinator.install(confirmed: true)
                        installed = coordinator.isInstalled()
                        status = "Installed. A backup of your previous settings was written."
                    }
                    preview = nil
                }
                .disabled(preview == nil && !installed)
            }

            if let preview {
                Text("Will add \(preview.addedCommands.count) hook entries. Preview:")
                    .font(.caption)
                ScrollView {
                    Text(preview.after)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }

            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { installed = coordinator.isInstalled() }
    }
}
