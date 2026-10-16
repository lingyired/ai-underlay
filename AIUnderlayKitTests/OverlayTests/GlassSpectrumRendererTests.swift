import XCTest
import AppKit
@testable import AIUnderlayKit

/// Glass Spectrum contract: a real per-ray travelling wave (not a static
/// texture that scales), one animated layer per lane, quota-length clipping,
/// the attention colour priority and the two switch semantics.
@MainActor
final class GlassSpectrumRendererTests: XCTestCase {
    private let geometry = GaugeGeometry(
        trackRect: CGRect(x: 0, y: 0, width: 1000, height: 30),
        fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
        growsTowardRight: true
    )

    private func spec(
        windows: [QuotaWindow] = [QuotaWindow(id: "w", label: "w", kind: .weekly, durationSeconds: 604800,
                       remainingFraction: 0.82, resetAt: nil, expectedRemainingFraction: nil,
                       updatedAt: nil, availability: .valid)],
        glass: ResolvedGlassTheme = .default(providerId: "codex"),
        signal: ProviderVisualSignal?,
        reduceMotion: Bool = false,
        growsTowardRight: Bool = true,
        showsTravelingLight: Bool = true,
        waveIntensity: Double = SpectrumRhythm.motionIntensityDefault,
        trackWidth: CGFloat = 1000
    ) -> LaneRenderSpec {
        let geometry = GaugeGeometry(
            trackRect: CGRect(x: 0, y: 0, width: trackWidth, height: 30),
            fillBounds: CGRect(x: 0, y: 0, width: trackWidth, height: 30),
            growsTowardRight: growsTowardRight
        )
        return LaneRenderSpec(
            providerId: "codex", geometry: geometry, windows: windows, palette: .codex,
            glass: glass, signal: signal, reduceMotion: reduceMotion,
            waveIntensity: waveIntensity,
            showsTravelingLight: showsTravelingLight
        )
    }

    private func root(of lane: CALayer) -> CALayer? {
        lane.sublayers?.first { $0.name == "spectrum" }
    }

    private func curtain(in spectrum: CALayer) -> CALayer? {
        spectrum.sublayers?.first { $0.name == "curtain" }
    }

    private let cycle = SpectrumRhythm.cycleDuration(outputTPS: nil)

    // MARK: - Structure and lifecycle

    func test_running_drawsScrimAndOneAnimatedCurtainLayer() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        XCTAssertNotNil(lane.sublayers?.first { $0.name == "scrim" })
        let layer = try XCTUnwrap(curtain(in: spectrum))
        XCTAssertTrue((layer.sublayers ?? []).isEmpty, "the curtain is one animated layer, not a layer per ray")
        let animation = try XCTUnwrap(layer.animation(forKey: "curtainFrames") as? CAKeyframeAnimation)
        XCTAssertEqual(animation.keyPath, "contents")
        XCTAssertEqual(animation.calculationMode, .discrete)
        XCTAssertEqual(animation.repeatCount, .infinity)
        XCTAssertEqual(animation.duration, cycle, accuracy: 0.0001)
    }

    /// The scrim is V5's `.zone .sheen` bottom edge, not a film over the fill,
    /// and it stands *above* the screen-blended light group: inside the group
    /// the screen filter would composite the dark edge as light and neutralize
    /// it, leaving a sheen that renders nothing.
    ///
    /// A 0.45-alpha black scrim across the bottom 82% of the lane is what made
    /// the native glass read "灰蒙蒙" next to the lab: it cost the inner fill
    /// 38/255 of blue. The ceiling here keeps a future edit from silently
    /// re-introducing it, and the floor keeps the machined bottom edge that
    /// gives the rays something to stand on.
    func test_scrimIsAV5SheenEdge_notAFilmOverTheFill() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let scrim = try XCTUnwrap(
            lane.sublayers?.first { $0.name == "scrim" } as? CAGradientLayer
        )
        let names = (lane.sublayers ?? []).map { $0.name ?? "" }
        let spectrumIndex = try XCTUnwrap(names.firstIndex(of: "spectrum"))
        let scrimIndex = try XCTUnwrap(names.firstIndex(of: "scrim"))
        XCTAssertGreaterThan(
            scrimIndex, spectrumIndex,
            "the sheen must composite over the screened light, like V5's .sheen z-index 7"
        )
        let colors = try XCTUnwrap(scrim.colors as? [CGColor])
        XCTAssertEqual(colors.count, 2)
        XCTAssertEqual(Double(colors[0].alpha), 0, accuracy: 0.001,
                       "the scrim starts fully transparent")
        XCTAssertLessThanOrEqual(Double(colors[1].alpha), 0.16,
                                 "the scrim stays a bottom edge, never a film")
        XCTAssertGreaterThan(Double(colors[1].alpha), 0.05,
                             "the bottom edge keeps the machined sheen")
        let locations = try XCTUnwrap(scrim.locations?.map { $0.doubleValue })
        XCTAssertEqual(locations, [0.76, 1.0],
                       "V5's sheen only covers the last quarter of the lane")
        // V5's sheen is a dark blue-grey, not neutral black: on the Aurora scene
        // a pure black edge reads as a shadow instead of a machined rim.
        let edge = colors[1].components ?? []
        XCTAssertGreaterThanOrEqual(Double(edge[2]), Double(edge[0]),
                                    "the sheen stays in the fill's blue family")
    }

    func test_animatedLayerBudget_isSmall() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        var animated = 0
        var stack: [CALayer] = [spectrum]
        while let layer = stack.popLast() {
            if layer.animationKeys()?.isEmpty == false { animated += 1 }
            stack.append(contentsOf: layer.sublayers ?? [])
            if let mask = layer.mask { stack.append(mask) }
        }
        XCTAssertLessThanOrEqual(animated, GlassSpectrumRenderer.maxAnimatedLayers)
    }

    func test_rayCurtain_standsOnTheBottomEdge() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 320),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let frame = try XCTUnwrap(curtain(in: spectrum)?.contents) as! CGImage
        let rep = NSBitmapImageRep(cgImage: frame)
        let pixelWidth = rep.pixelsWide
        let pixelHeight = rep.pixelsHigh

        func alpha(nearCentre centre: Int, row: Int) -> CGFloat {
            ((-1)...1).compactMap { rep.colorAt(x: centre + $0, y: row)?.alphaComponent }.max() ?? 0
        }

        let density = ResolvedGlassTheme.default(providerId: "codex").material.rayDensity
        let rayCount = SpectrumWaveModel.rayCount(width: 320, density: density)
        // One in three rays: this test is about the curtain's baseline, not
        // the wave's stride, so it tolerates neighbours bleeding into a sample.
        let centres = stride(from: 0, to: rayCount, by: 3).map { index in
            Int(((Double(index) + 0.5) / Double(rayCount)) * Double(pixelWidth))
        }
        XCTAssertGreaterThan(centres.count, 20)

        let litAtBottom = centres.filter { alpha(nearCentre: $0, row: pixelHeight - 1) > 0.02 }
        XCTAssertEqual(litAtBottom.count, centres.count,
                       "every ray's base is flush with the bottom edge")

        let tips = centres.compactMap { centre in
            (0..<pixelHeight).first { alpha(nearCentre: centre, row: $0) > 0.02 }
        }
        XCTAssertEqual(tips.count, centres.count, "every ray is drawn")
        let spread = (tips.max() ?? 0) - (tips.min() ?? 0)
        XCTAssertGreaterThan(Double(spread), Double(pixelHeight) * 0.2,
                             "the wave lives in the tips, not in a flat block")
    }

    func test_repeatedIdenticalRender_doesNotRestartTheSequence() throws {
        let lane = CALayer()
        lane.frame = geometry.trackRect
        let renderSpec = spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 320)
        GlassSpectrumRenderer.update(into: lane, spec: renderSpec, running: true, cycle: cycle, restart: true)
        let layer = try XCTUnwrap(curtain(in: try XCTUnwrap(root(of: lane))))
        let production = try XCTUnwrap(layer.animation(forKey: "curtainFrames"))

        GlassSpectrumRenderer.update(into: lane, spec: renderSpec, running: true, cycle: cycle, restart: false)
        XCTAssertTrue(layer.animation(forKey: "curtainFrames") === production,
                      "a quota or theme poll must not restart the wave")
    }

    func test_notRunning_hidesTheCurtainAndStopsEverything() throws {
        let lane = CALayer()
        lane.frame = geometry.trackRect
        GlassSpectrumRenderer.update(
            into: lane, spec: spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        GlassSpectrumRenderer.update(
            into: lane, spec: spec(signal: ProviderVisualSignal(isRunning: false)),
            running: false, cycle: cycle, restart: true
        )
        XCTAssertTrue(spectrum.isHidden)
        XCTAssertNil(try XCTUnwrap(curtain(in: spectrum)).animation(forKey: "curtainFrames"))
    }

    func test_reduceMotion_drawsAStaticCurtain() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true), reduceMotion: true),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let layer = try XCTUnwrap(curtain(in: spectrum))
        XCTAssertNil(layer.animation(forKey: "curtainFrames"))
        XCTAssertNotNil(layer.contents, "Reduce Motion keeps a still frame of the wave")
        XCTAssertFalse(spectrum.isHidden)
    }

    // MARK: - The wave itself

    func test_perRayWave_movesWithThePhase_insteadOfScalingOneTexture() {
        func profile(at phase: Double, travels: Bool) -> [Double] {
            let center = SpectrumWaveModel.primaryCrestCenter(
                at: phase, travels: travels, travelsTowardRight: true
            )
            return SpectrumWaveModel.rays(width: 320, density: 1).map {
                SpectrumWaveModel.sample(
                    normalizedX: $0.normalizedX, rayIndex: $0.index,
                    phase: phase, primaryCenter: center,
                    intensity: SpectrumRhythm.motionIntensityDefault
                ).heightFraction
            }
        }
        for travels in [true, false] {
            let early = profile(at: 0, travels: travels)
            let late = profile(at: 0.5, travels: travels)
            // A per-ray wave: a handful of rays keep their height and most
            // change, so the shape moves instead of the whole block scaling.
            let unchanged = zip(early, late).filter { abs($0 - $1) < 0.01 }.count
            let changed = zip(early, late).filter { abs($0 - $1) > 0.08 }.count
            XCTAssertGreaterThan(changed, early.count / 4,
                                 "a travelling wave must move most rays (travels: \(travels))")
            XCTAssertGreaterThan(unchanged, 0,
                                 "rays must not move in lockstep (travels: \(travels))")
        }
    }

    func test_neighbouringRays_areNotInLockstep_atAStandingPhase() {
        // Independent of phase: the deterministic per-ray offsets alone must
        // break the "one group, one shape" look.
        let phase = 0.37
        let center = SpectrumWaveModel.primaryCrestCenter(at: phase, travels: false, travelsTowardRight: true)
        let heights = SpectrumWaveModel.rays(width: 320, density: 1).map {
            SpectrumWaveModel.sample(
                normalizedX: $0.normalizedX, rayIndex: $0.index, phase: phase,
                primaryCenter: center, intensity: SpectrumRhythm.motionIntensityDefault
            ).heightFraction
        }
        let neighbours = zip(heights, heights.dropFirst()).map { abs($0 - $1) }
        XCTAssertGreaterThan(neighbours.filter { $0 > 0.02 }.count, neighbours.count / 3,
                             "neighbouring rays must carry different heights at one instant")
    }

    func test_travelingDisabled_stillMovesTheWave() {
        let standsStill = SpectrumWaveModel.primaryCrestCenter(at: 0.25, travels: false, travelsTowardRight: true)
        XCTAssertEqual(standsStill, 0.5, "the parked crest sits on the lane centre")
        func shape(at phase: Double) -> [Double] {
            SpectrumWaveModel.rays(width: 320, density: 1).map {
                SpectrumWaveModel.sample(
                    normalizedX: $0.normalizedX, rayIndex: $0.index, phase: phase,
                    primaryCenter: standsStill, intensity: SpectrumRhythm.motionIntensityDefault
                ).heightFraction
            }
        }
        let early = shape(at: 0)
        let late = shape(at: 0.5)
        let moved = zip(early, late).filter { abs($0 - $1) > 0.05 }.count
        XCTAssertGreaterThan(moved, early.count / 3,
                             "with the traveller off, the ray wave itself must still be visible")
    }

    func test_crestTravelsAcrossTheLane_andWrapsWithoutAJump() {
        let start = SpectrumWaveModel.primaryCrestCenter(at: 0, travels: true, travelsTowardRight: true)
        let middle = SpectrumWaveModel.primaryCrestCenter(at: 0.5, travels: true, travelsTowardRight: true)
        let end = SpectrumWaveModel.primaryCrestCenter(at: 0.999, travels: true, travelsTowardRight: true)
        XCTAssertEqual(start, 0, accuracy: 0.001, "one lap per cycle starts at the leading edge")
        XCTAssertGreaterThan(end, 0.99, "the crest reaches the trailing edge")
        XCTAssertEqual(middle, 0.5, accuracy: 0.02)
        // The focus kernel measures distance *around* the lane, so the light
        // field is periodic: leaving one edge is the same picture as entering
        // it. The span is exactly one lap, which is what removes the seam, and
        // the wrap itself is continuous because phase 1 terminates at 0.
        let lapEnd = SpectrumWaveModel.primaryCrestCenter(at: 0.9999, travels: true, travelsTowardRight: true)
        XCTAssertEqual(lapEnd, 0.9999, accuracy: 0.001, "one lap per cycle, no off-lane lead")
        XCTAssertEqual(SpectrumWaveModel.primaryCrestCenter(at: 1, travels: true, travelsTowardRight: true),
                       start, accuracy: 0.001, "the lap closes exactly on the start")
        XCTAssertEqual(SpectrumWaveModel.travelLeadFraction, 0, accuracy: 0.0001)
    }

    func test_leftwardLane_mirrorsTheTravel() {
        // At t=0 the primary crest enters at the leading edge, at t=0.5 it is
        // exactly at the lane centre and at t=1 it has reached the trailing
        // edge — for both growth directions.
        for forward in [true, false] {
            let start = SpectrumWaveModel.primaryCrestCenter(at: 0.001, travels: true, travelsTowardRight: forward)
            let middle = SpectrumWaveModel.primaryCrestCenter(at: 0.5, travels: true, travelsTowardRight: forward)
            let end = SpectrumWaveModel.primaryCrestCenter(at: 0.999, travels: true, travelsTowardRight: forward)
            XCTAssertEqual(middle, 0.5, accuracy: 0.001, "forward: \(forward)")
            XCTAssertEqual(abs(start - middle), abs(end - middle), accuracy: 0.02,
                           "the crest sweeps symmetric distances on both sides")
            if forward {
                XCTAssertLessThan(start, middle, "a rightward lane starts behind the centre")
                XCTAssertGreaterThan(end, middle, "a rightward lane ends beyond the centre")
            } else {
                XCTAssertGreaterThan(start, middle, "a leftward lane starts past the centre")
                XCTAssertLessThan(end, middle, "a leftward lane ends before the centre")
            }
            XCTAssertEqual((end - start) > 0, forward,
                           "a rightward lane travels right; a leftward lane travels left")
        }
    }

    func test_crestKernel_isWideAndFadesSmoothly() {
        let centre = SpectrumWaveModel.focus(normalizedX: 0.5, crestCenter: 0.5)
        XCTAssertEqual(centre, 1, accuracy: 0.0001)
        let shoulder = SpectrumWaveModel.focus(normalizedX: 0.5, crestCenter: 0.5 + SpectrumWaveModel.focusSigmaFraction)
        XCTAssertEqual(shoulder, exp(-1), accuracy: 0.001)
        let far = SpectrumWaveModel.focus(normalizedX: 0.5, crestCenter: 0.9)
        XCTAssertLessThan(far, 0.02, "the light must not wash the whole lane")
    }

    /// V5 caps the crest radius at 205 pt (`radius = min(w·0.28, 205)`). The
    /// cap is what keeps the bright crest *local* on a wide single-bar lane:
    /// without it the kernel grows with the lane and the light spreads until
    /// there is no focus left.
    func test_crestRadius_isCappedAtV5sMaximum_onWideLanes() {
        XCTAssertEqual(SpectrumWaveModel.focusRadius(forWidth: 480), 134.4, accuracy: 0.01)
        XCTAssertEqual(SpectrumWaveModel.focusRadius(forWidth: 1000), 205, accuracy: 0.01,
                       "a wide lane must not spread its crest past V5's 205 pt cap")
        XCTAssertEqual(SpectrumWaveModel.focusRadius(forWidth: 4000), 205, accuracy: 0.01)

        // The capped kernel must still peak at the crest and fade at the lane
        // edges — a cap that flattened the kernel would be worse than none.
        let atCrest = SpectrumWaveModel.focus(normalizedX: 0.5, crestCenter: 0.5, width: 1000)
        XCTAssertEqual(atCrest, 1, accuracy: 0.0001)
        let quarterLaneAway = SpectrumWaveModel.focus(normalizedX: 0.75, crestCenter: 0.5, width: 1000)
        XCTAssertLessThan(quarterLaneAway, 0.05, "205 pt on a 1000 pt lane is still a local crest")
    }

    /// The lab's two waves drift across the lane at 0.61 and 0.68 lane-widths
    /// per cycle. Drift — turns divided by spatial frequency — is what the eye
    /// reads as wave speed, and the earlier `waveBTurnsPerLoop = 2` sent wave B
    /// at 1.67 lane-widths per cycle: 2.4× the lab, which is the "too fast"
    /// artefact this pass fixes. Both turns must stay integers so the cached
    /// frame sequence still closes without a seam.
    func test_waveDrift_matchesTheV5Lab_withoutBreakingTheLoop() {
        let driftA = SpectrumWaveModel.waveATurnsPerLoop / SpectrumWaveModel.waveASpatialCycles
        let driftB = SpectrumWaveModel.waveBTurnsPerLoop / SpectrumWaveModel.waveBSpatialCycles
        XCTAssertEqual(driftA, 0.49, accuracy: 0.02)
        XCTAssertEqual(driftB, 0.83, accuracy: 0.03)
        // V5's own relative drift is 0.61 + 0.68 = 1.29.
        XCTAssertEqual(driftA + driftB, 1.29, accuracy: 0.12,
                       "the combined wave speed is what the eye reads; it must stay near the lab")
        for turns in [SpectrumWaveModel.waveATurnsPerLoop, SpectrumWaveModel.waveBTurnsPerLoop] {
            XCTAssertEqual(turns, turns.rounded(), accuracy: 0.0001,
                           "a non-integer turn count would leave a seam in the frame loop")
        }
    }

    func test_intensity_scalesTheWaveNotTheBase() {
        let phase = 0.3
        let centre = SpectrumWaveModel.primaryCrestCenter(at: phase, travels: true, travelsTowardRight: true)
        let low = SpectrumWaveModel.sample(normalizedX: 0.2, rayIndex: 4, phase: phase,
                                           primaryCenter: centre, intensity: 0.30)
        let high = SpectrumWaveModel.sample(normalizedX: 0.2, rayIndex: 4, phase: phase,
                                           primaryCenter: centre, intensity: 1.0)
        XCTAssertGreaterThan(high.heightFraction, low.heightFraction)
        XCTAssertGreaterThan(high.alpha, low.alpha)
        XCTAssertGreaterThanOrEqual(low.alpha, SpectrumWaveModel.baseAlpha)
        XCTAssertLessThanOrEqual(high.alpha, SpectrumWaveModel.alphaCeiling,
                                 "even full strength must not wash the curtain to white")
        XCTAssertLessThanOrEqual(high.heightFraction, SpectrumWaveModel.tallestHeightFraction)
    }

    /// The base visibility is a fidelity contract, not a taste knob: V5's
    /// Aurora scene draws every ray at `0.22 + modulated`. An earlier revision
    /// trimmed it to `0.17` to work around composite faults, and the curtain
    /// then read as translucent grey next to the lab. Pinning the constant
    /// makes any future trim an explicit decision with its own lab evidence.
    func test_baseVisibility_matchesTheAuroraLab() {
        XCTAssertEqual(SpectrumWaveModel.baseAlpha, 0.22)
    }

    func test_heightStaysBounded_soTheWaveNeverInverts() {
        for index in 0..<64 {
            for phase in stride(from: 0.0, to: 1.0, by: 0.05) {
                let sample = SpectrumWaveModel.sample(
                    normalizedX: Double(index) / 64, rayIndex: index, phase: phase,
                    primaryCenter: phase, intensity: SpectrumRhythm.motionIntensityDefault
                )
                XCTAssertGreaterThanOrEqual(sample.heightFraction, SpectrumWaveModel.shortestHeightFraction)
                XCTAssertLessThanOrEqual(sample.heightFraction, SpectrumWaveModel.tallestHeightFraction)
                XCTAssertGreaterThan(sample.alpha, 0)
                XCTAssertLessThan(sample.alpha, 1)
            }
        }
    }

    func test_phaseLoopsSeamlessly() {
        // The wave is periodic over one turn, so the last frame of a sequence
        // joins the first without a jump.
        for rayIndex in 0..<12 {
            let start = SpectrumWaveModel.waveValue(normalizedX: Double(rayIndex) / 12, rayIndex: rayIndex, phase: 0)
            let end = SpectrumWaveModel.waveValue(normalizedX: Double(rayIndex) / 12, rayIndex: rayIndex, phase: 1)
            XCTAssertEqual(start, end, accuracy: 0.0001)
        }
    }

    // MARK: - Frames and caching

    func test_frameSequence_hasEnoughFrames_atTheReferenceCadence() {
        XCTAssertGreaterThanOrEqual(
            GlassSpectrumRenderer.framesPerCycle(width: 320, height: 30, scale: 2),
            GlassSpectrumRenderer.minimumFramesPerCycle
        )
        // A half-width, half-height lane can afford the full frame count.
        XCTAssertEqual(GlassSpectrumRenderer.framesPerCycle(width: 320, height: 30, scale: 2),
                       GlassSpectrumRenderer.maximumFramesPerCycle)
        let wide = GlassSpectrumRenderer.framesPerCycle(width: 2048, height: 30, scale: 2)
        XCTAssertGreaterThanOrEqual(wide, GlassSpectrumRenderer.minimumFramesPerCycle)
        XCTAssertLessThanOrEqual(wide, GlassSpectrumRenderer.nominalFramesPerCycle)
        let bytes = wide * GlassSpectrumRenderer.pixelByteCount(width: 2048, height: 30, scale: 2)
        XCTAssertLessThanOrEqual(bytes, GlassSpectrumRenderer.maxSequenceBytes)
    }

    func test_frameCount_roundsToTheStep_soSliderDragsRarelyRebuild() {
        // 0.5 -> 0.7 -> 0.9 Hz must all resolve to the same frame count, so a
        // slider drag does not rebuild the sequence at every in-between value.
        func frames(_ hz: Double) -> Int {
            GlassSpectrumRenderer.framesPerCycle(width: 320, height: 30, scale: 2, cycle: 1.0 / hz)
        }
        // A one-percent tempo nudge must not rebuild the sequence...
        XCTAssertEqual(frames(0.70), frames(0.71))
        // ...the count only moves in whole steps...
        for hz in [0.50, 0.70, 0.90, 1.10] {
            XCTAssertEqual(frames(hz) % GlassSpectrumRenderer.frameCountStep, 0)
            XCTAssertGreaterThanOrEqual(frames(hz), GlassSpectrumRenderer.minimumFramesPerCycle)
            XCTAssertLessThanOrEqual(frames(hz), GlassSpectrumRenderer.maximumFramesPerCycle)
        }
        // ...and a faster tempo never asks for more refreshes than a slower one.
        XCTAssertGreaterThanOrEqual(frames(0.50), frames(1.10))
    }

    func test_frameIndex_mapsThePhaseOntoTheSequence() {
        XCTAssertEqual(GlassSpectrumRenderer.frameIndex(forPhase: 0, frameCount: 16), 0)
        XCTAssertEqual(GlassSpectrumRenderer.frameIndex(forPhase: 0.5, frameCount: 16), 8)
        XCTAssertEqual(GlassSpectrumRenderer.frameIndex(forPhase: 0.999, frameCount: 16), 15)
        XCTAssertEqual(GlassSpectrumRenderer.frameIndex(forPhase: -0.25, frameCount: 16), 12)
    }

    func test_sequenceIsCached_andRegeneratedOnlyWhenThePictureChanges() throws {
        SpectrumFrameCache.reset()
        defer { SpectrumFrameCache.reset() }
        let renderSpec = spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 320)
        let lane = CALayer()
        lane.frame = geometry.trackRect
        lane.contentsScale = 2
        GlassSpectrumRenderer.update(into: lane, spec: renderSpec, running: true, cycle: cycle, restart: true)
        let first = try XCTUnwrap(curtain(in: try XCTUnwrap(root(of: lane))))
        let firstImage = try XCTUnwrap(first.contents) as! CGImage

        GlassSpectrumRenderer.update(into: lane, spec: renderSpec, running: true, cycle: cycle, restart: false)
        XCTAssertTrue(try XCTUnwrap(first.contents) as! CGImage === firstImage,
                      "the same spec must reuse the cached sequence")
        XCTAssertEqual(SpectrumFrameCache.cachedSequenceCount, 1)

        var other = renderSpec
        other.waveIntensity = 0.9
        GlassSpectrumRenderer.update(into: lane, spec: other, running: true, cycle: cycle, restart: true)
        XCTAssertEqual(SpectrumFrameCache.cachedSequenceCount, 2,
                       "a visual change must build a new sequence instead of staling")
    }

    func test_cacheBudget_isBoundedInBytes() throws {
        SpectrumFrameCache.reset()
        defer { SpectrumFrameCache.reset() }
        var spec = spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 1024)
        for step in 0..<40 {
            spec.waveIntensity = 0.30 + Double(step % 20) * 0.03
            let lane = CALayer()
            lane.frame = spec.geometry.trackRect
            lane.contentsScale = 2
            GlassSpectrumRenderer.update(into: lane, spec: spec, running: true, cycle: cycle, restart: true)
        }
        XCTAssertLessThanOrEqual(SpectrumFrameCache.cachedByteCount, SpectrumFrameCache.byteLimit,
                                 "the frame cache must stay inside its byte budget")
        XCTAssertGreaterThan(SpectrumFrameCache.cachedSequenceCount, 0)
    }

    // MARK: - Offline phase frames

    func test_phaseFrames_differAcrossPhases() throws {
        let renderSpec = spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 320)
        let frames: [CGImage] = try stride(from: 0.0, through: 0.75, by: 0.25).map { phase in
            try XCTUnwrap(GlassSpectrumRenderer.frameImage(for: renderSpec, phase: phase))
        }
        XCTAssertEqual(frames.count, 4)
        for (index, frame) in frames.enumerated() where index > 0 {
            XCTAssertFalse(frames[index - 1] === frame)
        }
        // Phase 0 and phase 0.5 must differ by more than a stray pixel: compare
        // the per-ray tip height of the frozen frames.
        let tips = frames.map { rayTipHeights($0, rayCount: SpectrumWaveModel.rayCount(width: 320, density: 1)) }
        let moved = zip(tips[0], tips[2]).filter { abs($0 - $1) > 2 }.count
        XCTAssertGreaterThan(moved, tips[0].count / 3,
                             "four phases must produce visibly different ray shapes")
    }

    /// Where each ray's ink starts, in pixels from the top of the frame.
    private func rayTipHeights(_ image: CGImage, rayCount: Int) -> [Int] {
        let rep = NSBitmapImageRep(cgImage: image)
        return (0..<rayCount).map { index in
            let x = Int((Double(index) + 0.5) / Double(rayCount) * Double(rep.pixelsWide))
            for row in 0..<rep.pixelsHigh {
                let lit = ((-1)...1).contains { offset in
                    (rep.colorAt(x: min(rep.pixelsWide - 1, max(0, x + offset)), y: row)?.alphaComponent ?? 0) > 0.02
                }
                if lit { return row }
            }
            return rep.pixelsHigh
        }
    }

    // MARK: - Quota clip at the real remaining length

    func test_spectrumIsClippedToTheRealOuterQuotaLength() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(windows: [QuotaWindow(id: "w", label: "w", kind: .weekly, durationSeconds: 604800,
                        remainingFraction: 0.5, resetAt: nil, expectedRemainingFraction: nil,
                        updatedAt: nil, availability: .valid)],
                 signal: ProviderVisualSignal(isRunning: true), trackWidth: 400),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        // The mask is not a sublayer of the lane (LayerSlot.reconcile owns only
        // the named slots), and it lives in spectrum-root coordinates.
        XCTAssertNil(lane.sublayers?.first { $0.name == "quotaClip" })
        let clip = try XCTUnwrap(spectrum.mask)
        XCTAssertTrue(spectrum.mask === clip)
        XCTAssertEqual(clip.frame.width, 200, accuracy: 0.5,
                       "a 50% outer window clips the curtain to half the lane")
        XCTAssertEqual(clip.frame.minX, 0, accuracy: 0.5)
        XCTAssertFalse(spectrum.sublayers?.contains { $0 === clip } ?? false)
    }

    func test_allZeroQuotaClipsTheSpectrumToNothingWhileRunningStaysIndependent() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(windows: [QuotaWindow(id: "w", label: "w", kind: .weekly, durationSeconds: 604800,
                        remainingFraction: 0, resetAt: nil, expectedRemainingFraction: nil,
                        updatedAt: nil, availability: .valid)],
                 signal: ProviderVisualSignal(isRunning: true), trackWidth: 400),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let clip = try XCTUnwrap(spectrum.mask)
        XCTAssertEqual(clip.frame.width, 0)
        XCTAssertFalse(spectrum.isHidden, "the running input is independent of the black region")
    }

    func test_unknownQuotaKeepsTheNeutralTrackUnclipped() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(windows: [QuotaWindow(id: "w", label: "w", kind: .weekly, durationSeconds: 604800,
                        remainingFraction: nil, resetAt: nil, expectedRemainingFraction: nil,
                        updatedAt: nil, availability: .unavailable)],
                 signal: ProviderVisualSignal(isRunning: true), trackWidth: 400),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        XCTAssertEqual(try XCTUnwrap(spectrum.mask).frame.width, 400, accuracy: 0.5)
    }

    func test_quotaClipIdentity_isReusedAcrossUnknownAndValid() throws {
        let lane = CALayer()
        lane.frame = geometry.trackRect
        let unknown = spec(windows: [QuotaWindow(id: "w", label: "w", kind: .weekly, durationSeconds: 604800,
                              remainingFraction: nil, resetAt: nil, expectedRemainingFraction: nil,
                              updatedAt: nil, availability: .unavailable)],
                           signal: ProviderVisualSignal(isRunning: true), trackWidth: 400)
        GlassSpectrumRenderer.update(into: lane, spec: unknown, running: true, cycle: cycle, restart: true)
        let clip = try XCTUnwrap(try XCTUnwrap(root(of: lane)).mask)
        GlassSpectrumRenderer.update(
            into: lane, spec: spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 400),
            running: true, cycle: cycle, restart: false
        )
        XCTAssertTrue(try XCTUnwrap(root(of: lane)).mask === clip,
                      "a quota refresh must not rebuild (and flash) the clip")
    }

    // MARK: - Colour priority and independence

    func test_curtainColour_followsTheAttentionPriority() throws {
        func components(_ kind: AttentionKind) throws -> [CGFloat] {
            let lane = GlassSpectrumRenderer.render(
                spec(signal: ProviderVisualSignal(isRunning: true, attention: kind), trackWidth: 320),
                running: true, cycle: cycle, restart: true
            )
            let spectrum = try XCTUnwrap(root(of: lane))
            let frame = try XCTUnwrap(curtain(in: spectrum)?.contents) as! CGImage
            let rep = NSBitmapImageRep(cgImage: frame)
            let pixel = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
            let rgb = pixel.usingColorSpace(.deviceRGB) ?? .clear
            return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        }
        let waiting = try components(.waiting)
        let error = try components(.error)
        XCTAssertGreaterThan(error[0], error[1], "error wears the red light")
        XCTAssertGreaterThan(waiting[0], waiting[2], "waiting wears the amber light")
        XCTAssertNotEqual(error, waiting)
    }

    /// The curtain is a painted layer, so under an alert it wears the
    /// *saturated* partner of the signal colour: the pale alert does not
    /// survive the menu bar material (`#FFE1A0` arrived as `192,164,104`).
    func test_alertingCurtainWearsTheSaturatedTint() throws {
        func pixel(_ kind: AttentionKind) throws -> (red: CGFloat, blue: CGFloat) {
            let lane = GlassSpectrumRenderer.render(
                spec(signal: ProviderVisualSignal(isRunning: true, attention: kind), trackWidth: 320),
                running: true, cycle: cycle, restart: true
            )
            let spectrum = try XCTUnwrap(root(of: lane))
            let frame = try XCTUnwrap(curtain(in: spectrum)?.contents) as! CGImage
            let rep = NSBitmapImageRep(cgImage: frame)
            let pixel = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
            let colour = pixel.usingColorSpace(.deviceRGB) ?? .clear
            return (colour.redComponent, colour.blueComponent)
        }
        let lights = GlassDefaults.signalLights
        let waiting = try pixel(.waiting)
        let paleRatio = lights.waiting.blue / lights.waiting.red
        XCTAssertLessThan(Double(waiting.blue / waiting.red), Double(paleRatio) * 0.85,
                          "the field is painted in the tint, not in the pale alert")
        XCTAssertGreaterThan(waiting.blue, 0, "and it is still amber, not red")
    }

    func test_providerAgentTheme_doesNotColourTheCurtain() throws {
        var themed = ResolvedGlassTheme.default(providerId: "codex")
        themed.agentThemeColor = RGBAColor(red: 1, green: 0, blue: 1)
        let lane = GlassSpectrumRenderer.render(
            spec(glass: themed, signal: ProviderVisualSignal(isRunning: true), trackWidth: 320),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let frame = try XCTUnwrap(curtain(in: spectrum)?.contents) as! CGImage
        let rep = NSBitmapImageRep(cgImage: frame)
        let pixel = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
        let rgb = pixel.usingColorSpace(.deviceRGB) ?? .clear
        XCTAssertGreaterThan(rgb.blueComponent, rgb.greenComponent,
                             "the curtain keeps the running signal light, not the provider glow")
        XCTAssertGreaterThan(rgb.blueComponent, rgb.redComponent)
    }

    // MARK: - Phase carry

    func test_curtainKeyframes_closeTheLoopWithEveryFrameShownOnce() throws {
        let frames = try (0..<6).map { index -> CGImage in
            try XCTUnwrap(GlassSpectrumRenderer.frameImage(
                for: spec(signal: ProviderVisualSignal(isRunning: true)),
                phase: SpectrumWaveModel.framePhase(index: index, count: 6)
            ))
        }
        let timeline = GlassSpectrumRenderer.curtainKeyframeTimeline(frames: frames)
        // A `contents` keyframe animation whose last key time is below 1.0
        // falls back to the model value for the rest of the cycle: the last
        // frame never appears and the loop hitches once per cycle.
        XCTAssertEqual(timeline.keyTimes.last?.doubleValue, 1.0)
        XCTAssertEqual(timeline.values.count, frames.count + 1,
                       "the timeline closes with the first phase again")
        XCTAssertTrue(timeline.values.last === frames[0])
        let steps = zip(timeline.keyTimes, timeline.keyTimes.dropFirst())
            .map { $1.doubleValue - $0.doubleValue }
        for step in steps {
            XCTAssertEqual(step, 1.0 / Double(frames.count), accuracy: 0.0001,
                           "every phase holds for exactly one step")
        }
    }

    func test_curtainAnimation_playsTheClosedTimeline() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let animation = try XCTUnwrap(
            curtain(in: try XCTUnwrap(root(of: lane)))?.animation(forKey: "curtainFrames")
                as? CAKeyframeAnimation
        )
        let keyTimes = try XCTUnwrap(animation.keyTimes)
        XCTAssertEqual(keyTimes.last?.doubleValue, 1.0)
        XCTAssertEqual((animation.values as? [CGImage])?.count, keyTimes.count)
    }

    func test_phaseCarry_survivesADurationChange() {
        let animation = CABasicAnimation(keyPath: "contents")
        animation.duration = 2
        animation.beginTime = 100
        animation.timeOffset = 0.5
        let carry = GlassSpectrumRenderer.phaseCarry(from: animation, now: 100.5)
        XCTAssertEqual(carry, 0.5, accuracy: 0.001,
                       "re-timing a live slider drag must continue from the current phase")
    }

    func test_phaseCarry_isZeroWithoutAPreviousTimeline() {
        XCTAssertEqual(GlassSpectrumRenderer.phaseCarry(from: nil, now: 100), 0)
    }
}
