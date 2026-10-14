import CoreGraphics

/// The deterministic brightness ladder for nested quota tiers.
///
/// A theme may name one base colour; the tiers then derive from it with fixed
/// factors so the outer (longest) window is visibly darker than the inner
/// ones. This is a pure function, pinned by tests — it never changes a length.
public enum QuotaTierPalette {
    /// Brightness factors, outermost → innermost, for a given tier count.
    /// One tier renders at full brightness; with more tiers the outermost
    /// drops to 0.52 and the innermost stays 1.0.
    public static func factors(count: Int) -> [Double] {
        guard count > 1 else { return Array(repeating: 1, count: max(count, 0)) }
        return (0..<count).map { index in
            0.52 + 0.48 * (Double(index) / Double(count - 1))
        }
    }

    /// Tier colours for a base colour, outermost → innermost.
    public static func derive(base: RGBAColor, count: Int) -> [RGBAColor] {
        factors(count: count).map { base.scaled(by: $0) }
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
    /// Neutral bed for a lane with no known data. A dark translucent black
    /// reads on any wallpaper; it is never used to fake a 0% quota.
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

    /// The exact colours a lane with `count` known windows should draw,
    /// outermost → innermost. With two windows this is the V5 look: a dim
    /// outer fill and a fully bright inner fill.
    public func tierColors(forWindowCount count: Int) -> [RGBAColor] {
        guard count > 0 else { return [] }
        switch count {
        case 1: return [inner]
        case 2: return [outer, inner]
        default: return (0..<count).map { color(forTier: $0) }
        }
    }

    /// Builds a palette from the V5 base colours: the quotas' tier ladder is
    /// derived deterministically, never hand-tuned per provider.
    public static func derived(providerId: String, base: RGBAColor) -> ProviderPalette {
        let tiers = QuotaTierPalette.derive(base: base, count: 3)
        return ProviderPalette(providerId: providerId, outer: tiers[0], middle: tiers[1], inner: tiers[2])
    }

    /// Codex: the V5 ice-blue base (`#69BFFF`).
    public static let codex = ProviderPalette.derived(
        providerId: "codex",
        base: RGBAColor(red: 0x69 / 255, green: 0xBF / 255, blue: 0xFF / 255)
    )

    /// Claude Code: the V5 soft-copper base (`#FFB08A`).
    public static let claude = ProviderPalette.derived(
        providerId: "claude",
        base: RGBAColor(red: 0xFF / 255, green: 0xB0 / 255, blue: 0x8A / 255)
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
