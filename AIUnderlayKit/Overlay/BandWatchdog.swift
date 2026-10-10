import AppKit
import CoreGraphics

/// Detects band windows the window server silently dropped. `NSWindow.isVisible`
/// keeps returning true after the system discards a desktop-level window, so we
/// ask the window server how many of *our* band windows are actually on screen
/// and re-assert only when the count is short — never on a match, which would
/// cause flicker.
public enum BandWatchdog {
    /// True when we manage at least one band but the window server reports fewer.
    public static func needsReassert(managedBands: Int, onScreenBands: Int) -> Bool {
        managedBands > 0 && onScreenBands < managedBands
    }

    /// Counts this process's on-screen windows at the band level.
    public static func onScreenBandCount() -> Int {
        let bandLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        let pid = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == pid
                && ($0[kCGWindowLayer as String] as? Int) == bandLevel
        }.count
    }
}
