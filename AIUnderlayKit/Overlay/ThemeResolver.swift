import CoreGraphics
import Foundation

/// Turns a theme document (v1 or v2) plus the user's appearance overrides into
/// the single `ResolvedGlassTheme` the renderers consume.
///
/// Every field is optional; a theme only overrides what it names, so an
/// unchanged theme file can never silently blank out a provider. Which state
/// wins — Error > Waiting > Unread — is a code constant in `AttentionKind`,
/// never a file field.
///
/// Precedence, everywhere: **user appearance > theme file > built-in V5**.
public enum ThemeResolver {
    /// Full-size alpha used when a v1 track colour is given without an opacity.
    public static let defaultTrackAlpha: Double = 0.38
    public static let defaultBaselineAlpha: Double = 0.9

    // MARK: - Palette (quota tiers)

    /// The quota palette for a provider: base V5 palette → v2 single base
    /// colour → v1/v2 explicit layers → user's own base colour → the split
    /// side's own base colour.
    ///
    /// `splitRole` is only set while one provider is split across both lanes;
    /// it re-derives the tier ladder from that side's base so the two sides of
    /// the split cannot look alike. Every other layout passes nil and keeps the
    /// provider's single colour.
    public static func palette(
        theme: ThemeDocument?,
        providerId: String,
        base: ProviderPalette,
        appearance: GlassAppearance = .empty,
        splitRole: SplitLaneRole? = nil
    ) -> ProviderPalette {
        var palette = base

        if let baseHex = theme?.providers?[providerId]?.quotaBaseColor.flatMap({ ThemeColor(hex: $0) }) {
            palette = ProviderPalette.derived(providerId: providerId, base: RGBAColor(baseHex))
        }
        if let layers = theme?.providers?[providerId]?.quotaLayers, !layers.isEmpty {
            let colors = layers.compactMap { ThemeColor(hex: $0).map { RGBAColor($0) } }
            if !colors.isEmpty {
                palette.outer = colors[0]
                palette.middle = colors.count > 1 ? colors[1] : colors[0]
                palette.inner = colors.count > 2 ? colors[2] : palette.middle
            }
        }
        // The user's own quota colour is the strongest signal, and it always
        // re-derives the whole ladder so the tiers stay visibly distinct.
        if let userBase = appearance.quotaBaseColors[providerId].flatMap({ RGBAColor(hex: $0) }) {
            palette = ProviderPalette.derived(providerId: providerId, base: userBase)
        }
        // The split's own colour is more specific than the provider's, so it
        // comes last: it reuses whatever the chain above resolved as this
        // provider's full-brightness colour, then only moves the hue for the
        // side that carries the 5-hour window. The track and the baseline are
        // not the provider's colour and stay exactly as the theme set them.
        if let splitRole {
            let splitBase = SplitLaneColors.baseColor(
                role: splitRole,
                providerBase: palette.inner,
                overrides: appearance.splitQuotaBaseColors
            )
            let tiers = QuotaTierPalette.derive(base: splitBase, count: 3)
            palette.outer = tiers[0]
            palette.middle = tiers[1]
            palette.inner = tiers[2]
        }
        if let track = theme?.global?.trackColor.flatMap({ ThemeColor(hex: $0) }) {
            palette.track = RGBAColor(track, alpha: theme?.global?.trackOpacity ?? defaultTrackAlpha)
        }
        if let baseline = theme?.global?.baselineColor.flatMap({ ThemeColor(hex: $0) }) {
            palette.baseline = RGBAColor(baseline, alpha: theme?.global?.baselineOpacity ?? defaultBaselineAlpha)
        }
        return palette
    }

    // MARK: - Full glass theme

    public static func glassTheme(
        theme: ThemeDocument?,
        providerId: String,
        base: ProviderPalette,
        appearance: GlassAppearance = .empty,
        splitRole: SplitLaneRole? = nil
    ) -> ResolvedGlassTheme {
        let palette = palette(
            theme: theme,
            providerId: providerId,
            base: base,
            appearance: appearance,
            splitRole: splitRole
        )

        let agentThemeColor =
            appearance.agentThemeColors[providerId].flatMap { RGBAColor(hex: $0) }
            ?? theme?.providers?[providerId]?.agentThemeColor.flatMap { ThemeColor(hex: $0) }.map { RGBAColor($0) }
            ?? GlassDefaults.agentTheme(for: providerId, fallback: palette.inner)

        let signalLights = resolveSignalLights(theme: theme, appearance: appearance)

        let exhaustedTrack: RGBAColor
        if let userHex = appearance.exhaustedTrackColor, let color = RGBAColor(hex: userHex) {
            exhaustedTrack = color
        } else if let themeHex = theme?.global?.exhaustedTrackColor, let color = ThemeColor(hex: themeHex) {
            exhaustedTrack = RGBAColor(color, alpha: theme?.global?.exhaustedTrackOpacity ?? color.alpha)
        } else {
            exhaustedTrack = GlassDefaults.exhaustedTrack
        }

        let material = GlassMaterialOverrides.resolve(
            base: GlassDefaults.material,
            theme: theme?.material?.overrides,
            user: appearance.material
        )
        let attention = resolveAttention(theme?.attention)

        return ResolvedGlassTheme(
            providerId: providerId,
            palette: palette,
            agentThemeColor: agentThemeColor,
            signalLights: signalLights,
            exhaustedTrack: exhaustedTrack,
            neutralTrack: palette.track,
            baseline: palette.baseline,
            showsBaseline: theme?.global?.baselineEnabled ?? true,
            material: material,
            attention: attention
        )
    }

    // MARK: - Signals

    /// The four signal lights, resolved in the documented order:
    /// user override → v2 `signals` → v1 `states`/`spectrumColor` legacy
    /// mapping → V5 defaults.
    static func resolveSignalLights(theme: ThemeDocument?, appearance: GlassAppearance) -> GlassSignalLights {
        let legacy = legacySignalLights(from: theme)
        func light(_ key: SignalColorKey, _ fallback: RGBAColor) -> RGBAColor {
            if let userHex = appearance.signalColors[key.rawValue], let color = RGBAColor(hex: userHex) {
                return color
            }
            if let themeHex = signalStyle(theme, key)?.lightColor,
               let color = ThemeColor(hex: themeHex) {
                return RGBAColor(color)
            }
            return fallback
        }
        return GlassSignalLights(
            running: light(.running, legacy.running ?? GlassDefaults.signalLights.running),
            error: light(.error, legacy.error ?? GlassDefaults.signalLights.error),
            waiting: light(.waiting, legacy.waiting ?? GlassDefaults.signalLights.waiting),
            unread: light(.unread, legacy.unread ?? GlassDefaults.signalLights.unread)
        )
    }

    private static func signalStyle(_ theme: ThemeDocument?, _ key: SignalColorKey) -> ThemeDocument.SignalStyle? {
        switch key {
        case .running: return theme?.signals?.running
        case .error: return theme?.signals?.error
        case .waiting: return theme?.signals?.waiting
        case .unread: return theme?.signals?.unread
        }
    }

    /// Legacy v1 mapping, defined so old files keep expressing what they meant:
    ///
    /// - `states.waiting` / `states.error` collapse to one light each, taking
    ///   the border colour first (the old ribbon colour), then the spectrum
    ///   colour, then the overlay.
    /// - `providers.*.spectrumColor` becomes the running light **only when the
    ///   file is unambiguous**: exactly one provider names one colour. Two
    ///   different provider colours must not be merged into a global state
    ///   semantic, so the ambiguity falls back to the V5 running light.
    static func legacySignalLights(from theme: ThemeDocument?) -> (running: RGBAColor?, error: RGBAColor?, waiting: RGBAColor?, unread: RGBAColor?) {
        guard let theme else { return (nil, nil, nil, nil) }

        func stateColor(_ name: String) -> RGBAColor? {
            guard let style = theme.states?[name] else { return nil }
            // The light *is* the old ribbon/border colour; the overlay's own
            // opacity belongs to the overlay wash, not to the signal light.
            if let hex = style.borderColor, let color = ThemeColor(hex: hex) {
                return RGBAColor(color)
            }
            if let hex = style.spectrumColor, let color = ThemeColor(hex: hex) {
                return RGBAColor(color)
            }
            if let hex = style.overlayColor, let color = ThemeColor(hex: hex) {
                return RGBAColor(color, alpha: style.overlayOpacity ?? color.alpha)
            }
            return nil
        }

        let spectrumColors = Set((theme.providers ?? [:]).values.compactMap { $0.spectrumColor })
        let running: RGBAColor?
        if spectrumColors.count == 1,
           let hex = spectrumColors.first,
           let color = ThemeColor(hex: hex) {
            running = RGBAColor(color)
        } else {
            running = nil
        }

        return (running, stateColor("error"), stateColor("waiting"), nil)
    }

    // MARK: - Attention geometry

    static func resolveAttention(_ attention: ThemeDocument.Attention?) -> AttentionGeometry {
        let base = AttentionGeometry.selectedV5
        guard let attention else { return base }
        return AttentionGeometry(
            topLineHeight: attention.topLineHeight ?? base.topLineHeight,
            bottomRibbonHeight: attention.bottomRibbonHeight ?? base.bottomRibbonHeight,
            sweepSecondsError: attention.sweepSecondsError ?? base.sweepSecondsError,
            sweepSecondsWaiting: attention.sweepSecondsWaiting ?? base.sweepSecondsWaiting,
            sweepSecondsUnread: attention.sweepSecondsUnread ?? base.sweepSecondsUnread
        ).clamped
    }
}

public extension RGBAColor {
    /// A theme color, with an explicit alpha when the theme supplies one.
    init(_ color: ThemeColor, alpha: Double? = nil) {
        self.init(red: color.red, green: color.green, blue: color.blue,
                  alpha: alpha ?? color.alpha)
    }
}
