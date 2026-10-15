import XCTest
import AppKit
@testable import AIUnderlayKit

/// The single running engine: dense ray curtain, traveling field, bounded
/// layer count, and Reduce Motion compatibility.
@MainActor
final class GlassSpectrumRendererTests: XCTestCase {
    private let geometry = GaugeGeometry(
        trackRect: CGRect(x: 0, y: 0, width: 1000, height: 30),
        fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
        growsTowardRight: true
    )

    private func spec(
        windows: [QuotaWindow] = [],
        glass: ResolvedGlassTheme = .default(providerId: "codex"),
        signal: ProviderVisualSignal?,
        reduceMotion: Bool = false,
        growsTowardRight: Bool = true
    ) -> LaneRenderSpec {
        let geometry = GaugeGeometry(
            trackRect: self.geometry.trackRect,
            fillBounds: self.geometry.fillBounds,
            growsTowardRight: growsTowardRight
        )
        return LaneRenderSpec(
            providerId: "codex", geometry: geometry, windows: windows, palette: .codex,
            glass: glass, signal: signal, reduceMotion: reduceMotion
        )
    }

    private func root(of lane: CALayer) -> CALayer? {
        lane.sublayers?.first { $0.name == "spectrum" }
    }

    // MARK: - Running draws the curtain

    func test_running_drawsThreeRayGroupsAndTwoLightFields() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: SpectrumRhythm.cycleDuration(outputTPS: nil), restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let names = spectrum.sublayers?.map(\.name) ?? []
        XCTAssertEqual(names.filter { $0?.hasPrefix("rays") == true }.count, 3)
        XCTAssertEqual(names.filter { $0?.hasPrefix("field") == true }.count, 2)
    }

    func test_rayGroups_areTexturesNotOneLayerPerRay() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: 2.9, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        for layer in spectrum.sublayers ?? [] where layer.name?.hasPrefix("rays") == true {
            XCTAssertNotNil(layer.contents, "the density lives in one cached bitmap per group")
            XCTAssertTrue((layer.sublayers ?? []).isEmpty)
        }
        XCTAssertLessThanOrEqual(spectrum.sublayers?.count ?? 0, GlassSpectrumRenderer.maxAnimatedLayers)
    }

    func test_density_changesTheRenderedTexture() throws {
        var dense = ResolvedGlassTheme.default(providerId: "codex")
        dense.material.rayDensity = 1.0
        var sparse = dense
        sparse.material.rayDensity = 0.1
        func texture(_ glass: ResolvedGlassTheme) throws -> CGImage {
            let lane = GlassSpectrumRenderer.render(
                spec(glass: glass, signal: ProviderVisualSignal(isRunning: true)),
                running: true, cycle: 2.9, restart: true
            )
            let spectrum = try XCTUnwrap(root(of: lane))
            let rays = try XCTUnwrap(spectrum.sublayers?.first { $0.name == "rays0" })
            let raw = try XCTUnwrap(rays.contents)
            return raw as! CGImage
        }
        XCTAssertFalse(try texture(dense) === texture(sparse),
                       "ray density must change the texture, not be a no-op")
        XCTAssertTrue(try texture(dense) === texture(dense),
                      "the same settings must reuse the cached texture")
    }

    /// The V5 curtain stands on the strip: every ray's base is flush with the
    /// bottom edge and only the tips wave. An earlier port drew from the top
    /// edge, which hung the curtain from the top and put the ragged hem at the
    /// bottom — a structural test cannot see that, so this looks at pixels.
    func test_rayCurtain_standsOnTheBottomEdge() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: 2.9, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let layer = try XCTUnwrap(spectrum.sublayers?.first { $0.name == "rays0" })
        let texture = try XCTUnwrap(layer.contents) as! CGImage
        let rep = NSBitmapImageRep(cgImage: texture)
        let pixelWidth = rep.pixelsWide
        let pixelHeight = rep.pixelsHigh

        func alpha(nearCentre centre: Int, row: Int) -> CGFloat {
            ((-1)...1).compactMap { rep.colorAt(x: centre + $0, y: row)?.alphaComponent }.max() ?? 0
        }

        // The ray-centre rule is the one the texture draws with: every third
        // ray belongs to group 0.
        let density = ResolvedGlassTheme.default(providerId: "codex").material.rayDensity
        let rayCount = max(24, Int((geometry.trackRect.width / 8.5 * (0.55 + density * 1.25)).rounded()))
        let centres = stride(from: 0, to: rayCount, by: 3).map { index in
            Int(((CGFloat(index) + 0.5) / CGFloat(rayCount)) * CGFloat(pixelWidth))
        }
        XCTAssertGreaterThan(centres.count, 20)

        let litAtBottom = centres.filter { alpha(nearCentre: $0, row: pixelHeight - 1) > 0.08 }
        XCTAssertEqual(litAtBottom.count, centres.count,
                       "every ray's base is flush with the bottom edge, so the strip stands on one baseline")

        let tips = centres.compactMap { centre in
            (0..<pixelHeight).first { alpha(nearCentre: centre, row: $0) > 0.08 }
        }
        XCTAssertEqual(tips.count, centres.count, "every ray is drawn")
        let spread = (tips.max() ?? 0) - (tips.min() ?? 0)
        XCTAssertGreaterThan(Double(spread), Double(pixelHeight) * 0.15,
                             "the wave lives in the tips, not in a flat block")
    }

    func test_rayGroups_breathWithPhaseOffsets() throws {
        let cycle = 2.9
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: cycle, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let rays = (spectrum.sublayers ?? []).filter { $0.name?.hasPrefix("rays") == true }
        let beginTimes = rays.compactMap { ($0.animation(forKey: "rayBreath") as? CAKeyframeAnimation)?.beginTime }
        XCTAssertEqual(beginTimes.count, 3)
        XCTAssertEqual(Set(beginTimes).count, 3, "groups must not pulse in lockstep")
        for layer in rays {
            let animation = try XCTUnwrap(layer.animation(forKey: "rayBreath") as? CAKeyframeAnimation)
            XCTAssertEqual(animation.duration, cycle, accuracy: 0.0001)
            XCTAssertEqual(animation.repeatCount, .infinity)
        }
    }

    func test_lightFields_travelInOppositeDirections() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true)),
            running: true, cycle: 2.9, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let fields = (spectrum.sublayers ?? []).filter { $0.name?.hasPrefix("field") == true }
        let travels = fields.compactMap { $0.animation(forKey: "fieldTravel") as? CABasicAnimation }
        XCTAssertEqual(travels.count, 2)
        let froms = travels.map { ($0.fromValue as? CGFloat) ?? 0 }
        let tos = travels.map { ($0.toValue as? CGFloat) ?? 0 }
        XCTAssertLessThan(froms[0], tos[0], "the primary field travels with the growth direction")
        XCTAssertGreaterThan(froms[1], tos[1], "the reflected field travels the other way")
    }

    func test_leftwardLane_mirrorsTheFieldTravel() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true), growsTowardRight: false),
            running: true, cycle: 2.9, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let field = try XCTUnwrap(spectrum.sublayers?.first { $0.name == "field0" })
        let travel = try XCTUnwrap(field.animation(forKey: "fieldTravel") as? CABasicAnimation)
        XCTAssertGreaterThan((travel.fromValue as? CGFloat) ?? 0, (travel.toValue as? CGFloat) ?? 0)
    }

    // MARK: - Colour follows the signal, not the provider

    func test_rayColour_followsTheAttentionPriority() throws {
        func firstRayColor(_ attention: AttentionKind) throws -> RGBAColor {
            let lane = GlassSpectrumRenderer.render(
                spec(signal: ProviderVisualSignal(isRunning: true, attention: attention)),
                running: true, cycle: 2.9, restart: true
            )
            let spectrum = try XCTUnwrap(root(of: lane))
            let field = try XCTUnwrap(spectrum.sublayers?.first { $0.name == "field0" } as? CAGradientLayer)
            // The most saturated stop in the field is a tint stop of the light.
            let colors = try XCTUnwrap(field.colors as? [CGColor])
            let tint = try XCTUnwrap(colors[safe: 3] ?? colors.last)
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
            running: true, cycle: 2.9, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        let field = try XCTUnwrap(spectrum.sublayers?.first { $0.name == "field0" } as? CAGradientLayer)
        let colors = try XCTUnwrap(field.colors as? [CGColor])
        let tint = try XCTUnwrap(colors.dropFirst().first { $0.alpha > 0 })
        let components = tint.components ?? []
        XCTAssertEqual(Double(components[2]), GlassDefaults.signalLights.running.blue, accuracy: 0.02)
    }

    // MARK: - Stop / Reduce Motion

    func test_notRunning_hidesTheCurtainAndStopsEverything() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: false)),
            running: false, cycle: 2.9, restart: false
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        XCTAssertTrue(spectrum.isHidden)
        for layer in spectrum.sublayers ?? [] {
            XCTAssertNil(layer.animation(forKey: "rayBreath"))
            XCTAssertNil(layer.animation(forKey: "fieldTravel"))
        }
    }

    func test_reduceMotion_drawsAStaticCurtain() throws {
        let lane = GlassSpectrumRenderer.render(
            spec(signal: ProviderVisualSignal(isRunning: true), reduceMotion: true),
            running: true, cycle: 2.9, restart: true
        )
        let spectrum = try XCTUnwrap(root(of: lane))
        XCTAssertFalse(spectrum.isHidden, "the state stays visible, only the motion goes")
        for layer in spectrum.sublayers ?? [] {
            XCTAssertNil(layer.animation(forKey: "rayBreath"))
            XCTAssertNil(layer.animation(forKey: "fieldTravel"))
        }
    }

    func test_repeatedIdenticalRender_doesNotRestartAnimations() throws {
        let lane = CALayer()
        lane.frame = geometry.trackRect
        let spec = spec(signal: ProviderVisualSignal(isRunning: true))
        let cycle = SpectrumRhythm.cycleDuration(outputTPS: nil)
        for _ in 0..<5 {
            GlassSpectrumRenderer.update(into: lane, spec: spec, running: true, cycle: cycle, restart: false)
        }
        let spectrum = try XCTUnwrap(root(of: lane))
        XCTAssertEqual(spectrum.sublayers?.filter { $0.name?.hasPrefix("rays") == true }.count, 3)
        for layer in spectrum.sublayers ?? [] {
            XCTAssertNotNil(layer.animation(forKey: layer.name?.hasPrefix("rays") == true ? "rayBreath" : "fieldTravel"))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
