// Standalone probe: prints the real menu bar geometry as seen by the window
// server, plus NSScreen notch/visibleFrame data. Run with: swift Scripts/probe-menubar.swift
import AppKit
import CoreGraphics

let menuBarLevel = CGWindowLevelForKey(.mainMenuWindow)

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let menuBarBounds: [CGRect] = windows.compactMap { info in
    guard (info[kCGWindowLayer as String] as? Int) == Int(menuBarLevel),
          let dict = info[kCGWindowBounds as String] as? [String: Any],
          let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
    else { return nil }
    return rect
}

print("menuBarLevel = \(menuBarLevel)")
print("menu bar windows (window server, top-left origin):")
for b in menuBarBounds {
    print("  x=\(b.minX) y=\(b.minY) w=\(b.width) h=\(b.height)")
}

print("NSScreen.screens:")
for screen in NSScreen.screens {
    let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    let left = screen.auxiliaryTopLeftArea.map { "\($0)" } ?? "nil"
    let right = screen.auxiliaryTopRightArea.map { "\($0)" } ?? "nil"
    print("  id=\(num?.stringValue ?? "?") frame=\(screen.frame) visible=\(screen.visibleFrame)")
    print("    safeAreaTop=\(screen.safeAreaInsets.top) scale=\(screen.backingScaleFactor)")
    print("    auxTopLeft=\(left) auxTopRight=\(right)")
}
