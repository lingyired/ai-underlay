import AppKit
import SwiftUI
import AIUnderlayKit

@main
struct AIUnderlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The settings UI is hosted in an explicit window by
        // SettingsWindowController; this scene is a minimal placeholder.
        Settings {
            EmptyView()
        }
    }
}

/// Accessory app lifecycle owner. Keeps the app out of the Dock and wires up
/// the coordinator once the app is ready.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator

        // `--open-settings` opens the settings window on launch; used for
        // scripted verification and screenshots.
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                SettingsOpener.open()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
