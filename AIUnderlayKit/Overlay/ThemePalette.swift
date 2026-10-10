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

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

/// A provider's palette. The provider fixes the hue family; the window tier
/// (outer/middle/inner) selects the lightness within it.
public struct ProviderPalette: Codable, Sendable, Equatable {
    public var providerId: String
    /// Longest window.
    public var outer: RGBAColor
    /// Middle window.
    public var middle: RGBAColor
    /// Shortest window.
    public var inner: RGBAColor
    /// Backing groove. A dark translucent black reads on any wallpaper.
    public var track: RGBAColor
    /// Baseline marker.
    public var baseline: RGBAColor

    public init(
        providerId: String,
        outer: RGBAColor,
        middle: RGBAColor,
        inner: RGBAColor,
        track: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.38),
        baseline: RGBAColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.9)
    ) {
        self.providerId = providerId
        self.outer = outer
        self.middle = middle
        self.inner = inner
        self.track = track
        self.baseline = baseline
    }

    /// Color for a window tier counted from the outermost (0 = outermost).
    /// Beyond the third tier the inner color is reused.
    public func color(forTier tier: Int) -> RGBAColor {
        switch tier {
        case 0: return outer
        case 1: return middle
        default: return inner
        }
    }

    /// Codex: cool blue/violet family.
    public static let codex = ProviderPalette(
        providerId: "codex",
        outer: RGBAColor(red: 0.30, green: 0.40, blue: 0.85),
        middle: RGBAColor(red: 0.42, green: 0.52, blue: 0.95),
        inner: RGBAColor(red: 0.58, green: 0.68, blue: 1.00)
    )

    /// Claude Code: warm terracotta/orange family.
    public static let claude = ProviderPalette(
        providerId: "claude",
        outer: RGBAColor(red: 0.80, green: 0.42, blue: 0.25),
        middle: RGBAColor(red: 0.90, green: 0.55, blue: 0.34),
        inner: RGBAColor(red: 0.97, green: 0.68, blue: 0.48)
    )

    /// Neutral fallback for unknown providers.
    public static let neutral = ProviderPalette(
        providerId: "neutral",
        outer: RGBAColor(red: 0.55, green: 0.55, blue: 0.60),
        middle: RGBAColor(red: 0.65, green: 0.65, blue: 0.70),
        inner: RGBAColor(red: 0.78, green: 0.78, blue: 0.82)
    )

    public static func `for`(providerId: String) -> ProviderPalette {
        switch providerId.lowercased() {
        case "codex": return .codex
        case "claude", "claude-code", "claudecode": return .claude
        default: return .neutral
        }
    }
}
