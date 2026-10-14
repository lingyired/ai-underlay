import AppKit
import SwiftUI

/// Bridges the pure `RGBAColor` domain type and SwiftUI's `Color` pickers.
extension RGBAColor {
    /// Converts a SwiftUI color into sRGB components. Colors that cannot be
    /// converted (pattern colors) fall back to the receiver's own value.
    init(_ color: Color, fallback: RGBAColor) {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else {
            self = fallback
            return
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }
}

extension Color {
    init(_ color: RGBAColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
