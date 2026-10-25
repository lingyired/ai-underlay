import AppKit

/// The menu bar affordance. Left-click toggles the dashboard popup; right-click
/// shows a small menu. The overlay itself is click-through, so this is the only
/// interactive menu bar element we add — and the user can hide it.
@MainActor
public final class StatusItemController {
    /// Compact click target for the menu-bar glyph. Wider system symbols may
    /// expand this floor so their artwork is never clipped.
    nonisolated public static let targetLength: CGFloat = 36

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
            let symbol = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                                 accessibilityDescription: "AI Underlay")
            let image = Self.paddedTemplateImage(symbol)
            statusItem.length = image.size.width
            button.image = image
            button.imagePosition = .imageOnly
            button.alignment = .center
            button.toolTip = "AI Underlay · 点击查看额度，右键打开设置"
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            Log.write(
                "status item created; visible=\(statusItem.isVisible), " +
                "length=\(statusItem.length), buttonWidth=\(button.frame.width)"
            )
        } else {
            Log.write("status item has NO button")
        }
    }

    /// Keeps the glyph centered inside a 36pt target.
    nonisolated public static func preferredLength(forIconWidth iconWidth: CGFloat) -> CGFloat {
        max(max(0, iconWidth), targetLength)
    }

    /// Wraps the SF Symbol in a full-height template image. The nearly clear
    /// fill lets AppKit's tracking highlight cover the entire hit target while
    /// remaining invisible when the item is idle.
    private static func paddedTemplateImage(_ symbol: NSImage?) -> NSImage {
        let iconSize = symbol?.size ?? .zero
        let imageSize = NSSize(
            width: preferredLength(forIconWidth: iconSize.width),
            height: max(NSStatusBar.system.thickness, iconSize.height)
        )
        let image = NSImage(size: imageSize, flipped: false) { _ in
            NSColor.white.withAlphaComponent(0.01).setFill()
            NSRect(origin: .zero, size: imageSize).fill()
            if let symbol {
                let iconRect = NSRect(
                    x: (imageSize.width - iconSize.width) / 2,
                    y: (imageSize.height - iconSize.height) / 2,
                    width: iconSize.width,
                    height: iconSize.height
                )
                symbol.draw(in: iconRect)
            }
            return true
        }
        image.isTemplate = true
        return image
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
        let enabled = AppCoordinator.shared?.settings.settings.overlayEnabled ?? true
        let toggle = NSMenuItem(title: enabled ? "暂停菜单栏显示" : "启用菜单栏显示",
                               action: #selector(toggleOverlay), keyEquivalent: "")
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
