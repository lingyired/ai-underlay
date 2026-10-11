import Foundation

/// User-facing appearance and display settings. Non-secret; persisted as JSON.
public struct AppSettings: Codable, Sendable, Equatable {
    public var layout: LayoutMode
    public var anchor: AnchorMode
    public var singleDirection: SingleBarDirection
    /// Master on/off for the overlay band.
    public var overlayEnabled: Bool
    public var showBaseline: Bool
    public var showAgentEffects: Bool
    public var reduceMotion: Bool
    /// Preview fixture key, or nil for live data.
    public var previewFixture: String?
    public var statusItemVisible: Bool
    /// Per-display configurations, keyed by stable display ID.
    public var displays: [DisplayConfiguration]

    public init(
        layout: LayoutMode = .dual,
        anchor: AnchorMode = .outerEdge,
        singleDirection: SingleBarDirection = .leadingToTrailing,
        overlayEnabled: Bool = true,
        showBaseline: Bool = true,
        showAgentEffects: Bool = true,
        reduceMotion: Bool = false,
        previewFixture: String? = nil,
        statusItemVisible: Bool = true,
        displays: [DisplayConfiguration] = []
    ) {
        self.layout = layout
        self.anchor = anchor
        self.singleDirection = singleDirection
        self.overlayEnabled = overlayEnabled
        self.showBaseline = showBaseline
        self.showAgentEffects = showAgentEffects
        self.reduceMotion = reduceMotion
        self.previewFixture = previewFixture
        self.statusItemVisible = statusItemVisible
        self.displays = displays
    }

    public static let `default` = AppSettings()
}
