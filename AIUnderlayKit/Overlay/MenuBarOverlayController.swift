import AppKit

/// Owns one band window per display and drives the renderer. At P0 it only
/// renders a static debug band; the real gauge renderer arrives in P1.
@MainActor
public final class MenuBarOverlayController {
    private var windows: [String: MenuBarBandWindow] = [:]
    private var hostViews: [String: NSView] = [:]

    public init() {}

    /// Debug band: a dark track plus a brand-colored fill, spanning the top of
    /// the primary display. Used to verify level, click-through and geometry.
    public func showStaticBand() {
        guard let screen = NSScreen.main else { return }
        let displayID = Self.displayID(for: screen)
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        showBand(on: screen, displayID: displayID, height: height)
    }

    private func showBand(on screen: NSScreen, displayID: String, height: CGFloat) {
        let window = windows[displayID] ?? {
            let created = MenuBarBandWindow()
            windows[displayID] = created
            return created
        }()

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - height,
            width: screen.frame.width,
            height: height
        )
        window.setFrame(frame, display: false)

        let host = hostViews[displayID] ?? {
            let view = NSView(frame: .zero)
            view.wantsLayer = true
            window.contentView = view
            hostViews[displayID] = view
            return view
        }()
        host.frame = NSRect(origin: .zero, size: frame.size)
        renderStaticBand(in: host, size: frame.size)

        window.orderFrontRegardless()
    }

    private func renderStaticBand(in host: NSView, size: CGSize) {
        host.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }

        let track = CALayer()
        track.frame = CGRect(origin: .zero, size: size)
        track.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.38)
        host.layer?.addSublayer(track)

        let fill = CALayer()
        fill.frame = CGRect(x: 0, y: 0, width: size.width * 0.6, height: size.height)
        fill.backgroundColor = CGColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 0.95)
        host.layer?.addSublayer(fill)
    }

    /// Removes every band window (used on teardown and screen changes).
    public func hideAll() {
        for (_, window) in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        hostViews.removeAll()
    }

    /// Stable per-display key. Falls back to the frame when no display ID is
    /// available (e.g. headless test environments).
    static func displayID(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return "\(screen.frame.origin.x),\(screen.frame.origin.y)"
    }
}
