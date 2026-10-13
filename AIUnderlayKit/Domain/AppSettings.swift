import Foundation

/// How the "agent running" state is animated on the menu bar.
public enum RunningEffect: String, Codable, Sendable, CaseIterable {
    /// The whole fill gently brightens and dims (breathing light).
    case breathing
    /// A soft highlight band sweeps along the fill direction.
    case sweep
    /// A small pulsing dot at the fill's anchor.
    case dot
    /// Equalizer-style bars rising from the menu bar's bottom edge; the rhythm
    /// follows the agent's output speed (see `SpectrumRhythm`).
    case spectrum
    /// No animation.
    case none
}

/// Color of the "agent running" animation.
public enum RunningEffectColor: String, Codable, Sendable, CaseIterable {
    case green
    case white
    case blue
    case orange
    case purple
    /// Follow the active theme's provider color. With no theme installed this
    /// resolves to the built-in running color, so nothing changes for anyone who
    /// never installs one.
    case theme

    public var rgba: (red: Double, green: Double, blue: Double) {
        switch self {
        case .green: return (0.30, 1.00, 0.45)
        case .white: return (1.00, 1.00, 1.00)
        case .blue: return (0.45, 0.80, 1.00)
        case .orange: return (1.00, 0.65, 0.30)
        case .purple: return (0.70, 0.55, 1.00)
        case .theme: return (0.30, 1.00, 0.45)
        }
    }

    /// Whether this choice names an explicit color. `theme` defers to the theme.
    public var isExplicit: Bool { self != .theme }
}

/// User-facing appearance and display settings. Non-secret; persisted as JSON.
public struct AppSettings: Codable, Sendable, Equatable {
    public var layout: LayoutMode
    public var anchor: AnchorMode
    public var singleDirection: SingleBarDirection
    /// Master on/off for the overlay band.
    public var overlayEnabled: Bool
    /// How the "agent running" state is animated on the bar.
    public var runningEffect: RunningEffect
    /// Color of the running animation.
    public var runningEffectColor: RunningEffectColor
    /// Explicit proxy URL for CLI child processes, e.g. "http://127.0.0.1:10808".
    /// Empty means "use the macOS system proxy settings".
    public var proxyOverride: String
    public var showBaseline: Bool
    public var showAgentEffects: Bool
    public var reduceMotion: Bool
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
        runningEffect: RunningEffect = .breathing,
        runningEffectColor: RunningEffectColor = .theme,
        proxyOverride: String = "",
        showBaseline: Bool = true,
        showAgentEffects: Bool = true,
        reduceMotion: Bool = false,
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
        self.runningEffect = runningEffect
        self.runningEffectColor = runningEffectColor
        self.proxyOverride = proxyOverride
        self.showBaseline = showBaseline
        self.showAgentEffects = showAgentEffects
        self.reduceMotion = reduceMotion
        self.activeThemeId = activeThemeId
        self.previewFixture = previewFixture
        self.statusItemVisible = statusItemVisible
        self.displays = displays
        self.displayedProviders = displayedProviders
    }

    public static let `default` = AppSettings()

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
        runningEffect = try c.decodeIfPresent(RunningEffect.self, forKey: .runningEffect) ?? d.runningEffect
        runningEffectColor = try c.decodeIfPresent(RunningEffectColor.self, forKey: .runningEffectColor) ?? d.runningEffectColor
        proxyOverride = try c.decodeIfPresent(String.self, forKey: .proxyOverride) ?? d.proxyOverride
        showBaseline = try c.decodeIfPresent(Bool.self, forKey: .showBaseline) ?? d.showBaseline
        showAgentEffects = try c.decodeIfPresent(Bool.self, forKey: .showAgentEffects) ?? d.showAgentEffects
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? d.reduceMotion
        activeThemeId = try c.decodeIfPresent(String.self, forKey: .activeThemeId)
        previewFixture = try c.decodeIfPresent(String.self, forKey: .previewFixture)
        statusItemVisible = try c.decodeIfPresent(Bool.self, forKey: .statusItemVisible) ?? d.statusItemVisible
        displays = try c.decodeIfPresent([DisplayConfiguration].self, forKey: .displays) ?? d.displays
        displayedProviders = try c.decodeIfPresent([String].self, forKey: .displayedProviders) ?? d.displayedProviders
    }
}
