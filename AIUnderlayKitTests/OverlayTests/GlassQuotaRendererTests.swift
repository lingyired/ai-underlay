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
        reduceMotion: Bool = false,
        signal: ProviderVisualSignal? = nil
    ) -> LaneRenderSpec {
        LaneRenderSpec(
            providerId: "codex", geometry: geometry, windows: windows, palette: palette,
            baseline: baseline, glass: glass, signal: signal, reduceMotion: reduceMotion
        )
    }

    private func fillFrames(_ lane: CALayer) -> [CGRect] {
        let fills = lane.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "fills" }
        return (fills?.sublayers ?? []).map(\.frame)
    }

    private func tint(_ lane: CALayer) -> CALayer? {
        lane.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "tint" }
    }

    private func tintClip(_ lane: CALayer) -> CALayer? {
        tint(lane)?.sublayers?.first { $0.name == "tintClip" }
    }

    private func haloImage(of lane: CALayer) -> CGImage? {
        tintClip(lane)?.sublayers?.first { $0.name == "tintHalo" }?.contents.map { $0 as! CGImage }
    }

    // MARK: - Rendered-material rasterisation helpers

    private func alphaPlane(_ image: CGImage) -> [Double] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (0..<(width * height)).map { Double(pixels[$0 * 4 + 3]) / 255 }
    }

    /// Mean absolute alpha change between two same-size material textures.
    private func meanAlphaDifference(_ a: CGImage, _ b: CGImage) -> Double {
        let left = alphaPlane(a)
        let right = alphaPlane(b)
        guard !left.isEmpty, left.count == right.count else { return 0 }
        let total = zip(left, right).reduce(0.0) { $0 + abs($1.0 - $1.1) }
        return total / Double(left.count)
    }

    /// The first column (from the left) where the running alpha reaches 1% of
    /// the texture's total. Softening spreads the reflection outward, so this
    /// index moves left as the material gets softer.
    private func leftTailReach(_ image: CGImage) -> Int {
        let width = image.width
        let height = image.height
        let plane = alphaPlane(image)
        guard width > 0, height > 0, plane.count == width * height else { return width }
        var columns = [Double](repeating: 0, count: width)
        for y in 0..<height {
            for x in 0..<width {
                columns[x] += plane[y * width + x]
            }
        }
        let total = columns.reduce(0, +)
        guard total > 0 else { return width }
        let target = total * 0.01
        var running = 0.0
        for x in 0..<width {
            running += columns[x]
            if running >= target { return x }
        }
        return width
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

    func test_fillGradient_startsInTheQuotaColour_andFallsOffTowardTheBase() {
        let layer = CAGradientLayer()
        GlassQuotaRenderer.applyFillGradient(layer, color: ProviderPalette.codex.inner, rank: 1, isInnermost: true)
        let colors = layer.colors as? [CGColor] ?? []
        XCTAssertEqual(colors.count, 3)
        // Index 0 is the top edge (unflipped coordinates). It must be the quota
        // colour itself: a white stop there renders as an inner shadow.
        let top = colors[0]
        let channels = top.components ?? []
        let expected = ProviderPalette.codex.inner
        XCTAssertEqual(Double(channels[0]), expected.red, accuracy: 0.01)
        XCTAssertEqual(Double(channels[1]), expected.green, accuracy: 0.01)
        XCTAssertEqual(Double(channels[2]), expected.blue, accuracy: 0.01)
        XCTAssertGreaterThan(top.alpha, 0.6, "the top edge keeps a solid fill, not a wash")
        XCTAssertLessThan(colors[1].alpha, top.alpha, "the body eases off toward the base")
        XCTAssertLessThan(colors[2].alpha, colors[1].alpha)
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

    // MARK: - Rendered softness: the blur-radius token reaches the material

    func test_softnessToken_lengthensTheMaterialKernelInDevicePixels() {
        XCTAssertEqual(GlassMaterialRenderer.clampedSoftness(-4), 0)
        XCTAssertEqual(GlassMaterialRenderer.clampedSoftness(64), GlassMaterialRenderer.maxSoftnessPoints)
        XCTAssertEqual(GlassMaterialRenderer.kernelRadiusPixels(softnessPoints: 0, scale: 2), 0, accuracy: 0.0001)
        XCTAssertEqual(GlassMaterialRenderer.kernelRadiusPixels(softnessPoints: 17, scale: 2), 17, accuracy: 0.0001)
        XCTAssertEqual(GlassMaterialRenderer.kernelRadiusPixels(softnessPoints: 32, scale: 2), 32, accuracy: 0.0001)
        // The token is stored in points, so at 1x the same 17 softens half as far.
        XCTAssertEqual(GlassMaterialRenderer.kernelRadiusPixels(softnessPoints: 17, scale: 1), 8.5, accuracy: 0.0001)

        let crisp = GlassMaterialRenderer.edgeTransitionSpanPixels(softnessPoints: 0, scale: 2)
        let normal = GlassMaterialRenderer.edgeTransitionSpanPixels(softnessPoints: 17, scale: 2)
        let soft = GlassMaterialRenderer.edgeTransitionSpanPixels(softnessPoints: 32, scale: 2)
        XCTAssertLessThanOrEqual(crisp, 1, "0pt must stay a hard edge")
        XCTAssertGreaterThan(normal, crisp + 8, "17pt visibly widens the edge")
        XCTAssertGreaterThan(soft, normal + 8, "32pt widens it further")
    }

    func test_softnessToken_changesTheRenderedMaterialTexture() throws {
        GlassMaterialRenderer.resetCache()
        let tint = GlassDefaults.codexAgentTheme
        let size = CGSize(width: 240, height: 30)
        let crisp = try XCTUnwrap(GlassMaterialRenderer.haloImage(tint: tint, laneSize: size, scale: 2, softnessPoints: 0))
        let normal = try XCTUnwrap(GlassMaterialRenderer.haloImage(tint: tint, laneSize: size, scale: 2, softnessPoints: 17))
        let soft = try XCTUnwrap(GlassMaterialRenderer.haloImage(tint: tint, laneSize: size, scale: 2, softnessPoints: 32))

        XCTAssertFalse(crisp === normal)
        XCTAssertFalse(normal === soft)
        XCTAssertGreaterThan(meanAlphaDifference(crisp, normal), 0.005,
                             "17pt must actually repaint the material, not just the JSON")
        XCTAssertGreaterThan(meanAlphaDifference(crisp, soft), meanAlphaDifference(crisp, normal))
        XCTAssertLessThan(leftTailReach(soft), leftTailReach(crisp),
                          "a softer reflection reaches further out from the blob")
    }

    /// The parent review found the original key was built from the *capped*
    /// bitmap size, so two lanes wider than the cap would wrongly share a
    /// texture whose stretch — and therefore whose kernel — differ.
    func test_textureKey_keepsLanesThatShareTheCappedBitmapApart() {
        let tint = GlassDefaults.codexAgentTheme
        let narrow = GlassMaterialRenderer.textureKey(
            tint: tint, laneSize: CGSize(width: 320, height: 30), scale: 2, softnessPoints: 32)
        let wide = GlassMaterialRenderer.textureKey(
            tint: tint, laneSize: CGSize(width: 640, height: 30), scale: 2, softnessPoints: 32)
        XCTAssertEqual(narrow.pixelWidth, wide.pixelWidth, "both lanes cap to the same bitmap width")
        XCTAssertNotEqual(narrow, wide, "…but they must not share one cache entry")
        XCTAssertNotEqual(narrow.kernelRadiusX, wide.kernelRadiusX, accuracy: 0.0001)

        GlassMaterialRenderer.resetCache()
        _ = GlassMaterialRenderer.haloImage(tint: tint, laneSize: CGSize(width: 320, height: 30), scale: 2, softnessPoints: 32)
        _ = GlassMaterialRenderer.haloImage(tint: tint, laneSize: CGSize(width: 640, height: 30), scale: 2, softnessPoints: 32)
        XCTAssertEqual(GlassMaterialRenderer.textureGenerationCount, 2,
                       "the wider lane must not reuse the narrower lane's kernel")
        XCTAssertEqual(GlassMaterialRenderer.cacheEntryCount, 2)
    }

    func test_textureGeneration_readsBackTheQuantizedKeyValues() throws {
        GlassMaterialRenderer.resetCache()
        let tint = GlassDefaults.codexAgentTheme
        let size = CGSize(width: 320, height: 30)
        // 17.01 and 17.24 both quantize to the same 0.5pt step.
        let first = try XCTUnwrap(GlassMaterialRenderer.haloImage(tint: tint, laneSize: size, scale: 2, softnessPoints: 17.01))
        let second = try XCTUnwrap(GlassMaterialRenderer.haloImage(tint: tint, laneSize: size, scale: 2, softnessPoints: 17.24))
        XCTAssertTrue(first === second)
        XCTAssertEqual(GlassMaterialRenderer.textureGenerationCount, 1)

        // A real 0.5pt step is a new texture.
        let third = try XCTUnwrap(GlassMaterialRenderer.haloImage(tint: tint, laneSize: size, scale: 2, softnessPoints: 17.6))
        XCTAssertFalse(third === first)
        XCTAssertEqual(GlassMaterialRenderer.textureGenerationCount, 2)
    }

    func test_materialTexture_isCachedPerParametersOnly() {
        GlassMaterialRenderer.resetCache()
        let glass = ResolvedGlassTheme.default(providerId: "codex")

        _ = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.8)], glass: glass))
        let firstGeneration = GlassMaterialRenderer.textureGenerationCount
        XCTAssertEqual(firstGeneration, 1)
        XCTAssertEqual(GlassMaterialRenderer.cacheEntryCount, 1)
        XCTAssertGreaterThan(GlassMaterialRenderer.cacheByteCount, 0)
        // A new quota poll with identical material parameters reuses the bitmap.
        _ = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.35)], glass: glass))
        XCTAssertEqual(GlassMaterialRenderer.textureGenerationCount, firstGeneration,
                       "only a parameter change may regenerate the material")
        XCTAssertGreaterThan(GlassMaterialRenderer.cacheHitCount, 0)

        // A real parameter change does generate a new one.
        var softer = glass
        softer.material.blurRadiusTarget = 32
        _ = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.35)], glass: softer))
        XCTAssertEqual(GlassMaterialRenderer.textureGenerationCount, firstGeneration + 1)
        XCTAssertEqual(GlassMaterialRenderer.cacheEntryCount, 2)
        XCTAssertLessThanOrEqual(GlassMaterialRenderer.cacheEntryCount, GlassMaterialRenderer.maxCacheEntries)
        XCTAssertLessThanOrEqual(GlassMaterialRenderer.cacheByteCount, GlassMaterialRenderer.maxCacheBytes)
    }

    func test_materialCache_staysBoundedUnderManyDistinctParameters() {
        GlassMaterialRenderer.resetCache()
        let tint = GlassDefaults.codexAgentTheme
        for step in 0...40 {
            _ = GlassMaterialRenderer.haloImage(
                tint: tint,
                laneSize: CGSize(width: 320, height: 30),
                scale: 2,
                softnessPoints: Double(step)
            )
        }
        XCTAssertGreaterThan(GlassMaterialRenderer.textureGenerationCount, GlassMaterialRenderer.maxCacheEntries)
        XCTAssertLessThanOrEqual(GlassMaterialRenderer.cacheEntryCount, GlassMaterialRenderer.maxCacheEntries)
        XCTAssertLessThanOrEqual(GlassMaterialRenderer.cacheByteCount, GlassMaterialRenderer.maxCacheBytes)
    }

    func test_materialHalo_staysInsideTheRealOuterFillClip() throws {
        GlassMaterialRenderer.resetCache()
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.4)]))
        let clip = try XCTUnwrap(tintClip(lane))
        XCTAssertEqual(clip.frame.width, 400, accuracy: 0.01, "the halo is clipped to the real outer fill")
        XCTAssertTrue(clip.masksToBounds)
        let halo = try XCTUnwrap(clip.sublayers?.first { $0.name == "tintHalo" })
        XCTAssertGreaterThan(halo.opacity, 0)
        let image = try XCTUnwrap(halo.contents) as! CGImage
        XCTAssertLessThanOrEqual(image.width, GlassMaterialRenderer.maxTextureWidthPixels)
        XCTAssertLessThanOrEqual(image.height, GlassMaterialRenderer.maxTextureHeightPixels)
    }

    func test_softness_isIndependentOfAmbientGlowAndGrain() throws {
        GlassMaterialRenderer.resetCache()
        func renderedHalo(softness: Double) throws -> CGImage {
            var glass = ResolvedGlassTheme.default(providerId: "codex")
            glass.material.blurRadiusTarget = softness
            glass.material.ambientGlow = 0
            glass.material.grain = 0
            let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.5)], glass: glass))
            return try XCTUnwrap(haloImage(of: lane))
        }
        let crisp = try renderedHalo(softness: 0)
        let soft = try renderedHalo(softness: 32)
        XCTAssertFalse(crisp === soft)
        XCTAssertGreaterThan(meanAlphaDifference(crisp, soft), 0.005,
                             "softness must reach the material with glow and grain at 0")
    }

    func test_themeStrengthZero_hidesTheTintAndStopsItsAnimation() throws {
        var glass = ResolvedGlassTheme.default(providerId: "codex")
        glass.material.ambientGlow = 0.6
        let running = ProviderVisualSignal(isRunning: true)
        let lane = GlassQuotaRenderer.render(
            spec(windows: [window("w", remaining: 0.8)], glass: glass, signal: running))
        let ambient = try XCTUnwrap(tintClip(lane)?.sublayers?.first { $0.name == "tintAmbient" })
        XCTAssertNotNil(ambient.animation(forKey: "ambientDrift"))
        let generation = GlassMaterialRenderer.textureGenerationCount

        glass.material.agentThemeStrength = 0
        GlassQuotaRenderer.update(
            into: lane, spec: spec(windows: [window("w", remaining: 0.8)], glass: glass, signal: running))
        XCTAssertEqual(tint(lane)?.isHidden, true)
        XCTAssertNil(ambient.animation(forKey: "ambientDrift"),
                     "a hidden tint must not keep a continuous animation running")
        XCTAssertEqual(GlassMaterialRenderer.textureGenerationCount, generation,
                       "strength 0 rasterises no material")
    }

    // MARK: - Quota contrast (dark base, dim outer, bright inner)

    func test_outerTierFillIsVisiblyWeakerThanTheInnerTier() {
        let outer = CAGradientLayer()
        let inner = CAGradientLayer()
        GlassQuotaRenderer.applyFillGradient(outer, color: ProviderPalette.codex.outer, rank: 0, isInnermost: false)
        GlassQuotaRenderer.applyFillGradient(inner, color: ProviderPalette.codex.inner, rank: 1, isInnermost: true)
        let outerColors = outer.colors as? [CGColor] ?? []
        let innerColors = inner.colors as? [CGColor] ?? []
        XCTAssertEqual(outerColors.count, 3)
        XCTAssertEqual(innerColors.count, 3)
        XCTAssertLessThan(outerColors[0].alpha, innerColors[0].alpha - 0.2,
                          "the outer window must read as a darker glass tier")
        XCTAssertLessThan(outerColors[1].alpha, innerColors[1].alpha)
        XCTAssertLessThan(outerColors[2].alpha, innerColors[2].alpha)
    }

    func test_tintStaysALocalReflectionNotAUniformWash() throws {
        GlassMaterialRenderer.resetCache()
        let lane = GlassQuotaRenderer.render(spec(windows: [window("w", remaining: 0.8),
                                                           window("s", remaining: 0.5)]))
        let clip = try XCTUnwrap(tintClip(lane))
        let bloom = try XCTUnwrap(clip.sublayers?.first { $0.name == "tintBloom" })
        let linear = try XCTUnwrap(clip.sublayers?.first { $0.name == "tintLinear" })
        let halo = try XCTUnwrap(clip.sublayers?.first { $0.name == "tintHalo" })
        XCTAssertLessThanOrEqual(bloom.opacity, 0.25, "the radial bloom no longer floods the whole fill")
        XCTAssertLessThanOrEqual(linear.opacity, 0.32)
        XCTAssertGreaterThan(halo.opacity, bloom.opacity, "the local reflection carries the tint")
        XCTAssertNotNil(halo.contents)
    }
}
