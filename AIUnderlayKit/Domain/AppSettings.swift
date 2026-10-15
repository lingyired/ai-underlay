import Foundation

/// User-facing appearance and display settings. Non-secret; persisted as JSON.
///
/// There is exactly one agent visual engine (`Glass Spectrum`); the old
/// `RunningEffect` / `RunningEffectColor` choices are gone. Their legacy JSON
/// keys are still *read* by `init(from:)` so an old file migrates instead of
/// resetting (see `migrateLegacyVisualChoices`).
public struct AppSettings: Codable, Sendable, Equatable {
    public var layout: LayoutMode
    public var anchor: AnchorMode
    public var singleDirection: SingleBarDirection
    /// Master on/off for the overlay band.
    public var overlayEnabled: Bool
    /// Explicit proxy URL for CLI child processes, e.g. "http://127.0.0.1:10808".
    /// Empty means "use the macOS system proxy settings".
    public var proxyOverride: String
    public var showBaseline: Bool
    /// Master on/off for agent signalling (spectrum + attention ribbon).
    /// Quota glass always renders, even when this is off.
    public var showAgentEffects: Bool
    public var reduceMotion: Bool
    /// The user's baseline Glass Spectrum tempo, in cycles/second: the floor of
    /// the tokens/s curve, and (while no tokens/s source exists) the tempo the
    /// menu bar actually runs at. `nil` = the built-in `SpectrumRhythm` floor.
    public var motionFloorFrequencyHz: Double?
    /// How pronounced the ray wave is, 0.30…1.00. Visual only: output speed
    /// changes the rhythm, never the wave amplitude. `nil` = the built-in
    /// `SpectrumRhythm.motionIntensityDefault`.
    public var motionIntensity: Double?
    /// The two wide light fields that sweep across a *running* lane. The ray
    /// curtain keeps breathing either way; this is only the travelling sheen.
    public var showTravelingLight: Bool
    /// The narrow bright sweep inside the attention ribbon. The static alert
    /// (top line, ribbon, glow) stays visible either way.
    public var showAttentionSweep: Bool
    /// The user's own colour and material edits (settings-level overrides).
    public var appearance: GlassAppearance
    /// Id of the active theme, or nil for the built-in default look. Themes live
    /// outside the app bundle, so app updates never overwrite them.
    public var activeThemeId: String?
    /// Preview fixture key, or nil for live data.
    public var previewFixture: String?
    public var statusItemVisible: Bool
    /// Per-display configurations, keyed by stable display ID.
    public var displays: [DisplayConfiguration]
    /// Deprecated: the provider set is now fixed to `AIUnderlayKit.supportedProviders`.
    /// Kept only so older settings files still decode; it no longer affects
    /// what is shown.
    public var displayedProviders: [String]

    public init(
        layout: LayoutMode = .dual,
        anchor: AnchorMode = .outerEdge,
        singleDirection: SingleBarDirection = .leadingToTrailing,
        overlayEnabled: Bool = true,
        proxyOverride: String = "",
        showBaseline: Bool = true,
        showAgentEffects: Bool = true,
        reduceMotion: Bool = false,
        motionFloorFrequencyHz: Double? = nil,
        motionIntensity: Double? = nil,
        showTravelingLight: Bool = true,
        showAttentionSweep: Bool = true,
        appearance: GlassAppearance = .empty,
        activeThemeId: String? = nil,
        previewFixture: String? = nil,
        statusItemVisible: Bool = true,
        displays: [DisplayConfiguration] = [],
        displayedProviders: [String] = []
    ) {
        self.layout = layout
        self.anchor = anchor
        self.singleDirection = singleDirection
        self.overlayEnabled = overlayEnabled
        self.proxyOverride = proxyOverride
        self.showBaseline = showBaseline
        self.showAgentEffects = showAgentEffects
        self.reduceMotion = reduceMotion
        self.motionFloorFrequencyHz = motionFloorFrequencyHz
        self.motionIntensity = motionIntensity
        self.showTravelingLight = showTravelingLight
        self.showAttentionSweep = showAttentionSweep
        self.appearance = appearance
        self.activeThemeId = activeThemeId
        self.previewFixture = previewFixture
        self.statusItemVisible = statusItemVisible
        self.displays = displays
        self.displayedProviders = displayedProviders
    }

    public static let `default` = AppSettings()

    /// Every key we ever wrote, including removed ones, so decoding can route
    /// legacy values into the new model.
    private enum CodingKeys: String, CodingKey {
        case layout, anchor, singleDirection, overlayEnabled
        case proxyOverride, showBaseline, showAgentEffects, reduceMotion
        case motionFloorFrequencyHz
        case motionIntensity
        case showTravelingLight, showAttentionSweep
        case appearance, activeThemeId, previewFixture, statusItemVisible
        case displays, displayedProviders
        // Removed settings (read-only compatibility):
        case runningEffect
        case runningEffectColor
    }

    /// The pre-refactor animation choices, kept only to migrate old files.
    /// Decoded as a raw string: an unknown or removed value must never fail
    /// the whole settings file.
    enum LegacyRunningEffect: String {
        case breathing, sweep, dot, spectrum, spectrumGlow, none
    }

    enum LegacyRunningColor: String {
        case green, white, blue, orange, purple, theme

        /// Matches the old `RunningEffectColor.rgba` values, in hex.
        var hex: String? {
            switch self {
            case .green: return "#4DFF73"
            case .white: return "#FFFFFF"
            case .blue: return "#73CCFF"
            case .orange: return "#FFA64D"
            case .purple: return "#B38CFF"
            case .theme: return nil
            }
        }
    }

    /// Tolerant decoding: every field falls back to its default when absent, so
    /// an older settings file (or one written before a new key existed) still
    /// loads instead of resetting everything.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        layout = try c.decodeIfPresent(LayoutMode.self, forKey: .layout) ?? d.layout
        anchor = try c.decodeIfPresent(AnchorMode.self, forKey: .anchor) ?? d.anchor
        singleDirection = try c.decodeIfPresent(SingleBarDirection.self, forKey: .singleDirection) ?? d.singleDirection
        overlayEnabled = try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? d.overlayEnabled
        proxyOverride = try c.decodeIfPresent(String.self, forKey: .proxyOverride) ?? d.proxyOverride
        showBaseline = try c.decodeIfPresent(Bool.self, forKey: .showBaseline) ?? d.showBaseline
        showAgentEffects = try c.decodeIfPresent(Bool.self, forKey: .showAgentEffects) ?? d.showAgentEffects
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? d.reduceMotion
        motionFloorFrequencyHz = try? c.decodeIfPresent(Double.self, forKey: .motionFloorFrequencyHz)
        motionIntensity = try? c.decodeIfPresent(Double.self, forKey: .motionIntensity)
        showTravelingLight = try c.decodeIfPresent(Bool.self, forKey: .showTravelingLight) ?? d.showTravelingLight
        showAttentionSweep = try c.decodeIfPresent(Bool.self, forKey: .showAttentionSweep) ?? d.showAttentionSweep
        appearance = (try? c.decodeIfPresent(GlassAppearance.self, forKey: .appearance)) ?? d.appearance
        activeThemeId = try c.decodeIfPresent(String.self, forKey: .activeThemeId)
        previewFixture = try c.decodeIfPresent(String.self, forKey: .previewFixture)
        statusItemVisible = try c.decodeIfPresent(Bool.self, forKey: .statusItemVisible) ?? d.statusItemVisible
        displays = try c.decodeIfPresent([DisplayConfiguration].self, forKey: .displays) ?? d.displays
        displayedProviders = try c.decodeIfPresent([String].self, forKey: .displayedProviders) ?? d.displayedProviders

        migrateLegacyVisualChoices(from: c)
    }

    /// One-time, decode-time migration of the removed effect picks.
    ///
    /// - `runningEffect == .none` meant "I don't want the bar animating", so it
    ///   maps to `reduceMotion` — which keeps the static status colours and the
    ///   attention ribbon that the old `none` also left visible.
    /// - An explicit `runningEffectColor` becomes the user's running signal
    ///   light, preserving the colour they had chosen.
    /// - Any other effect value migrates to the single Glass Spectrum engine.
    private mutating func migrateLegacyVisualChoices(from c: KeyedDecodingContainer<CodingKeys>) {
        // Raw strings: a removed value can never throw here.
        let legacyEffect = try? c.decodeIfPresent(String.self, forKey: .runningEffect)
        if let raw = legacyEffect, let effect = LegacyRunningEffect(rawValue: raw), effect == .none {
            reduceMotion = true
        }
        let legacyColor = try? c.decodeIfPresent(String.self, forKey: .runningEffectColor)
        if let raw = legacyColor, let color = LegacyRunningColor(rawValue: raw), let hex = color.hex {
            if appearance.signalColors[SignalColorKey.running.rawValue] == nil {
                appearance.signalColors[SignalColorKey.running.rawValue] = hex
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layout, forKey: .layout)
        try c.encode(anchor, forKey: .anchor)
        try c.encode(singleDirection, forKey: .singleDirection)
        try c.encode(overlayEnabled, forKey: .overlayEnabled)
        try c.encode(proxyOverride, forKey: .proxyOverride)
        try c.encode(showBaseline, forKey: .showBaseline)
        try c.encode(showAgentEffects, forKey: .showAgentEffects)
        try c.encode(reduceMotion, forKey: .reduceMotion)
        try c.encodeIfPresent(motionFloorFrequencyHz, forKey: .motionFloorFrequencyHz)
        try c.encodeIfPresent(motionIntensity, forKey: .motionIntensity)
        try c.encode(showTravelingLight, forKey: .showTravelingLight)
        try c.encode(showAttentionSweep, forKey: .showAttentionSweep)
        try c.encode(appearance, forKey: .appearance)
        try c.encodeIfPresent(activeThemeId, forKey: .activeThemeId)
        try c.encodeIfPresent(previewFixture, forKey: .previewFixture)
        try c.encode(statusItemVisible, forKey: .statusItemVisible)
        try c.encode(displays, forKey: .displays)
        try c.encode(displayedProviders, forKey: .displayedProviders)
        // The removed keys are deliberately not re-written.
    }
}
