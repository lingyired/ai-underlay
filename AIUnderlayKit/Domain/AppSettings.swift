import Foundation

/// How the "agent running" state is animated on the menu bar.
public enum RunningEffect: String, Codable, Sendable, CaseIterable {
    /// The whole fill gently brightens and dims (breathing light).
    case breathing
    /// A soft highlight band sweeps along the fill direction.
    case sweep
    /// A small pulsing dot at the fill's anchor.
    case dot
    /// No animation.
    case none
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
    /// Explicit proxy URL for CLI child processes, e.g. "http://127.0.0.1:10808".
    /// Empty means "use the macOS system proxy settings".
    public var proxyOverride: String
    public var showBaseline: Bool
    public var showAgentEffects: Bool
    public var reduceMotion: Bool
    /// Preview fixture key, or nil for live data.
    public var previewFixture: String?
    public var statusItemVisible: Bool
    /// Per-display configurations, keyed by stable display ID.
    public var displays: [DisplayConfiguration]
    /// Providers shown in the overlay and dashboard, in order.
    public var displayedProviders: [String]

    public init(
        layout: LayoutMode = .dual,
        anchor: AnchorMode = .outerEdge,
        singleDirection: SingleBarDirection = .leadingToTrailing,
        overlayEnabled: Bool = true,
        runningEffect: RunningEffect = .breathing,
        proxyOverride: String = "",
        showBaseline: Bool = true,
        showAgentEffects: Bool = true,
        reduceMotion: Bool = false,
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
        self.proxyOverride = proxyOverride
        self.showBaseline = showBaseline
        self.showAgentEffects = showAgentEffects
        self.reduceMotion = reduceMotion
        self.previewFixture = previewFixture
        self.statusItemVisible = statusItemVisible
        self.displays = displays
        self.displayedProviders = displayedProviders
    }

    public static let `default` = AppSettings()

    /// Tolerant decoding: every field falls back to its default when absent, so
    /// an older settings file (or one written before a new key existed) still
    /// loads instead of resetting everything. An absent/empty
    /// `displayedProviders` means "follow the upstream provider list".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        layout = try c.decodeIfPresent(LayoutMode.self, forKey: .layout) ?? d.layout
        anchor = try c.decodeIfPresent(AnchorMode.self, forKey: .anchor) ?? d.anchor
        singleDirection = try c.decodeIfPresent(SingleBarDirection.self, forKey: .singleDirection) ?? d.singleDirection
        overlayEnabled = try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? d.overlayEnabled
        runningEffect = try c.decodeIfPresent(RunningEffect.self, forKey: .runningEffect) ?? d.runningEffect
        proxyOverride = try c.decodeIfPresent(String.self, forKey: .proxyOverride) ?? d.proxyOverride
        showBaseline = try c.decodeIfPresent(Bool.self, forKey: .showBaseline) ?? d.showBaseline
        showAgentEffects = try c.decodeIfPresent(Bool.self, forKey: .showAgentEffects) ?? d.showAgentEffects
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? d.reduceMotion
        previewFixture = try c.decodeIfPresent(String.self, forKey: .previewFixture)
        statusItemVisible = try c.decodeIfPresent(Bool.self, forKey: .statusItemVisible) ?? d.statusItemVisible
        displays = try c.decodeIfPresent([DisplayConfiguration].self, forKey: .displays) ?? d.displays
        displayedProviders = try c.decodeIfPresent([String].self, forKey: .displayedProviders) ?? d.displayedProviders
    }
}
