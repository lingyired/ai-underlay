import AppKit

/// The menu bar affordance. Left-click toggles the dashboard popup; right-click
/// shows a small menu. The overlay itself is click-through, so this is the only
/// interactive menu bar element we add — and the user can hide it.
@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let onTogglePopover: () -> Void
    private let onOpenSettings: () -> Void
    private let onToggleOverlay: () -> Void

    public init(
        onTogglePopover: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onToggleOverlay: @escaping () -> Void
    ) {
        self.onTogglePopover = onTogglePopover
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

    /// The status button's frame in screen coordinates, for anchoring the popup.
    public var buttonScreenRect: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
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
            onTogglePopover()
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