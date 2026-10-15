import Foundation

/// Which window the baseline marker is bound to, and the expected remaining
/// fraction to place it at.
public struct BaselineSpec: Sendable, Equatable {
    /// Index into the longest-first window array the renderer receives.
    public var selectedWindowIndex: Int
    public var expectedRemainingFraction: Double?

    public init(selectedWindowIndex: Int, expectedRemainingFraction: Double?) {
        self.selectedWindowIndex = selectedWindowIndex
        self.expectedRemainingFraction = expectedRemainingFraction
    }
}

/// One provider's content, everything except where it is drawn. The coordinator
/// builds this; the overlay controller pairs it with real screen geometry.
public struct LaneContent: Sendable, Equatable {
    public var providerId: String
    /// Longest window first (outermost first). No known window = an empty lane
    /// that shows the neutral glass groove.
    public var windows: [QuotaWindow]
    public var palette: ProviderPalette
    public var baseline: BaselineSpec?
    /// Colours + material + attention geometry, already resolved.
    public var glass: ResolvedGlassTheme
    /// What the agent is doing, or nil when effects are disabled. The quota
    /// glass renders either way.
    public var signal: ProviderVisualSignal?
    public var reduceMotion: Bool
    /// Baseline Glass Spectrum tempo in cycles/second: the floor of the
    /// tokens/s curve. The coordinator resolves it from the user's setting;
    /// the default keeps every other caller on the built-in floor.
    public var spectrumFloorHz: Double
    /// Whether the wide travelling light fields run across this lane.
    public var showsTravelingLight: Bool
    /// Whether the attention ribbon sweeps its bright band across this lane.
    public var showsAttentionSweep: Bool

    public init(
        providerId: String,
        windows: [QuotaWindow],
        palette: ProviderPalette,
        baseline: BaselineSpec? = nil,
        glass: ResolvedGlassTheme,
        signal: ProviderVisualSignal? = nil,
        reduceMotion: Bool = false,
        spectrumFloorHz: Double = SpectrumRhythm.floorFrequencyHz,
        showsTravelingLight: Bool = true,
        showsAttentionSweep: Bool = true
    ) {
        self.providerId = providerId
        self.windows = windows
        self.palette = palette
        self.baseline = baseline
        self.glass = glass
        self.signal = signal
        self.reduceMotion = reduceMotion
        self.spectrumFloorHz = spectrumFloorHz
        self.showsTravelingLight = showsTravelingLight
        self.showsAttentionSweep = showsAttentionSweep
    }

    /// A lane with no data: the neutral groove an offline provider shows.
    public static func empty(
        providerId: String,
        reduceMotion: Bool = false,
        spectrumFloorHz: Double = SpectrumRhythm.floorFrequencyHz,
        showsTravelingLight: Bool = true,
        showsAttentionSweep: Bool = true
    ) -> LaneContent {
        LaneContent(
            providerId: providerId,
            windows: [],
            palette: .neutral,
            baseline: nil,
            glass: .default(providerId: providerId),
            signal: nil,
            reduceMotion: reduceMotion,
            spectrumFloorHz: spectrumFloorHz,
            showsTravelingLight: showsTravelingLight,
            showsAttentionSweep: showsAttentionSweep
        )
    }

    public func spec(geometry: GaugeGeometry) -> LaneRenderSpec {
        LaneRenderSpec(
            providerId: providerId,
            geometry: geometry,
            windows: windows,
            palette: palette,
            baseline: baseline,
            glass: glass,
            signal: signal,
            reduceMotion: reduceMotion,
            spectrumFloorHz: spectrumFloorHz,
            showsTravelingLight: showsTravelingLight,
            showsAttentionSweep: showsAttentionSweep
        )
    }
}

/// Everything needed to draw one provider lane at one concrete geometry. This
/// is the *only* input the glass renderers accept: no effect enums, no data
/// sources, no windows.
public struct LaneRenderSpec: Sendable, Equatable {
    public var providerId: String
    public var geometry: GaugeGeometry
    public var windows: [QuotaWindow]
    public var palette: ProviderPalette
    public var baseline: BaselineSpec?
    public var glass: ResolvedGlassTheme
    public var signal: ProviderVisualSignal?
    public var reduceMotion: Bool
    public var spectrumFloorHz: Double
    public var showsTravelingLight: Bool
    public var showsAttentionSweep: Bool

    public init(
        providerId: String,
        geometry: GaugeGeometry,
        windows: [QuotaWindow],
        palette: ProviderPalette,
        baseline: BaselineSpec? = nil,
        glass: ResolvedGlassTheme,
        signal: ProviderVisualSignal? = nil,
        reduceMotion: Bool = false,
        spectrumFloorHz: Double = SpectrumRhythm.floorFrequencyHz,
        showsTravelingLight: Bool = true,
        showsAttentionSweep: Bool = true
    ) {
        self.providerId = providerId
        self.geometry = geometry
        self.windows = windows
        self.palette = palette
        self.baseline = baseline
        self.glass = glass
        self.signal = signal
        self.reduceMotion = reduceMotion
        self.spectrumFloorHz = spectrumFloorHz
        self.showsTravelingLight = showsTravelingLight
        self.showsAttentionSweep = showsAttentionSweep
    }
}

/// A full description of what the overlay should show right now.
public struct OverlayPresentation: Sendable {
    public var config: DisplayConfiguration
    public var left: LaneContent?
    public var right: LaneContent?

    public init(config: DisplayConfiguration, left: LaneContent?, right: LaneContent?) {
        self.config = config
        self.left = left
        self.right = right
    }
}
