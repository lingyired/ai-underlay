import XCTest
import AppKit
@testable import AIUnderlayKit

/// Phase B contract: a weak static bed, a bright copy windowed by a moving
/// mask, shared field/peak geometry, quota-length clipping and the two
/// travelling-light switch semantics.
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
            showsTravelingLight: showsTravelingLight
        )
    }

    private func root(of lane: CALayer) -> CALayer? {
        lane.sublayers?.first { $0.name == "spectrum" }
    }

    private func peakLayers(in spectrum: CALayer) -> [CALayer] {
        (spectrum.sublayers ?? []).filter { $0.name?.hasPrefix("peak") == true }
            .filter { $0.name?.hasPrefix("peakmask") != true }
    }

    private func bedLayers(in spectrum: CALayer) -> [CALayer] {
        (spectrum.sublayers ?? []).filter { $0.name?.hasPrefix("rays") == true }
    }

    private func fieldLayers(in spectrum: CALayer) -> [CALayer] {
        (spectrum.sublayers ?? []).filter { $0.name?.hasPrefix("field") == true }
    }

    private let cycle = SpectrumRhythm.cycleDuration(outputTPS: nil)

    // MARK: - Structure

    func test_running_drawsThreeBedsThreeMaskedPeaksAndTwoFields() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        XCTAssertEqual(bedLayers(in: spectrum).count, 3)
        XCTAssertEqual(peakLayers(in: spectrum).count, 3)
        XCTAssertEqual(fieldLayers(in: spectrum).count, 2)
        for peaks in peakLayers(in: spectrum) {
            XCTAssertNotNil(peaks.mask, "the bright copy must use a real mask, not an overlay")
            XCTAssertTrue((peaks.sublayers ?? []).isEmpty)
        }
    }

    func test_staticBedIsWeak_andDensityEscalatesOnlyThePeakWindow() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let bed = try XCTUnwrap(bedLayers(in: spectrum).first)
        let peaks = try XCTUnwrap(peakLayers(in: spectrum).first)
        XCTAssertEqual(bed.opacity, GlassSpectrumRenderer.bedOpacity, accuracy: 0.0001)
        XCTAssertEqual(peaks.opacity, GlassSpectrumRenderer.peakOpacity, accuracy: 0.0001)
        XCTAssertGreaterThan(peaks.opacity, bed.opacity * 3,
                             "brightness must come from the local peak, not the whole curtain")
    }

    func test_rayGroups_areTexturesNotOneLayerPerRay() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        for layer in (bedLayers(in: spectrum) + peakLayers(in: spectrum)) {
            XCTAssertNotNil(layer.contents, "the density lives in one cached bitmap per group")
            XCTAssertTrue((layer.sublayers ?? []).isEmpty)
        }
    }

    func test_density_changesTheRenderedTexture_butReusesItForBedAndPeak() throws {
        var dense = ResolvedGlassTheme.default(providerId: "codex")
        dense.material.rayDensity = 1.0
        var sparse = dense
        sparse.material.rayDensity = 0.1
        func textures(_ glass: ResolvedGlassTheme) throws -> (CGImage, CGImage) {
            let lane = GlassSpectrumRenderer.render(
                spec(glass: glass, signal: ProviderVisualSignal(isRunning: true)),
                running: true, cycle: cycle, restart: true
            )
            let spectrum = try XCTUnwrap(root(of: lane))
            let bed = try XCTUnwrap(bedLayers(in: spectrum).first)
            let peaks = try XCTUnwrap(peakLayers(in: spectrum).first)
            return (try XCTUnwrap(bed.contents) as! CGImage, try XCTUnwrap(peaks.contents) as! CGImage)
        }
        let (denseBed, densePeak) = try textures(dense)
        let (sparseBed, _) = try textures(sparse)
        XCTAssertFalse(denseBed === sparseBed, "ray density must change the texture, not be a no-op")
        XCTAssertTrue(denseBed === densePeak, "the bright copy reuses the cached texture")
        let (againBed, _) = try textures(dense)
        XCTAssertTrue(denseBed === againBed, "the same settings must reuse the cached texture")
    }

    /// The V5 curtain stands on the strip: every ray's base is flush with the
    /// bottom edge and only the tips wave.
    func test_rayCurtain_standsOnTheBottomEdge() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let layer = try XCTUnwrap(bedLayers(in: spectrum).first)
        let texture = try XCTUnwrap(layer.contents) as! CGImage
        let rep = NSBitmapImageRep(cgImage: texture)
        let pixelWidth = rep.pixelsWide
        let pixelHeight = rep.pixelsHigh

        func alpha(nearCentre centre: Int, row: Int) -> CGFloat {
            ((-1)...1).compactMap { rep.colorAt(x: centre + $0, y: row)?.alphaComponent }.max() ?? 0
        }

        let density = ResolvedGlassTheme.default(providerId: "codex").material.rayDensity
        let rayCount = max(24, Int((geometry.trackRect.width / 8.5 * (0.55 + density * 1.25)).rounded()))
        let centres = stride(from: 0, to: rayCount, by: 3).map { index in
            Int(((CGFloat(index) + 0.5) / CGFloat(rayCount)) * CGFloat(pixelWidth))
        }
        XCTAssertGreaterThan(centres.count, 20)

        let litAtBottom = centres.filter { alpha(nearCentre: $0, row: pixelHeight - 1) > 0.08 }
        XCTAssertEqual(litAtBottom.count, centres.count,
                       "every ray's base is flush with the bottom edge")

        let tips = centres.compactMap { centre in
            (0..<pixelHeight).first { alpha(nearCentre: centre, row: $0) > 0.08 }
        }
        XCTAssertEqual(tips.count, centres.count, "every ray is drawn")
        let spread = (tips.max() ?? 0) - (tips.min() ?? 0)
        XCTAssertGreaterThan(Double(spread), Double(pixelHeight) * 0.15,
                             "the wave lives in the tips, not in a flat block")
    }

    func test_peakMask_isAContinuousWindow_notAFlatPlatform() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let peaks = try XCTUnwrap(peakLayers(in: spectrum).first)
        let mask = try XCTUnwrap(peaks.mask as? CAGradientLayer)
        let alphas = (mask.colors as? [CGColor])?.map(\.alpha) ?? []
        XCTAssertEqual(alphas, [0, 0.15, 1, 0.15, 0], "only the local core reaches full energy")
        let locations = (mask.locations ?? []).map(\.doubleValue)
        XCTAssertEqual(locations.first, 0)
        XCTAssertEqual(locations.last, 1)
        XCTAssertGreaterThan(locations[1], 0.02, "the shoulder must have real width")
    }

    // MARK: - Shared geometry and deterministic phase sampling

    func test_phaseSampler_matchesTheLightFieldTrajectory() throws {
        let laneWidth: CGFloat = 320
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: laneWidth),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let fields = fieldLayers(in: spectrum)
        XCTAssertEqual(fields.count, 2)
        let travels = fields.compactMap { $0.animation(forKey: "fieldTravel") as? CABasicAnimation }
        XCTAssertEqual(travels.count, 2)

        // The same endpoints the Core Animation timeline interpolates are the
        // ones the phase sampler reports, so mask and field cannot diverge.
        let fieldsModel = GlassSpectrumRenderer.LightFieldGeometry.racetrack(
            size: CGSize(width: laneWidth, height: 30), growsTowardRight: true
        )
        let model = SpectrumPhaseGeometry(
            size: CGSize(width: laneWidth, height: 30), fields: fieldsModel,
            cycle: cycle, growsTowardRight: true
        )
        XCTAssertEqual(travels[0].fromValue as? CGFloat, fieldsModel[0].fromX)
        XCTAssertEqual(travels[0].toValue as? CGFloat, fieldsModel[0].toX)
        XCTAssertEqual(travels[1].fromValue as? CGFloat, fieldsModel[1].fromX)
        XCTAssertEqual(model.primary.cycleFactor, fieldsModel[0].cycleFactor)
        XCTAssertEqual(model.secondary.cycleFactor, fieldsModel[1].cycleFactor,
                       "the secondary peak must keep its own period")
        let sample = model.sample(at: 0.3)
        XCTAssertEqual(sample.lightFieldOffsets[0], model.primary.offset(at: 0.3))
        XCTAssertEqual(sample.lightFieldOffsets[1], model.secondary.offset(at: 0.3 / model.secondary.cycleFactor))
    }

    func test_phaseSampler_peakWindowIsDarkOffCentre_andBrightAtCentre() {
        let size = CGSize(width: 320, height: 30)
        let fields = GlassSpectrumRenderer.LightFieldGeometry.racetrack(size: size, growsTowardRight: true)
        let model = SpectrumPhaseGeometry(
            size: size, fields: fields, cycle: cycle, growsTowardRight: true
        )
        let sample = model.sample(at: 0.25)
        let half = sample.primary.window / 2 + 4
        let alpha = { (x: CGFloat, phase: Double) -> Double in
            SpectrumPhaseGeometry.rampAlpha(
                x, sample: model.primary.sample(at: phase)
            )
        }
        XCTAssertGreaterThan(alpha(sample.primary.offset, 0.25), 0.95)
        XCTAssertLessThan(alpha(sample.primary.offset + half, 0.25), 0.02,
                          "just outside the window the peak is dark")
        XCTAssertLessThan(alpha(sample.primary.offset, 0.7),
                          alpha(sample.primary.offset, 0.25) - 0.5,
                          "the window must keep travelling")
    }

    func test_phaseSampler_mirrorsForLeftwardLanes() {
        let size = CGSize(width: 320, height: 30)
        let right = SpectrumPhaseGeometry(
            size: size,
            fields: GlassSpectrumRenderer.LightFieldGeometry.racetrack(size: size, growsTowardRight: true),
            cycle: cycle, growsTowardRight: true
        )
        let left = SpectrumPhaseGeometry(
            size: size,
            fields: GlassSpectrumRenderer.LightFieldGeometry.racetrack(size: size, growsTowardRight: false),
            cycle: cycle, growsTowardRight: false
        )
        XCTAssertTrue(right.primary.travelsTowardLeadingEdge)
        XCTAssertFalse(left.primary.travelsTowardLeadingEdge)
        XCTAssertGreaterThan(left.primary.offset(at: 0.2), left.primary.offset(at: 0.8),
                             "leftward lanes travel the other way")
        XCTAssertLessThan(right.primary.offset(at: 0.2), right.primary.offset(at: 0.8))
    }

    func test_applySampledPhase_movesTheBrightWindowWithoutRestartingProduction() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 320),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let mask = try XCTUnwrap(try XCTUnwrap(peakLayers(in: spectrum).first).mask as? CAGradientLayer)
        let production = try XCTUnwrap(mask.animation(forKey: "peakTravel") as? CABasicAnimation)
        XCTAssertEqual(production.keyPath, "transform.translation.x")
        XCTAssertEqual(production.duration, cycle, accuracy: 0.0001)

        GlassSpectrumRenderer.applySampledPhase(into: lane, spec: spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 320),
                                                cycle: cycle, phase: 0.2)
        let left = mask.transform.m41
        GlassSpectrumRenderer.applySampledPhase(into: lane, spec: spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 320),
                                                cycle: cycle, phase: 0.6)
        let right = mask.transform.m41
        XCTAssertGreaterThanOrEqual(abs(left - right), 320 * 0.15,
                                    "phase 0.2 and 0.6 must land at least 15% of the lane apart")
        XCTAssertNil(mask.animation(forKey: "peakTravel"),
                     "freezing a sampled phase must not leave the production timeline attached")
    }

    // MARK: - Travelling-light switch

    /// User setting `showsTravelingLight = false`: hide the wide sheen, keep a
    /// fixed local energy window, and never let a mask cross the lane.
    func test_travelingLightDisabled_hidesFieldsAndFreezesTheLocalWindow() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true), showsTravelingLight: false, trackWidth: 320),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        for field in fieldLayers(in: spectrum) {
            XCTAssertTrue(field.isHidden, "the full-width sheen must disappear")
            XCTAssertNil(field.animation(forKey: "fieldTravel"))
        }
        for peaks in peakLayers(in: spectrum) {
            XCTAssertFalse(peaks.isHidden)
            let mask = try XCTUnwrap(peaks.mask as? CAGradientLayer)
            XCTAssertNil(mask.animation(forKey: "peakTravel"), "no horizontal travel")
            XCTAssertEqual(mask.transform.m41, 160, accuracy: 0.5,
                           "the local window parks on the lane centre")
        }
    }

    func test_travelingLightToggle_appliesToTheLiveLayersBothWays() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 320),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let field = try XCTUnwrap(fieldLayers(in: spectrum).first)
        let mask = try XCTUnwrap(try XCTUnwrap(peakLayers(in: spectrum).first).mask as? CAGradientLayer)
        XCTAssertNotNil(field.animation(forKey: "fieldTravel"))
        XCTAssertNotNil(mask.animation(forKey: "peakTravel"))

        GlassSpectrumRenderer.update(
            into: lane, spec: spec(signal: ProviderVisualSignal(isRunning: true), showsTravelingLight: false, trackWidth: 320),
            running: true, cycle: cycle, restart: false
        )
        XCTAssertTrue(field.isHidden)
        XCTAssertNil(field.animation(forKey: "fieldTravel"))
        XCTAssertNil(mask.animation(forKey: "peakTravel"))

        GlassSpectrumRenderer.update(
            into: lane, spec: spec(signal: ProviderVisualSignal(isRunning: true), trackWidth: 320),
            running: true, cycle: cycle, restart: false
        )
        XCTAssertFalse(field.isHidden)
        XCTAssertNotNil(field.animation(forKey: "fieldTravel"))
        XCTAssertNotNil(mask.animation(forKey: "peakTravel"), "re-enabling restores the shared timeline")
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
                       "a 50% outer window clips the peak material to half the lane")
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
        XCTAssertEqual(spectrum.mask?.frame, spectrum.bounds,
                       "unknown keeps full neutral coverage instead of an exhausted zero mask")
    }

    func test_quotaClipIdentity_isReusedAcrossUnknownAndValid() throws {
        let lane = CALayer()
        lane.name = "lane"
        lane.frame = geometry.trackRect
        let valid = spec(windows: [QuotaWindow(id: "w", label: "w", kind: .weekly, durationSeconds: 604800,
                       remainingFraction: 0.82, resetAt: nil, expectedRemainingFraction: nil,
                       updatedAt: nil, availability: .valid)],
                         signal: ProviderVisualSignal(isRunning: true), trackWidth: 400)
        var unknown = valid
        unknown.windows = [QuotaWindow(id: "w", label: "w", kind: .weekly, durationSeconds: 604800,
                        remainingFraction: nil, resetAt: nil, expectedRemainingFraction: nil,
                        updatedAt: nil, availability: .unavailable)]
        GlassSpectrumRenderer.update(into: lane, spec: valid, running: true, cycle: cycle, restart: true)
        let spectrum = try XCTUnwrap(root(of: lane))
        let firstClip = try XCTUnwrap(spectrum.mask)
        GlassSpectrumRenderer.update(into: lane, spec: unknown, running: true, cycle: cycle, restart: false)
        XCTAssertTrue(spectrum.mask === firstClip)
        XCTAssertEqual(firstClip.frame, spectrum.bounds)
        GlassSpectrumRenderer.update(into: lane, spec: valid, running: true, cycle: cycle, restart: false)
        XCTAssertTrue(spectrum.mask === firstClip, "the mask layer is reused, not rebuilt")
        XCTAssertFalse(spectrum.sublayers?.contains { $0 === firstClip } ?? false)
    }

    // MARK: - Colour still follows the signal

    func test_rayColour_followsTheAttentionPriority() throws {
        func firstRayColor(_ attention: AttentionKind) throws -> RGBAColor {
            let lane = GlassSpectrumRenderer.render(
                spec(signal: ProviderVisualSignal(isRunning: true, attention: attention)),
                running: true, cycle: cycle, restart: true
            )
            let spectrum = try XCTUnwrap(root(of: lane))
            let field = try XCTUnwrap(fieldLayers(in: spectrum).first as? CAGradientLayer)
            let colors = try XCTUnwrap(field.colors as? [CGColor])
            let tint = try XCTUnwrap(colors.dropFirst().first { $0.alpha > 0 })
            let components = tint.components ?? []
            return RGBAColor(red: Double(components[0]), green: Double(components[1]),
                             blue: Double(components[2]), alpha: Double(components[3]))
        }
        let running = try firstRayColor(.none)
        let error = try firstRayColor(.error)
        let waiting = try firstRayColor(.waiting)
        let unread = try firstRayColor(.unread)
        XCTAssertNotEqual(running, error)
        XCTAssertEqual(error.red, GlassDefaults.signalLights.error.red, accuracy: 0.01)
        XCTAssertEqual(waiting.red, GlassDefaults.signalLights.waiting.red, accuracy: 0.01)
        XCTAssertEqual(unread.green, GlassDefaults.signalLights.unread.green, accuracy: 0.01)
    }

    func test_providerAgentTheme_doesNotColourTheRunningLight() throws {
        var purple = ResolvedGlassTheme.default(providerId: "codex")
        purple.agentThemeColor = RGBAColor(red: 0.6, green: 0.3, blue: 1.0)
        let lane = GlassSpectrumRenderer.render(
            spec(glass: purple, signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let field = try XCTUnwrap(fieldLayers(in: spectrum).first as? CAGradientLayer)
        let colors = try XCTUnwrap(field.colors as? [CGColor])
        let tint = try XCTUnwrap(colors.dropFirst().first { $0.alpha > 0 })
        let components = tint.components ?? []
        XCTAssertEqual(Double(components[2]), GlassDefaults.signalLights.running.blue, accuracy: 0.02)
    }

    // MARK: - Stop / Reduce Motion

    func test_notRunning_hidesTheCurtainAndStopsEverything() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: false)),
            running: false, cycle: cycle, restart: false
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        XCTAssertTrue(spectrum.isHidden)
        for layer in spectrum.sublayers ?? [] {
            XCTAssertNil(layer.animation(forKey: "rayBreath"))
            XCTAssertNil(layer.animation(forKey: "peakBreath"))
            XCTAssertNil(layer.animation(forKey: "peakTravel"))
            XCTAssertNil(layer.animation(forKey: "fieldTravel"))
            XCTAssertNil(layer.mask?.animation(forKey: "peakTravel"))
        }
    }

    func test_reduceMotion_drawsAStaticCurtain() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true), reduceMotion: true),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        XCTAssertFalse(spectrum.isHidden, "the state stays visible, only the motion goes")
        for layer in spectrum.sublayers ?? [] {
            XCTAssertNil(layer.animation(forKey: "rayBreath"))
            XCTAssertNil(layer.animation(forKey: "peakBreath"))
            XCTAssertNil(layer.animation(forKey: "peakTravel"))
            XCTAssertNil(layer.animation(forKey: "fieldTravel"))
            XCTAssertNil(layer.mask?.animation(forKey: "peakTravel"))
        }
    }

    func test_repeatedIdenticalRender_doesNotRestartAnimations() throws {
        let lane = CALayer()
        lane.frame = geometry.trackRect
        let spec = spec(signal: ProviderVisualSignal(isRunning: true))
        for _ in 0..<5 {
            GlassSpectrumRenderer.update(into: lane, spec: spec, running: true, cycle: cycle, restart: false)
        }
        let spectrum = try XCTUnwrap(root(of: lane))
        XCTAssertEqual(bedLayers(in: spectrum).count, 3)
        XCTAssertEqual(peakLayers(in: spectrum).count, 3)
        for peak in peakLayers(in: spectrum) {
            XCTAssertNotNil(peak.animation(forKey: "peakBreath"))
            let mask = try XCTUnwrap(peak.mask as? CAGradientLayer)
            XCTAssertNotNil(mask.animation(forKey: "peakTravel"))
        }
    }

    func test_continuousIds_modelPreservesLayerIdentity_andReusesMasks() throws {
        let lane = CALayer()
        lane.frame = geometry.trackRect
        let spec = spec(signal: ProviderVisualSignal(isRunning: true))
        GlassSpectrumRenderer.update(into: lane, spec: spec, running: true, cycle: cycle, restart: true)
        let spectrum = try XCTUnwrap(root(of: lane))
        let peak = try XCTUnwrap(peakLayers(in: spectrum).first)
        let mask = try XCTUnwrap(peak.mask)
        GlassSpectrumRenderer.update(into: lane, spec: spec, running: true, cycle: cycle, restart: true)
        XCTAssertTrue(peakLayers(in: spectrum).first === peak)
        XCTAssertTrue(peakLayers(in: spectrum).first?.mask === mask)
    }

    func test_curtainStandsOnAStaticDarkScrim() throws {
        let lane = CALayer()
        lane.frame = geometry.trackRect
        GlassSpectrumRenderer.update(
            into: lane, spec: spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let scrim = try XCTUnwrap(spectrum.sublayers?.first as? CAGradientLayer, "the bed is the bottom layer")
        XCTAssertEqual(scrim.name, "scrim")
        XCTAssertNil(scrim.animation(forKey: "rayBreath"))
        XCTAssertNil(scrim.animation(forKey: "fieldTravel"))
        let alphas = (scrim.colors as? [CGColor])?.map { $0.alpha } ?? []
        XCTAssertEqual(alphas.first, 0, "the bed fades out upward")
        XCTAssertGreaterThan(alphas.last ?? 0, 0.2, "the bed has to be dark enough to hold the light")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
