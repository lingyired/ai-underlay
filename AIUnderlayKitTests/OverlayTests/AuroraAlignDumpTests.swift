import XCTest
import AppKit
@testable import AIUnderlayKit

/// Opt-in dump of **whole lanes** for a side-by-side against the V5 lab's
/// Aurora Glass scene, plus a small set of render variants the fidelity pass
/// evaluates before touching production constants.
///
///     TEST_RUNNER_AURORA_ALIGN_DUMP=1 \
///     TEST_RUNNER_AURORA_ALIGN_OUTPUT="$PWD/build/aurora-align" \
///     ./Scripts/test.sh -derivedDataPath build/DerivedData \
///         -only-testing:AIUnderlayKitTests/AuroraAlignDumpTests
///
/// Unlike `V5FidelityDumpTests` (curtain only) this keeps every layer, because
/// the open question is the *whole* panel: bed, tier fills, agent tint and the
/// curtain composited together.
@MainActor
final class AuroraAlignDumpTests: XCTestCase {
    private let laneWidthPoints: CGFloat = 1712
    private let laneHeightPoints: CGFloat = 30
    private let laneScale: CGFloat = 2

    /// A variant is one post-update patch of the rendered tree. Keeping these
    /// as patches — rather than renderer branches — keeps the production code
    /// free of experimental knobs.
    private struct Variant {
        var screenTint = false
        var screenTintAlpha = 1.0
        var v5Fill = false
        var scrimRemoved = false
        /// Reproduces the pre-fix scrim exactly (black, `[0.18, 1]`, 0.45) so
        /// the before/after delta below is measured in one run, not across two
        /// builds. Evidence only — production no longer emits this.
        var legacyScrim = false
        /// Reproduces the pre-fix tier alphas (`0.48 + 0.34·rank` …).
        var legacyFill = false
        /// Drops the production `screenBlendMode` filter, for attribution.
        var noScreenBlend = false
    }

    private func window(_ id: String, _ kind: QuotaWindowKind, _ remaining: Double) -> QuotaWindow {
        QuotaWindow(
            id: id, label: id, kind: kind, durationSeconds: kind == .weekly ? 604800 : 18000,
            remainingFraction: remaining, resetAt: nil,
            expectedRemainingFraction: nil, updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            availability: .valid
        )
    }

    private func makeLane(
        themeHex: String,
        themeStrength: Double,
        quotaOpacity: Double,
        travels: Bool,
        running: Bool,
        windows: [QuotaWindow],
        variant: Variant = Variant()
    ) -> CALayer {
        let geometry = GaugeGeometry(
            trackRect: CGRect(x: 0, y: 0, width: laneWidthPoints, height: laneHeightPoints),
            fillBounds: CGRect(x: 0, y: 0, width: laneWidthPoints, height: laneHeightPoints),
            growsTowardRight: true
        )
        var glass = ResolvedGlassTheme.default(providerId: "codex")
        glass.agentThemeColor = RGBAColor(hex: themeHex) ?? glass.agentThemeColor
        glass.material.agentThemeStrength = themeStrength
        glass.material.quotaOpacity = quotaOpacity
        let spec = LaneRenderSpec(
            providerId: "codex",
            geometry: geometry,
            windows: windows,
            palette: .for(providerId: "codex"),
            glass: glass,
            signal: running ? AgentSignals(activeCount: 1).visualSignal : nil,
            showsTravelingLight: travels
        )
        let lane = CALayer()
        lane.frame = spec.geometry.trackRect
        lane.masksToBounds = true
        lane.contentsScale = laneScale
        GlassQuotaRenderer.update(into: lane, spec: spec)
        GlassSpectrumRenderer.update(
            into: lane, spec: spec, running: running,
            cycle: SpectrumRhythm.cycleDuration(
                outputTPS: spec.signal?.observedOutputTPS, floorHz: spec.spectrumFloorHz
            ),
            restart: true
        )
        apply(variant, to: lane)
        LayerSlot.reconcileLane(lane)
        if running {
            GlassSpectrumRenderer.applySampledPhase(into: lane, spec: spec, phase: 0.35)
        }
        return lane
    }

    private func apply(_ variant: Variant, to lane: CALayer) {
        if variant.noScreenBlend {
            walkTint(lane) { $0.compositingFilter = nil }
        }
        if variant.screenTint {
            // V5's `mix-blend-mode: screen` on `.glass-tint` / `.ambient`.
            walkTint(lane) { layer in
                guard layer.name == "tintBloom" || layer.name == "tintHalo" else { return }
                layer.compositingFilter = "screenBlendMode"
                if variant.screenTintAlpha != 1 {
                    layer.opacity *= Float(variant.screenTintAlpha)
                }
            }
        }
        if variant.scrimRemoved, let scrim = lane.sublayers?
            .first(where: { $0.name == "scrim" }) as? CAGradientLayer {
            scrim.colors = [
                CGColor(red: 0, green: 0, blue: 0, alpha: 0),
                CGColor(red: 0, green: 0, blue: 0, alpha: 0),
            ]
        }
        if variant.legacyScrim, let scrim = lane.sublayers?
            .first(where: { $0.name == "scrim" }) as? CAGradientLayer {
            scrim.colors = [
                CGColor(red: 0, green: 0, blue: 0, alpha: 0),
                CGColor(red: 0, green: 0, blue: 0, alpha: 0.45),
            ]
            scrim.locations = [0.18, 1]
        }
        if variant.legacyFill, let fills = lane.sublayers?
            .first(where: { $0.name == "quotaGlass" })?
            .sublayers?.first(where: { $0.name == "fills" }) {
            let tiers = ProviderPalette.codex.tierColors(forWindowCount: 2)
            let layers = (fills.sublayers ?? []).compactMap { $0 as? CAGradientLayer }
            for (index, gradient) in layers.enumerated() {
                let isInner = index == layers.count - 1
                let rank = isInner ? 1.0 : 0.0
                gradient.colors = [
                    tiers[index].withAlpha(0.48 + 0.34 * rank).cgColor,
                    tiers[index].withAlpha(0.34 + 0.46 * rank).cgColor,
                    tiers[index].scaled(by: 0.55).withAlpha(0.18 + 0.26 * rank).cgColor,
                ]
                gradient.locations = [0, 0.55, 1]
            }
        }
        if variant.v5Fill, let fills = lane.sublayers?
            .first(where: { $0.name == "quotaGlass" })?
            .sublayers?.first(where: { $0.name == "fills" }) {
            // V5's own tier alphas (`rgba(provider,.46)` body, `.88` inner) with
            // the provider hue kept unscaled. No white top stop (551e647).
            let hue = ProviderPalette.for(providerId: "codex").inner
            let layers = (fills.sublayers ?? []).compactMap { $0 as? CAGradientLayer }
            for (index, gradient) in layers.enumerated() {
                let isInner = index == layers.count - 1
                let alphas: [Double] = isInner ? [0.62, 0.68, 0.30] : [0.30, 0.46, 0.20]
                gradient.colors = alphas.map { hue.withAlpha($0).cgColor }
            }
        }
    }

    private func walkTint(_ lane: CALayer, _ body: (CALayer) -> Void) {
        guard let tint = lane.sublayers?
            .first(where: { $0.name == "quotaGlass" })?
            .sublayers?.first(where: { $0.name == "tint" }) else { return }
        func walk(_ layer: CALayer) {
            body(layer)
            layer.sublayers?.forEach(walk)
        }
        walk(tint)
    }

    private func rasterise(_ layer: CALayer) throws -> NSBitmapImageRep {
        let width = Int((layer.bounds.width * laneScale).rounded())
        let height = Int((layer.bounds.height * laneScale).rounded())
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = NSSize(width: layer.bounds.width, height: layer.bounds.height)
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        layer.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    func test_dumpAuroraAlignLanesWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["AURORA_ALIGN_DUMP"] == "1" else {
            throw XCTSkip("set AURORA_ALIGN_DUMP=1 to write the aurora-alignment lane dumps")
        }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURORA_ALIGN_OUTPUT"]
            ?? "build/aurora-align", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        // The live app's own numbers, read from the running instance on
        // 2026-10-16: single codex lane, weekly ~98.7% with a ~60.8% nested
        // 5h window, agent theme #007DAF, travelling light off.
        let live = [window("w", .weekly, 0.987), window("s", .session, 0.608)]
        // The lab's own exported fixture, for a same-fixture comparison with
        // the browser scene.
        let lab = [window("w", .weekly, 0.82), window("s", .session, 0.55)]

        func liveLane(_ variant: Variant = Variant(), travels: Bool = false, running: Bool = true) -> CALayer {
            makeLane(themeHex: "#007DAF", themeStrength: 1, quotaOpacity: 1,
                     travels: travels, running: running, windows: live, variant: variant)
        }

        let variants: [(String, CALayer)] = [
            ("live-lane", liveLane()),
            ("live-lane-notint", makeLane(themeHex: "#007DAF", themeStrength: 0, quotaOpacity: 1,
                                          travels: false, running: true, windows: live)),
            ("live-lane-travels", liveLane(travels: true)),
            ("live-quota-only", liveLane(running: false)),
            ("live-curtain-only", makeLane(themeHex: "#007DAF", themeStrength: 0, quotaOpacity: 0,
                                           travels: false, running: true, windows: live)),
            ("lab-lane", makeLane(themeHex: "#62AC96", themeStrength: 1, quotaOpacity: 1,
                                  travels: false, running: true, windows: lab)),
            ("lab-curtain-only", makeLane(themeHex: "#62AC96", themeStrength: 0, quotaOpacity: 0,
                                          travels: false, running: true, windows: lab)),
            ("cand-screen", liveLane(Variant(screenTint: true))),
            ("cand-screen70", liveLane(Variant(screenTint: true, screenTintAlpha: 0.7))),
            ("cand-v5fill", liveLane(Variant(v5Fill: true))),
            ("cand-v5fill-screen", liveLane(Variant(screenTint: true, v5Fill: true))),
            // The measured before/after pair: `before` is the pre-fix scrim and
            // tier alphas re-applied over the current renderer.
            ("before-3e51f0f", liveLane(Variant(legacyScrim: true, legacyFill: true))),
            // Attribution: one factor at a time, so the report can say which
            // change moved which number.
            ("attr-legacy-scrim-only", liveLane(Variant(legacyScrim: true))),
            ("attr-legacy-fill-only", liveLane(Variant(legacyFill: true))),
            ("attr-no-screen-blend", liveLane(Variant(noScreenBlend: true))),
        ]

        for (name, layer) in variants {
            let rep = try rasterise(layer)
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("\(name).png"))
        }
    }
}
