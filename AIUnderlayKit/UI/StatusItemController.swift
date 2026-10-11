import AppKit

/// The one narrow status item that opens settings. The overlay itself is
/// click-through, so this is the only menu bar affordance we add — and the user
/// can hide it.
///
/// Left-click opens the settings window directly (no menu step). Right-click
/// shows a small menu with the overlay toggle and Quit. This avoids the
/// ambiguity of a click that only reveals a menu.
@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let onOpenSettings: () -> Void
    private let onToggleOverlay: () -> Void

    public init(onOpenSettings: @escaping () -> Void, onToggleOverlay: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onToggleOverlay = onToggleOverlay
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                                   accessibilityDescription: "AI 下划线")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            Log.write("status item created; visible=\(statusItem.isVisible)")
        } else {
            Log.write("status item has NO button")
        }
    }

    public func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
        Log.write("setVisible(\(visible)) -> isVisible=\(statusItem.isVisible)")
    }

    @objc private func handleClick() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        Log.write("status item clicked; rightClick=\(isRightClick)")
        if isRightClick {
            showMenu()
        } else {
            onOpenSettings()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let toggle = NSMenuItem(title: "切换覆盖层", action: #selector(toggleOverlay), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // reset so the next left-click opens settings
    }

    @objc private func openSettings() {
        Log.write("menu: openSettings")
        onOpenSettings()
    }
    @objc private func toggleOverlay() {
        Log.write("menu: toggleOverlay")
        onToggleOverlay()
    }
    @objc private func quit() {
        Log.write("menu: quit")
        NSApp.terminate(nil)
    }
}