import AppKit

/// A borderless, click-through window that sits one level above the desktop
/// icons and below the menu bar, so the system keeps drawing menu bar icons
/// and text on top of us and we never intercept menu bar clicks.
///
/// Level is always derived from the system constant (never hardcoded) so a
/// future OS change to the desktop-icon level cannot silently break us.
@MainActor
public final class MenuBarBandWindow: NSWindow {
    /// Raw window level used for every band window. Exposed for tests.
    public static var bandLevelRawValue: Int {
        Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    }

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Self.bandLevelRawValue)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    /// The window is a passive canvas; it must never become key or main.
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
