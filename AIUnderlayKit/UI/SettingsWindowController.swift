import AppKit
import SwiftUI

/// Hosts the SwiftUI settings view in an ordinary window. An accessory app
/// cannot rely on the SwiftUI `Settings` scene's `showSettingsWindow:` action,
/// so we manage the window ourselves.
@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?

    public init() {}

    public func show<Content: View>(_ content: Content) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "AI Underlay Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 640, height: 500))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}