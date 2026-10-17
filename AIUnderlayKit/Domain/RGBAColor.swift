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
        guard let hsv = hsv else {
            // Already grey (or black): saturation has nothing to lift.
            return RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
        }
        let saturation = min(1, hsv.saturation * factor)
        // Value is held at 1 so the lifted colour never darkens.
        let rgb = Self.rgb(hue: hsv.hue, saturation: saturation, value: 1)
        return RGBAColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
    }

    /// The same colour with its hue turned by `amount` (0…1 is the full
    /// circle), keeping its own saturation and brightness.
    ///
    /// Used to give the two sides of a one-provider dual-window split two
    /// related but clearly different colours. A colour with no chroma has no
    /// hue to turn and comes back unchanged, so a grey theme stays grey.
    public func rotatedHue(by amount: Double) -> RGBAColor {
        guard let hsv else { return self }
        var hue = (hsv.hue + amount).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        let rgb = Self.rgb(hue: hue, saturation: hsv.saturation, value: hsv.value)
        return RGBAColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
    }

    /// Hue (0…1), saturation and value, or nil when the colour carries no
    /// hue at all. Every conversion between HSV and sRGB goes through here so
    /// the two cannot drift apart.
    private var hsv: (hue: Double, saturation: Double, value: Double)? {
        let highest = max(red, green, blue)
        let lowest = min(red, green, blue)
        let chroma = highest - lowest
        guard highest > 0, chroma > 0.0001 else { return nil }
        var hue: Double
        if highest == red {
            hue = ((green - blue) / chroma).truncatingRemainder(dividingBy: 6) / 6
        } else if highest == green {
            hue = (((blue - red) / chroma) + 2) / 6
        } else {
            hue = (((red - green) / chroma) + 4) / 6
        }
        if hue < 0 { hue += 1 }
        return (hue, chroma / highest, highest)
    }

    private static func rgb(hue: Double, saturation: Double, value: Double) -> (Double, Double, Double) {
        let sector = hue * 6
        let index = Int(floor(sector)) % 6
        let fraction = sector - floor(sector)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * fraction)
        let t = value * (1 - saturation * (1 - fraction))
        switch index {
        case 0: return (value, t, p)
        case 1: return (q, value, p)
        case 2: return (p, value, t)
        case 3: return (p, q, value)
        case 4: return (t, p, value)
        default: return (value, p, q)
        }
    }
}
