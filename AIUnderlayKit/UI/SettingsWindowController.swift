import AppKit
import SwiftUI

/// Hosts the SwiftUI settings view in an ordinary window. An accessory app
/// cannot rely on the SwiftUI `Settings` scene's `showSettingsWindow:` action,
/// so we manage the window ourselves — and activate explicitly, because an
/// accessory app is not frontmost by default and its window would otherwise
/// appear behind the current app.
@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?

    public init() {}

    public func show<Content: View>(_ content: Content) {
        // Bring the app forward first; without this the window is created but
        // stays behind whichever app is currently frontmost.
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "AI 下划线 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 660, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
