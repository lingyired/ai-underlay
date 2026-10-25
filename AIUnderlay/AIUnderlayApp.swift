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
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { SettingsOpener.open() }
                    .keyboardShortcut(",", modifiers: .command)
            }
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

        // Single-instance guard: a second copy would create a duplicate status
        // item and its own overlay bands. If we are not the first instance,
        // hand focus to the existing one and exit.
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            // Ask the already-running instance to open its settings window, then
            // exit. This makes "launch the app again" a reliable way to reach
            // settings even if the status item is hard to find.
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.lingsmbp.aiunderlay.openSettings"),
                object: nil, userInfo: nil, deliverImmediately: true)
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }

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
        if CommandLine.arguments.contains("--open-popup") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                AppCoordinator.shared?.togglePopover()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Fired when the app is reopened while already running (double-click in
    /// Finder, `open`, or launching again). Always opens settings, including
    /// when the user hid the status item and there is no popup anchor.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsOpener.open()
        return true
    }
}
