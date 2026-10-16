import CoreGraphics

/// An sRGB color with alpha, Codable so palettes persist with settings.
public struct RGBAColor: Codable, Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses the same forms a theme file accepts: `#RRGGBB`, `RRGGBB`,
    /// `#RGB`, `#RRGGBBAA`. Returns nil for anything else, so a typo in a
    /// settings override is ignored instead of rendering black.
    public init?(hex: String) {
        guard let parsed = ThemeColor(hex: hex) else { return nil }
        self.init(red: parsed.red, green: parsed.green, blue: parsed.blue, alpha: parsed.alpha)
    }

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Same colour at a different alpha.
    public func withAlpha(_ alpha: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: min(max(alpha, 0), 1))
    }

    /// Multiplies the colour channels by `factor`, clamping each to 0…1.
    /// Alpha is preserved. Used for deterministic quota-tier brightness.
    public func scaled(by factor: Double) -> RGBAColor {
        func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
        return RGBAColor(red: clamp(red * factor), green: clamp(green * factor), blue: clamp(blue * factor),
                         alpha: alpha)
    }

    /// sRGB luminance (0…1), used only for legibility safety rails.
    public var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// `#RRGGBB` (alpha dropped) for storage in settings.
    public var hexString: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// The same hue at full value, with its saturation raised.
    ///
    /// V5's lab paints the translucent alert wash and the ribbon's glow with a
    /// hand-picked `--tint` that is deliberately *more saturated* than the
    /// alert colour itself: a pale colour at 0.24 alpha sinks into the glass
    /// and reads as grey film, while a saturated one still reads as light.
    /// This is the generic fallback for a user-supplied signal colour; the
    /// shipped palette uses V5's exact values (`GlassSignalLights.tint(for:)`).
    public func saturationLifted(by factor: Double = 1.6) -> RGBAColor {
        let highest = max(red, green, blue)
        let lowest = min(red, green, blue)
        let chroma = highest - lowest
        guard highest > 0, chroma > 0.0001 else {
            // Already grey (or black): saturation has nothing to lift.
            return RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        let saturation = min(1, chroma / highest * factor)
        var hue: Double
        if highest == red {
            hue = ((green - blue) / chroma).truncatingRemainder(dividingBy: 6) / 6
        } else if highest == green {
            hue = (((blue - red) / chroma) + 2) / 6
        } else {
            hue = (((red - green) / chroma) + 4) / 6
        }
        if hue < 0 { hue += 1 }

        // HSV -> RGB, holding value at 1 so the lifted colour never darkens.
        let sector = hue * 6
        let index = Int(floor(sector)) % 6
        let fraction = sector - floor(sector)
        let p = 1 - saturation
        let q = 1 - saturation * fraction
        let t = 1 - saturation * (1 - fraction)
        let rgb: (Double, Double, Double)
        switch index {
        case 0: rgb = (1, t, p)
        case 1: rgb = (q, 1, p)
        case 2: rgb = (p, 1, t)
        case 3: rgb = (p, q, 1)
        case 4: rgb = (t, p, 1)
        default: rgb = (1, p, q)
        }
        return RGBAColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
    }
}
