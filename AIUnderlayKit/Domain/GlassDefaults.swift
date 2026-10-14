import Foundation

/// The built-in "Selected Glass V5" look: the exact parameters the user
/// selected in the browser material lab, translated to native targets.
///
/// These are the bottom of every resolution chain. A theme file only overrides
/// what it names; the settings UI only overrides what the user edits.
public enum GlassDefaults {
    /// Codex glass tint: the user's selected `#62AC96`.
    public static let codexAgentTheme = RGBAColor(red: 0x62 / 255, green: 0xAC / 255, blue: 0x96 / 255)
    /// Claude glass tint: the user's selected white. The renderer applies a
    /// legibility ceiling on top; the stored value stays exactly white.
    public static let claudeAgentTheme = RGBAColor(red: 1, green: 1, blue: 1)

    /// The memory of every definitely-used-up quota window: opaque black.
    public static let exhaustedTrack = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)

    public static let material = GlassMaterialParameters.selectedV5
    public static let attention = AttentionGeometry.selectedV5
    public static let signalLights = GlassSignalLights.selectedV5
    public static let baseline = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.9)

    public static func agentTheme(for providerId: String, fallback: RGBAColor) -> RGBAColor {
        switch providerId.lowercased() {
        case "codex": return codexAgentTheme
        case "claude", "claude-code", "claudecode": return claudeAgentTheme
        default: return fallback
        }
    }
}

/// Everything the visual engine needs to draw one provider lane, after theme,
/// settings and defaults have been merged. Pure data — no AppKit.
public struct ResolvedGlassTheme: Sendable, Equatable {
    public var providerId: String
    /// Quota tier colours + neutral bed + baseline from the palette chain.
    public var palette: ProviderPalette
    /// The glass tint. Affects refraction/tint only: never quotas, never
    /// signal lights.
    public var agentThemeColor: RGBAColor
    /// The four state lights. Global semantics, fixed priority.
    public var signalLights: GlassSignalLights
    /// The bed under a *known* quota: the used-up part is this colour.
    public var exhaustedTrack: RGBAColor
    /// The bed for unknown/unauthenticated lanes (never fake 0%).
    public var neutralTrack: RGBAColor
    public var baseline: RGBAColor
    public var showsBaseline: Bool
    public var material: GlassMaterialParameters
    public var attention: AttentionGeometry

    public init(
        providerId: String,
        palette: ProviderPalette,
        agentThemeColor: RGBAColor,
        signalLights: GlassSignalLights,
        exhaustedTrack: RGBAColor,
        neutralTrack: RGBAColor,
        baseline: RGBAColor,
        showsBaseline: Bool,
        material: GlassMaterialParameters,
        attention: AttentionGeometry
    ) {
        self.providerId = providerId
        self.palette = palette
        self.agentThemeColor = agentThemeColor
        self.signalLights = signalLights
        self.exhaustedTrack = exhaustedTrack
        self.neutralTrack = neutralTrack
        self.baseline = baseline
        self.showsBaseline = showsBaseline
        self.material = material
        self.attention = attention
    }

    /// The built-in look for a provider with no theme and no overrides.
    public static func `default`(providerId: String) -> ResolvedGlassTheme {
        let palette = ProviderPalette.for(providerId: providerId)
        return ResolvedGlassTheme(
            providerId: providerId,
            palette: palette,
            agentThemeColor: GlassDefaults.agentTheme(for: providerId, fallback: palette.inner),
            signalLights: GlassDefaults.signalLights,
            exhaustedTrack: GlassDefaults.exhaustedTrack,
            neutralTrack: palette.track,
            baseline: GlassDefaults.baseline,
            showsBaseline: true,
            material: GlassDefaults.material,
            attention: GlassDefaults.attention
        )
    }
}
