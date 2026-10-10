import AppKit

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

/// Renders a quota gauge into a `CALayer` tree. This is the ONLY renderer:
/// the settings preview must drive this same type, never a parallel drawing
/// path. It consumes domain types only — it has no knowledge of CodexBar.
public protocol GaugeRendering {
    func render(
        windows: [QuotaWindow],
        geometry: GaugeGeometry,
        palette: ProviderPalette,
        baseline: BaselineSpec?
    ) -> CALayer
}

/// Concrete renderer. Windows are supplied longest-first (outermost first);
/// inner fills are drawn after outer fills so they sit on top.
public struct GaugeLayerRenderer: GaugeRendering {
    /// Below this many points a fill is visually invisible; we still draw the
    /// true (tiny) fill and add a separate end-cap so a non-zero window is not
    /// mistaken for zero, without inflating the fill's real length.
    public static let minimumVisibleLength: CGFloat = 1

    public init() {}

    public func render(
        windows: [QuotaWindow],
        geometry: GaugeGeometry,
        palette: ProviderPalette,
        baseline: BaselineSpec?
    ) -> CALayer {
        let container = CALayer()
        container.frame = geometry.trackRect
        container.masksToBounds = true

        let track = makeTrackLayer(geometry: geometry, palette: palette)
        container.addSublayer(track)

        let fractions = windows.map { $0.remainingFraction }
        let lengths = NestedGauge.nestedLengths(trackWidth: geometry.fillBounds.width, remaining: fractions)

        for (index, window) in windows.enumerated() {
            let length = lengths[index]
            guard !length.isNaN else { continue }  // broken chain: draw nothing for this window
            let fill = makeFillLayer(
                length: length,
                geometry: geometry,
                color: palette.color(forTier: index).cgColor
            )
            container.addSublayer(fill)
        }

        if let baseline, let marker = makeBaselineLayer(baseline: baseline, windows: windows, geometry: geometry, palette: palette) {
            container.addSublayer(marker)
        }

        return container
    }

    // MARK: - Layer builders

    private func makeTrackLayer(geometry: GaugeGeometry, palette: ProviderPalette) -> CALayer {
        let layer = CALayer()
        layer.frame = geometry.trackRect
        layer.backgroundColor = palette.track.cgColor
        layer.cornerRadius = geometry.fullBleed ? 0 : geometry.trackRect.height / 2
        layer.borderWidth = geometry.fullBleed ? 0 : 1
        return layer
    }

    private func makeFillLayer(length: CGFloat, geometry: GaugeGeometry, color: CGColor) -> CALayer {
        let rect = geometry.fillRect(forLength: length)
        let layer = CALayer()
        layer.frame = rect
        layer.backgroundColor = color
        layer.cornerRadius = geometry.fullBleed ? 0 : min(rect.height, rect.width) / 2

        // Sub-visible but non-zero: attach an end-cap so it is discoverable
        // without changing the fill's true length.
        if length > 0 && length < Self.minimumVisibleLength {
            let cap = CALayer()
            cap.frame = CGRect(x: 0, y: 0, width: Self.minimumVisibleLength, height: rect.height)
            cap.backgroundColor = color
            layer.addSublayer(cap)
        }
        return layer
    }

    private func makeBaselineLayer(
        baseline: BaselineSpec,
        windows: [QuotaWindow],
        geometry: GaugeGeometry,
        palette: ProviderPalette
    ) -> CALayer? {
        guard baseline.selectedWindowIndex >= 0, baseline.selectedWindowIndex < windows.count else { return nil }
        let outer = Array(windows[0..<baseline.selectedWindowIndex]).map { $0.remainingFraction }
        guard let length = QuotaPace.markerLength(
            trackWidth: geometry.fillBounds.width,
            outerRemaining: outer,
            selectedExpectedRemaining: baseline.expectedRemainingFraction
        ) else { return nil }

        let width: CGFloat = 2
        let x = geometry.growsTowardRight
            ? geometry.fillBounds.minX + length - width / 2
            : geometry.fillBounds.maxX - length - width / 2
        let layer = CALayer()
        layer.frame = CGRect(x: x, y: geometry.fillBounds.minY, width: width, height: geometry.fillBounds.height)
        layer.backgroundColor = palette.baseline.cgColor
        return layer
    }
}
