import SwiftUI
import AppKit
import AIUnderlayKit

/// Diagnostics. Shows measured geometry and overlay state, with a desensitized
/// copy button. Expanded in P4.
struct DiagnosticsTab: View {
    @State private var snapshot = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.title2)

            ScrollView {
                Text(snapshot.isEmpty ? "Press Refresh." : snapshot)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)

            HStack {
                Button("Refresh") { snapshot = collect() }
                Button("Copy (desensitized)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snapshot, forType: .string)
                }
                .disabled(snapshot.isEmpty)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { snapshot = collect() }
    }

    private func collect() -> String {
        var lines: [String] = []
        lines.append("AIUnderlayKit \(AIUnderlayKit.version)")
        lines.append("Displays: \(NSScreen.screens.count)")
        for screen in NSScreen.screens {
            let id = MenuBarOverlayController.displayID(for: screen)
            let height = MenuBarOverlayController.menuBarHeight(for: screen)
            let notch = MenuBarGeometry.notchEdges(for: screen)
            lines.append("  display \(id): frame=\(screen.frame) scale=\(screen.backingScaleFactor)")
            lines.append("    menuBarHeight=\(height) notch=\(notch.map { "\($0)" } ?? "none")")
        }
        lines.append("Managed band windows: \(AppCoordinator.shared?.overlay.managedBandCount ?? 0)")
        lines.append("On-screen band windows: \(BandWatchdog.onScreenBandCount())")
        return CodexBarCLIClient.desensitize(lines.joined(separator: "\n"))
    }
}