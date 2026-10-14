import XCTest
import AppKit
@testable import AIUnderlayKit

/// The quota glass: real black used-up bed, honest nested lengths, and a glass
/// tint that can never cover what is already spent.
@MainActor
final class GlassQuotaRendererTests: XCTestCase {
    private let geometry = GaugeGeometry(
        trackRect: CGRect(x: 0, y: 0, width: 1000, height: 30),
        fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
        growsTowardRight: true
    )

    private func window(_ id: String, remaining: Double?, availability: DataAvailability = .valid) -> QuotaWindow {
        QuotaWindow(
            id: id, label: id, kind: .custom, durationSeconds: id == "w" ? 604800 : 18000,
            remainingFraction: remaining, resetAt: nil, expectedRemainingFraction: nil,
            updatedAt: nil, availability: availability
        )
    }

    private func spec(
        windows: [QuotaWindow],
        palette: ProviderPalette = .codex,
        glass: ResolvedGlassTheme = .default(providerId: "codex"),
        baseline: BaselineSpec? = nil,
        reduceMotion: Bool = false
    ) -> LaneRenderSpec {
        LaneRenderSpec(
            providerId: "codex", geometry: geometry, windows: windows, palette: palette,
            baseline: baseline, glass: glass, signal: nil, reduceMotion: reduceMotion
        )
    }

    private func fillFrames(_ lane: CALayer) -> [CGRect] {
        let fills = lane.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "fills" }
        return (fills?.sublayers ?? []).map(\.frame)
    }

    // MARK: - Nested geometry (the V5 numbers)

    func test_v5CodexQuota_82and55_nestsTo451() {
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.82),
                                                            window("s", remaining: 0.55)]))
        let fills = fillFrames(lane)
        XCTAssertEqual(fills.count, 2)
        XCTAssertEqual(fills[0].width, 820, accuracy: 0.001)
        XCTAssertEqual(fills[1].width, 820 * 0.55, accuracy: 0.001)
        XCTAssertTrue(fills[0].contains(fills[1]), "outer fill must contain the inner one")
    }

    func test_v5ClaudeQuota_67and36_nestsTo2412() {
        let lane = GlassQuotaRenderer.render(spec(
            windows: [window("w", remaining: 0.67), window("s", remaining: 0.36)],
            palette: .claude,
            glass: .default(providerId: "claude")
        ))
        let fills = fillFrames(lane)
        XCTAssertEqual(fills[0].width, 670, accuracy: 0.001)
        XCTAssertEqual(fills[1].width, 670 * 0.36, accuracy: 0.001)
    }

    func test_leftwardLane_mirrorsTheFill() {
        let mirrored = GaugeGeometry(
            trackRect: CGRect(x: 0, y: 0, width: 1000, height: 30),
            fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
            growsTowardRight: false
        )
        let spec = LaneRenderSpec(
            providerId: "codex", geometry: mirrored,
            windows: [window("w", remaining: 0.5)], palette: .codex,
            glass: .default(providerId: "codex")
        )
        let fills = fillFrames(GlassQuotaRenderer.render(spec))
        XCTAssertEqual(fills[0].width, 500, accuracy: 0.001)
        XCTAssertEqual(fills[0].maxX, 1000, accuracy: 0.001, "a leftward lane grows from the right edge")
    }

    // MARK: - Black used-up bed

    func test_knownQuota_drawsAnOpaqueBlackUsedUpBed() {
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.4)]))
        let bed = lane.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "bed" } as? CAGradientLayer
        XCTAssertNotNil(bed)
        // Unflipped layer coordinates: the first stop is the top edge (0.78),
        // and the last stop is the bottom, where the bed is deepest (0.98).
        let stops = (bed?.colors as? [CGColor]) ?? []
        XCTAssertEqual(stops.first?.alpha ?? 0, 0.78, accuracy: 0.01, "the V5 bed eases lighter at the top")
        XCTAssertEqual(stops.last?.alpha ?? 0, 0.98, accuracy: 0.01, "and is deepest at the bottom")
        let components = stops.last?.components ?? []
        XCTAssertEqual(components[0], 0, accuracy: 0.001, "used-up quota is genuinely black")
        XCTAssertEqual(components[1], 0, accuracy: 0.001)
        XCTAssertEqual(components[2], 0, accuracy: 0.001)
    }

    func test_allZero_stillDrawsTheBlackBedAndNoFillLength() {
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0)]))
        XCTAssertEqual(fillFrames(lane).first?.width, 0)
        let bed = lane.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "bed" } as? CAGradientLayer
        XCTAssertNotNil(bed, "a known 0% is drawn as exhausted black")
    }

    func test_unknownQuota_drawsTheNeutralBedNeverBlackExhaustion() {
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: nil, availability: .unavailable)]))
        let glass = lane.sublayers?.first { $0.name == "quotaGlass" }
        let bed = glass?.sublayers?.first { $0.name == "bed" } as? CAGradientLayer
        let bottom = (bed?.colors as? [CGColor])?.last
        XCTAssertEqual(bottom?.alpha ?? 1, 0.38, accuracy: 0.02, "unknown is a translucent groove, not black 0%")
        XCTAssertTrue(fillFrames(lane).isEmpty, "unknown draws no fill at all")
        XCTAssertEqual(glass?.sublayers?.first { $0.name == "tint" }?.isHidden, true)
    }

    func test_missingOuterWindowBreaksTheChain() {
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: nil, availability: .unavailable),
                                                            window("s", remaining: 0.5)]))
        XCTAssertTrue(fillFrames(lane).isEmpty, "an inner window is never drawn without its outer length")
    }

    func test_staleQuota_rendersDimmedWithTheBedStillPresent() {
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.7, availability: .stale)]))
        let fill = lane.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "fills" }?.sublayers?.first
        XCTAssertEqual(fill?.opacity ?? 1, 0.62, accuracy: 0.01)
    }

    // MARK: - Tier ladder

    func test_twoWindows_useDimOuterAndFullInnerTier() {
        let palette = ProviderPalette.codex
        let tiers = palette.tierColors(forWindowCount: 2)
        XCTAssertEqual(tiers[1], palette.inner, "the innermost tier is the full base colour")
        XCTAssertLessThan(tiers[0].luminance, tiers[1].luminance)
    }

    func test_tierFactors_areVisiblySeparatedAndDeterministic() {
        let factors = QuotaTierPalette.factors(count: 3)
        XCTAssertEqual(factors.first ?? 0, 0.52, accuracy: 0.0001)
        XCTAssertEqual(factors.last ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(factors[1] - factors[0], 0.2)
        XCTAssertEqual(QuotaTierPalette.factors(count: 2), [0.52, 1.0])
        XCTAssertEqual(QuotaTierPalette.factors(count: 1), [1.0])
    }

    func test_fillGradient_hasABrightTopAndDarkerBase() {
        let layer = CAGradientLayer()
        GlassQuotaRenderer.applyFillGradient(layer, color: ProviderPalette.codex.inner, rank: 1, isInnermost: true)
        let colors = layer.colors as? [CGColor] ?? []
        XCTAssertEqual(colors.count, 4)
        let topAlpha = colors[0].alpha
        XCTAssertGreaterThan(topAlpha, 0.2, "the inner tier gets a visible white bevel")
    }

    // MARK: - End caps

    func test_innermostFill_getsTheWhiteEndCapAtItsFarEnd() {
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.8),
                                                            window("s", remaining: 0.5)]))
        let caps = lane.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "caps" }?.sublayers ?? []
        XCTAssertEqual(caps.count, 2)
        let inner = caps.last
        XCTAssertEqual(inner?.frame.maxX ?? .nan, CGFloat(400), accuracy: 0.01, "the cap sits at the real nested length")
        let components = inner?.backgroundColor?.components ?? []
        XCTAssertEqual(components[0], 1, accuracy: 0.001)
        XCTAssertEqual(components[1], 1, accuracy: 0.001)
        XCTAssertEqual(components[2], 1, accuracy: 0.001)
    }

    func test_subVisibleNonZeroFill_isStillDiscoverable() {
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.0005)])) // 0.5pt
        let fill = fillFrames(lane).first
        XCTAssertEqual(fill?.width ?? 0, 0.5, accuracy: 0.001, "the true length is never inflated")
        let caps = lane.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "caps" }?.sublayers ?? []
        XCTAssertEqual(caps.count, 1, "a non-zero quota keeps a visible end cap")
    }

    // MARK: - Glass tint

    func test_tint_isClippedToTheOuterFillSoSpentQuotaStaysBlack() {
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.4)]))
        let tint = lane.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "tint" }
        let clip = tint?.sublayers?.first { $0.name == "tintClip" }
        XCTAssertEqual(clip?.frame.width ?? 0, 400, accuracy: 0.01)
    }

    func test_tint_hidesWhenQuotaIsUnknownOrZero() {
        let unknown = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: nil)]))
        let zero = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0)]))
        for lane in [unknown, zero] {
            let tint = lane.sublayers?.first { $0.name == "quotaGlass" }?
                .sublayers?.first { $0.name == "tint" }
            XCTAssertEqual(tint?.isHidden, true)
        }
    }

    func test_whiteAgentTint_isAttenuatedForLegibility() {
        let white = GlassQuotaRenderer.legibilityCeiling(for: RGBAColor(red: 1, green: 1, blue: 1))
        let green = GlassQuotaRenderer.legibilityCeiling(for: GlassDefaults.codexAgentTheme)
        XCTAssertLessThan(white, 0.65)
        XCTAssertEqual(green, 1, accuracy: 0.0001, "an ordinary tint keeps its full strength")
    }

    func test_ambientGlowZero_doesNotHideTheThemeTint() {
        var glass = ResolvedGlassTheme.default(providerId: "codex")
        glass.material.ambientGlow = 0
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.5)], glass: glass))
        let tint = lane.sublayers?.first { $0.name == "quotaGlass" }?.sublayers?.first { $0.name == "tint" }
        XCTAssertEqual(tint?.isHidden, false)
        let bloom = tint?.sublayers?.first { $0.name == "tintClip" }?
            .sublayers?.first { $0.name == "tintBloom" }
        XCTAssertGreaterThan(bloom?.opacity ?? 0, 0, "strength 1.0 keeps the glass tint visible at glow 0")
    }

    func test_quotaOpacity_scalesTheGlassGroupOnlyNotTheBaseline() {
        var glass = ResolvedGlassTheme.default(providerId: "codex")
        glass.material.quotaOpacity = 0.5
        let spec = spec(windows: [window("w", remaining: 0.8)],
                        glass: glass,
                        baseline: BaselineSpec(selectedWindowIndex: 0, expectedRemainingFraction: 0.5))
        let lane = GlassQuotaRenderer.render(spec)
        let quotaGlass = lane.sublayers?.first { $0.name == "quotaGlass" }
        let baseline = lane.sublayers?.first { $0.name == "baseline" }
        XCTAssertEqual(quotaGlass?.opacity ?? 1, 0.5, accuracy: 0.01)
        XCTAssertEqual(baseline?.isHidden, false)
    }

    // MARK: - Baseline

    func test_baseline_projectsWithTheOuterProduct() {
        let spec = spec(windows: [window("w", remaining: 0.8), window("s", remaining: 0.5)],
                        baseline: BaselineSpec(selectedWindowIndex: 1, expectedRemainingFraction: 0.75))
        let lane = GlassQuotaRenderer.render(spec)
        let marker = lane.sublayers?.first { $0.name == "baseline" }
        XCTAssertEqual(marker?.frame.midX ?? 0, 600, accuracy: 1.0, "1000 × 0.8 × 0.75")
    }

    func test_baselineIsHiddenWithoutASpecOrWhenTheThemeDisablesIt() {
        var glass = ResolvedGlassTheme.default(providerId: "codex")
        glass.showsBaseline = false
        let withSpec = GlassQuotaRenderer.render(spec(
            windows: [window("w", remaining: 0.8)], glass: glass,
            baseline: BaselineSpec(selectedWindowIndex: 0, expectedRemainingFraction: 0.5)
        ))
        XCTAssertEqual(withSpec.sublayers?.first { $0.name == "baseline" }?.isHidden, true)
        let withoutSpec = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.8)]))
        XCTAssertEqual(withoutSpec.sublayers?.first { $0.name == "baseline" }?.isHidden, true)
    }

    // MARK: - Display state derivation

    func test_displayState() {
        XCTAssertEqual(QuotaDisplayState.resolve(windows: []), .unknown)
        XCTAssertEqual(QuotaDisplayState.resolve(windows: [window("w", remaining: nil)]), .unknown)
        XCTAssertEqual(QuotaDisplayState.resolve(windows: [window("w", remaining: 0.5, availability: .unauthenticated)]), .unknown)
        XCTAssertEqual(QuotaDisplayState.resolve(windows: [window("w", remaining: 0.5)]), .valid)
        XCTAssertEqual(QuotaDisplayState.resolve(windows: [window("w", remaining: 0)]), .valid)
        XCTAssertEqual(QuotaDisplayState.resolve(windows: [window("w", remaining: 0.5),
                                                           window("s", remaining: 0.5, availability: .stale)]), .stale)
    }
}
