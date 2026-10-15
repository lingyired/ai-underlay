import XCTest
import AppKit
@testable import AIUnderlayKit

/// The stability contract: repeated updates converge to the same tree, never
/// restart animations that did not change, and never grow the layer count.
@MainActor
final class GlassLayerHostTests: XCTestCase {
    private let geometry = GaugeGeometry(
        trackRect: CGRect(x: 0, y: 0, width: 1000, height: 30),
        fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
        growsTowardRight: true
    )

    private func window(_ id: String, remaining: Double?) -> QuotaWindow {
        QuotaWindow(id: id, label: id, kind: .custom, durationSeconds: id == "w" ? 604800 : 18000,
                    remainingFraction: remaining, resetAt: nil, expectedRemainingFraction: nil,
                    updatedAt: nil, availability: remaining == nil ? .unavailable : .valid)
    }

    private func spec(
        quota: Double = 0.8,
        glass: ResolvedGlassTheme = .default(providerId: "codex"),
        signal: ProviderVisualSignal? = ProviderVisualSignal(isRunning: true),
        reduceMotion: Bool = false,
        spectrumFloorHz: Double = SpectrumRhythm.floorFrequencyHz
    ) -> LaneRenderSpec {
        LaneRenderSpec(
            providerId: "codex", geometry: geometry,
            windows: [window("w", remaining: quota), window("s", remaining: 0.5)],
            palette: .codex, baseline: nil, glass: glass, signal: signal,
            reduceMotion: reduceMotion, spectrumFloorHz: spectrumFloorHz
        )
    }

    func test_baselineTempo_changesTheLiveCycle() throws {
        let host = GlassLayerHost()
        host.update(spec(spectrumFloorHz: 0.5))

        let rays = host.root.sublayers?.first { $0.name == "spectrum" }?
            .sublayers?.first { $0.name == "rays0" }
        let breath = try XCTUnwrap(rays?.animation(forKey: "rayBreath") as? CAKeyframeAnimation)
        XCTAssertEqual(breath.duration, 2.0, accuracy: 0.0001,
                       "0.5 Hz is a two-second cycle, whatever the engine default is")

        // Picking a new baseline re-times the running animation instead of
        // waiting for the old cycle to end.
        host.update(spec(spectrumFloorHz: 0.7))
        let retimed = try XCTUnwrap(rays?.animation(forKey: "rayBreath") as? CAKeyframeAnimation)
        XCTAssertEqual(retimed.duration, 1 / 0.7, accuracy: 0.0001)
    }

    func test_baselineTempo_changeRestartsTheLightField() {
        let host = GlassLayerHost()
        host.update(spec(spectrumFloorHz: 0.5))
        let starts = host.diagnostics.animationStarts

        host.update(spec(spectrumFloorHz: 0.5))
        XCTAssertEqual(host.diagnostics.animationStarts, starts,
                       "repeating the same tempo must not restart anything")

        host.update(spec(spectrumFloorHz: 0.9))
        XCTAssertGreaterThan(host.diagnostics.animationStarts, starts)
    }

    func test_repeatingTheSameSpecNeverGrowsTheTreeOrRestartsAnimations() {
        let host = GlassLayerHost()
        host.update(spec())
        let layerCount = host.diagnostics.layerCount
        let animatedCount = host.diagnostics.animatedLayerCount
        let starts = host.diagnostics.animationStarts

        for _ in 0..<100 { host.update(spec()) }

        XCTAssertEqual(host.diagnostics.layerCount, layerCount)
        XCTAssertEqual(host.diagnostics.animatedLayerCount, animatedCount)
        XCTAssertEqual(host.diagnostics.animationStarts, starts,
                       "an unchanged spec must not restart a single animation")
    }

    func test_quotaRefreshKeepsTheRunningAnimationAlive() {
        let host = GlassLayerHost()
        host.update(spec(quota: 0.8))
        let rays = host.root.sublayers?.first { $0.name == "spectrum" }?
            .sublayers?.first { $0.name == "rays0" }
        let first = rays?.animation(forKey: "rayBreath")
        XCTAssertNotNil(first)

        // The new quota snapshot arrives; nothing about motion changed.
        host.update(spec(quota: 0.4))

        let second = rays?.animation(forKey: "rayBreath")
        XCTAssertTrue(first === second, "a quota refresh must not restart the light field")
        XCTAssertEqual(host.diagnostics.animationStarts, 1)
    }

    func test_themeColorChangeDoesNotMoveQuotaGeometry() {
        let host = GlassLayerHost()
        host.update(spec())
        let fills = host.root.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "fills" }?.sublayers
        let frames = fills?.map(\.frame)

        var retinted = ResolvedGlassTheme.default(providerId: "codex")
        retinted.agentThemeColor = RGBAColor(red: 0.7, green: 0.2, blue: 0.9)
        host.update(spec(glass: retinted))

        XCTAssertEqual(fills?.map(\.frame), frames, "tinting is a colour change, never a geometry change")
    }

    func test_runningToIdle_stopsAnimations_AndBackRestartsThem() {
        let host = GlassLayerHost()
        host.update(spec())
        let spectrum = host.root.sublayers?.first { $0.name == "spectrum" }
        XCTAssertNotNil(spectrum?.sublayers?.first { $0.name == "rays0" }?.animation(forKey: "rayBreath"))

        host.update(spec(signal: ProviderVisualSignal(isRunning: false)))
        XCTAssertEqual(spectrum?.isHidden, true)
        XCTAssertNil(spectrum?.sublayers?.first { $0.name == "rays0" }?.animation(forKey: "rayBreath"))

        host.update(spec())
        XCTAssertEqual(spectrum?.isHidden, false)
        XCTAssertNotNil(spectrum?.sublayers?.first { $0.name == "rays0" }?.animation(forKey: "rayBreath"))
    }

    func test_attentionKindChangeRestartsTheSweep_butRepeatDoesNot() {
        let host = GlassLayerHost()
        host.update(spec(signal: ProviderVisualSignal(isRunning: false, attention: .waiting)))
        let startsAfterWaiting = host.diagnostics.animationStarts
        host.update(spec(signal: ProviderVisualSignal(isRunning: false, attention: .waiting)))
        XCTAssertEqual(host.diagnostics.animationStarts, startsAfterWaiting)

        host.update(spec(signal: ProviderVisualSignal(isRunning: false, attention: .error)))
        XCTAssertGreaterThan(host.diagnostics.animationStarts, startsAfterWaiting)
        let top = host.root.sublayers?.first { $0.name == "attention" }?
            .sublayers?.first { $0.name == "topLine" }
        let components = top?.backgroundColor?.components ?? []
        XCTAssertEqual(Double(components[0]), GlassDefaults.signalLights.error.red, accuracy: 0.01)
    }

    func test_runningWithAttention_showsBothChannels() {
        let host = GlassLayerHost()
        host.update(spec(signal: ProviderVisualSignal(isRunning: true, attention: .waiting)))
        let spectrum = host.root.sublayers?.first { $0.name == "spectrum" }
        let attention = host.root.sublayers?.first { $0.name == "attention" }
        XCTAssertEqual(spectrum?.isHidden, false, "work continues while waiting")
        XCTAssertEqual(attention?.isHidden, false)
        let light = spectrum?.sublayers?.first { $0.name == "field0" } as? CAGradientLayer
        let tint = (light?.colors as? [CGColor])?[safeColor: 3]
        let components = tint?.components ?? []
        XCTAssertEqual(Double(components[0]), GlassDefaults.signalLights.waiting.red, accuracy: 0.02,
                       "a running light wears the highest attention colour")
    }

    func test_reduceMotionStopsEverythingButKeepsTheStaticLayout() {
        let host = GlassLayerHost()
        host.update(spec(signal: ProviderVisualSignal(isRunning: true, attention: .error), reduceMotion: true))
        XCTAssertEqual(host.diagnostics.animatedLayerCount, 0)
        XCTAssertEqual(host.root.sublayers?.first { $0.name == "spectrum" }?.isHidden, false)
        XCTAssertEqual(host.root.sublayers?.first { $0.name == "attention" }?.isHidden, false)
    }

    func test_teardownLeavesNothingAnimating() {
        let host = GlassLayerHost()
        host.update(spec(signal: ProviderVisualSignal(isRunning: true, attention: .error)))
        host.teardown()
        XCTAssertEqual(host.diagnostics.animatedLayerCount, 0)
    }

    /// The tint's optional ambient drift (only on when ambientGlow > 0) is
    /// owned by the quota renderer, so teardown has to stop it too.
    func test_teardownAlsoStopsTheTintAmbientDrift() {
        var glass = ResolvedGlassTheme.default(providerId: "codex")
        glass.material.ambientGlow = 0.6
        let host = GlassLayerHost()
        host.update(spec(glass: glass, signal: ProviderVisualSignal(isRunning: true)))
        let ambient = host.root.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "tint" }?
            .sublayers?.first { $0.name == "tintClip" }?
            .sublayers?.first { $0.name == "tintAmbient" }
        XCTAssertNotNil(ambient?.animation(forKey: "ambientDrift"))

        host.teardown()
        XCTAssertNil(ambient?.animation(forKey: "ambientDrift"))
        XCTAssertEqual(host.diagnostics.animatedLayerCount, 0)
    }

    func test_laneZOrderIsStable() {
        let host = GlassLayerHost()
        host.update(spec(signal: ProviderVisualSignal(isRunning: true, attention: .error)))
        XCTAssertEqual(host.root.sublayers?.compactMap(\.name),
                       ["quotaGlass", "spectrum", "attention", "baseline"],
                       "baseline stays on top, glass below everything")
    }

    // MARK: - Dual-lane isolation

    /// In a dual layout the two lanes are siblings stacked on the same screen-
    /// wide track, so anything a lane paints at full width lands on top of the
    /// other provider's fills. The second lane must leave the first lane's half
    /// pixel-identical — the reported "only one provider, but the effect fills
    /// the whole menu bar".
    func test_dualLanes_secondLaneLeavesTheFirstHalfPixelIdentical() throws {
        let (left, right) = try dualGeometries()
        let running = ProviderVisualSignal(isRunning: true)

        let leftOnly = GlassLayerHost()
        leftOnly.update(specFor(geometry: left, provider: "codex", signal: running))
        let rightOnly = GlassLayerHost()
        rightOnly.update(specFor(geometry: right, provider: "claude", signal: running))

        let size = CGSize(width: 2048, height: 30)
        let alone = try rasterise([leftOnly.root], size: size)
        let together = try rasterise([leftOnly.root, rightOnly.root], size: size)

        let differing = try countDifferingPixels(alone, together, region: CGRect(x: 0, y: 0, width: 1024, height: 30))
        XCTAssertEqual(differing, 0, "the right lane must not repaint the left provider's half")
    }

    /// The mirror case: the left lane is added first, so it must not paint into
    /// the right provider's half either.
    func test_dualLanes_firstLaneLeavesTheOtherHalfPixelIdentical() throws {
        let (left, right) = try dualGeometries()
        let running = ProviderVisualSignal(isRunning: true)

        let leftOnly = GlassLayerHost()
        leftOnly.update(specFor(geometry: left, provider: "codex", signal: running))
        let rightOnly = GlassLayerHost()
        rightOnly.update(specFor(geometry: right, provider: "claude", signal: running))

        let size = CGSize(width: 2048, height: 30)
        let alone = try rasterise([rightOnly.root], size: size)
        let together = try rasterise([rightOnly.root, leftOnly.root], size: size)

        let differing = try countDifferingPixels(alone, together, region: CGRect(x: 1024, y: 0, width: 1024, height: 30))
        XCTAssertEqual(differing, 0, "the left lane must not repaint the right provider's half")
    }

    /// With one provider configured the other lane is `LaneContent.empty`.
    /// Its neutral groove is legitimate on its own half and must stay there.
    func test_emptyNeighbourLane_doesNotTouchThePopulatedHalf() throws {
        let (left, right) = try dualGeometries()
        let leftHost = GlassLayerHost()
        leftHost.update(specFor(geometry: left, provider: "codex",
                                signal: ProviderVisualSignal(isRunning: true)))
        let emptyHost = GlassLayerHost()
        emptyHost.update(LaneContent.empty(providerId: "claude").spec(geometry: right))

        let size = CGSize(width: 2048, height: 30)
        let alone = try rasterise([leftHost.root], size: size)
        let together = try rasterise([leftHost.root, emptyHost.root], size: size)

        let differing = try countDifferingPixels(alone, together, region: CGRect(x: 0, y: 0, width: 1024, height: 30))
        XCTAssertEqual(differing, 0, "an unknown lane must not dim the populated provider")
    }

    /// Single layout has no neighbour: the light curtain still spans the whole
    /// bar, which is the whole point of that mode.
    func test_singleLane_stillPaintsTheWholeTrack() {
        let geometry = GaugeGeometry(
            trackRect: CGRect(x: 0, y: 0, width: 2048, height: 30),
            fillBounds: CGRect(x: 0, y: 0, width: 2048, height: 30),
            growsTowardRight: true
        )
        let host = GlassLayerHost()
        host.update(specFor(geometry: geometry, provider: "codex",
                            signal: ProviderVisualSignal(isRunning: true)))
        for slot in ["spectrum", "attention"] {
            let frame = host.root.sublayers?.first { $0.name == slot }?.frame
            XCTAssertEqual(frame?.width ?? .nan, 2048, accuracy: 0.001, slot)
        }
        let bed = host.root.sublayers?.first { $0.name == "quotaGlass" }?
            .sublayers?.first { $0.name == "bed" }
        XCTAssertEqual(bed?.frame.width ?? .nan, 2048, accuracy: 0.001)
    }

    // MARK: - Dual-lane helpers

    private func dualGeometries() throws -> (left: GaugeGeometry, right: GaugeGeometry) {
        let placed = GaugeLayout.layout(
            mode: .dual, anchor: .outerEdge, singleDirection: .leadingToTrailing,
            screenFrame: CGRect(x: 0, y: 0, width: 2048, height: 30),
            menuBarHeight: 30, notchEdges: nil
        )
        let left = try XCTUnwrap(placed.first { $0.side == .left }?.geometry)
        let right = try XCTUnwrap(placed.first { $0.side == .right }?.geometry)
        XCTAssertEqual(left.fillBounds.width, 1024)
        XCTAssertEqual(right.fillBounds.minX, 1024)
        return (left, right)
    }

    private func specFor(geometry: GaugeGeometry, provider: String, signal: ProviderVisualSignal) -> LaneRenderSpec {
        LaneRenderSpec(
            providerId: provider, geometry: geometry,
            windows: [window("w", remaining: 0.82), window("s", remaining: 0.55)],
            palette: ProviderPalette.for(providerId: provider),
            glass: .default(providerId: provider), signal: signal
        )
    }

    /// Draws the given lanes onto one transparent bitmap, the way the overlay
    /// stacks them in its band window.
    private func rasterise(_ lanes: [CALayer], size: CGSize, scale: CGFloat = 2) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for lane in lanes { lane.render(in: context.cgContext) }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Number of pixels inside `region` that differ by more than one 8-bit step
    /// across any channel.
    private func countDifferingPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, region: CGRect) throws -> Int {
        let scale = CGFloat(a.pixelsWide) / 2048
        let x0 = Int(region.minX * scale), x1 = Int(region.maxX * scale)
        let y0 = Int(region.minY * scale), y1 = Int(region.maxY * scale)
        var differing = 0
        for x in stride(from: x0, to: x1, by: 2) {
            for y in stride(from: y0, to: y1, by: 2) {
                let pa = try XCTUnwrap(a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let pb = try XCTUnwrap(b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let delta = abs(pa.redComponent - pb.redComponent)
                    + abs(pa.greenComponent - pb.greenComponent)
                    + abs(pa.blueComponent - pb.blueComponent)
                    + abs(pa.alphaComponent - pb.alphaComponent)
                if delta > 1.0 / 255 { differing += 1 }
            }
        }
        return differing
    }
}

private extension Array where Element == CGColor {
    subscript(safeColor index: Int) -> CGColor? {
        indices.contains(index) ? self[index] : nil
    }
}
