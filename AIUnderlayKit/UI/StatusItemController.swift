import AppKit

/// The one narrow status item that opens settings. The overlay itself is
/// click-through, so this is the only menu bar affordance we add — and the user
/// can hide it.
@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem
    private let onOpenSettings: () -> Void
    private let onToggleOverlay: () -> Void

    public init(onOpenSettings: @escaping () -> Void, onToggleOverlay: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onToggleOverlay = onToggleOverlay
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "切换覆盖层", action: #selector(toggleOverlay), keyEquivalent: "o")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
            .target = self

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                                   accessibilityDescription: "AI 下划线")
            button.image?.isTemplate = true
            button.menu = menu
            NSLog("[AIUnderlay] status item created; visible=\(statusItem.isVisible) button=\(button)")
        } else {
            NSLog("[AIUnderlay] status item has NO button")
        }
    }

    public func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
        NSLog("[AIUnderlay] setVisible(\(visible)) -> isVisible=\(statusItem.isVisible)")
    }

    @objc private func openSettings() {
        NSLog("[AIUnderlay] menu: 设置")
        onOpenSettings()
    }
    @objc private func toggleOverlay() {
        NSLog("[AIUnderlay] menu: 切换覆盖层")
        onToggleOverlay()
    }
    @objc private func quit() {
        NSLog("[AIUnderlay] menu: 退出")
        NSApp.terminate(nil)
    }
}