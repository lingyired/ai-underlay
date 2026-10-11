import CoreGraphics

/// Pure geometry for the menu-bar panel, kept separate so display clamping can
/// be tested without opening a window.
public enum PanelGeometry {
    public static let topGap: CGFloat = 4
    public static let screenMargin: CGFloat = 8
    public static let minimumHeight: CGFloat = 160

    /// Top-left anchor below the status button, clamped to the screen.
    public static func clampedTopLeft(below buttonRect: CGRect, width: CGFloat, visibleFrame: CGRect?) -> CGPoint {
        var x = buttonRect.minX
        if let visibleFrame {
            x = min(max(x, visibleFrame.minX + screenMargin),
                    visibleFrame.maxX - width - screenMargin)
        }
        return CGPoint(x: x, y: buttonRect.minY - topGap)
    }

    /// How tall the panel may be before it runs off the screen bottom.
    public static func maximumHeight(topLeft: CGPoint, visibleFrame: CGRect) -> CGFloat {
        let roomBelow = topLeft.y - visibleFrame.minY - screenMargin
        let aestheticCap = (visibleFrame.height * 0.85).rounded(.down)
        return max(1, min(roomBelow, aestheticCap))
    }

    public static func clampedHeight(_ raw: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(raw, minimumHeight), maximum)
    }

    /// AppKit rect (bottom-left origin) for a panel of the given size hanging
    /// below `topLeft`.
    public static func frame(topLeft: CGPoint, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height)
    }
}