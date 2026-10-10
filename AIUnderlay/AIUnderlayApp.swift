import AppKit
import SwiftUI
import AIUnderlayKit

@main
struct AIUnderlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsWindow()
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
