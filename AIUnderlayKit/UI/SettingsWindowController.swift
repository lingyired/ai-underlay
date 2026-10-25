import AppKit
import SwiftUI

/// Hosts the SwiftUI settings view in an ordinary window. An accessory app
/// cannot rely on the SwiftUI `Settings` scene's `showSettingsWindow:` action,
/// so we manage the window ourselves and activate it explicitly.
@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?

    public init() {}

    public func show<Content: View>(_ content: Content) {
        Log.write("SettingsWindowController.show called")
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "AI Underlay 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.setContentSize(NSSize(width: 980, height: 700))
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
