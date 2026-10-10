import AppKit
import CoreGraphics

/// Reads the real menu bar geometry from the window server.
///
/// Why the window server and not `NSScreen`: macOS only accounts for the menu
/// bar in the `visibleFrame` of the display that hosts it. On any other
/// display `visibleFrame`/`safeAreaInsets` report 0, so a band sized from them
/// comes out too short and leaks wallpaper. The menu bar is a real window at
/// `CGWindowLevelForKey(.mainMenuWindow)`; its bounds are public and need no
/// permission (only window *titles* require screen recording).
public enum MenuBarGeometry {
    /// Floor for a measured menu bar height, used only when a probe returns an
    /// implausibly small value. The real value on this machine is 30.
    public static let minimumMenuBarHeight: CGFloat = 24

    // MARK: - Window server probe (cached)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedBounds: [CGRect] = []
    nonisolated(unsafe) private static var cachedAt = Date.distantPast
    private static let cacheTTL: TimeInterval = 0.5

    /// On-screen menu bar window bounds, in Quartz (top-left origin) coordinates.
    /// Results are cached for 500ms because this is a round trip to the window
    /// server and is called from geometry code on every layout pass.
    public static func onScreenMenuBarBounds(now: Date = Date()) -> [CGRect] {
        lock.lock()
        defer { lock.unlock() }
        if now.timeIntervalSince(cachedAt) < cacheTTL {
            return cachedBounds
        }
        let level = Int(CGWindowLevelForKey(.mainMenuWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let bounds: [CGRect] = windows.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == level,
                  let dict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { return nil }
            return rect
        }
        cachedBounds = bounds
        cachedAt = now
        return bounds
    }

    /// Clears the cache. Tests call this to avoid cross-test bleed.
    public static func resetCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedBounds = []
        cachedAt = .distantPast
    }

    // MARK: - Pure geometry (unit-tested without a display)

    /// Converts an AppKit display frame (bottom-left origin) into the Quartz
    /// frame (top-left origin) the window server reports, flipping Y around the
    /// primary display's top edge.
    public static func quartzFrame(for displayFrame: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(
            x: displayFrame.minX,
            y: primaryMaxY - displayFrame.maxY,
            width: displayFrame.width,
            height: displayFrame.height
        )
    }

    /// Picks the menu bar height for the display whose Quartz frame matches a
    /// menu bar window by X origin and width. Returns nil when nothing matches
    /// (caller falls back), and floors implausible values to `minimumMenuBarHeight`.
    public static func menuBarHeight(
        forQuartzFrame quartz: CGRect,
        menuBarWindowBounds: [CGRect]
    ) -> CGFloat? {
        let matching = menuBarWindowBounds.filter {
            abs($0.minX - quartz.minX) < 1 && abs($0.width - quartz.width) < 1
        }
        guard let height = matching.map(\.height).max(), height > 0 else { return nil }
        return max(height, minimumMenuBarHeight)
    }

    /// The notch gap edges for a screen, or nil when the screen has no notch
    /// (or the auxiliary areas overlap, which means no real gap).
    public static func notchEdges(for screen: NSScreen) -> (left: CGFloat, right: CGFloat)? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX
        else { return nil }
        return (left.maxX, right.minX)
    }
}
