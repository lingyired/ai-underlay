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
        reduceMotion: Bool = false
    ) -> LaneRenderSpec {
        LaneRenderSpec(
            providerId: "codex", geometry: geometry,
            windows: [window("w", remaining: quota), window("s", remaining: 0.5)],
            palette: .codex, baseline: nil, glass: glass, signal: signal, reduceMotion: reduceMotion
        )
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

    func test_laneZOrderIsStable() {
        let host = GlassLayerHost()
        host.update(spec(signal: ProviderVisualSignal(isRunning: true, attention: .error)))
        XCTAssertEqual(host.root.sublayers?.compactMap(\.name),
                       ["quotaGlass", "spectrum", "attention", "baseline"],
                       "baseline stays on top, glass below everything")
    }
}

private extension Array where Element == CGColor {
    subscript(safeColor index: Int) -> CGColor? {
        indices.contains(index) ? self[index] : nil
    }
}
