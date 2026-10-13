import XCTest
import AppKit
@testable import AIUnderlayKit

@MainActor
final class AgentEffectTests: XCTestCase {
    private let geometry = GaugeGeometry(
        trackRect: CGRect(x: 0, y: 0, width: 1000, height: 30),
        fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
        growsTowardRight: true
    )

    func test_style_nilForIdleAndUnknown() {
        XCTAssertNil(AgentEffectStyle.style(for: nil))
        XCTAssertNil(AgentEffectStyle.style(for: .idle))
        XCTAssertNil(AgentEffectStyle.style(for: .unknown))
        XCTAssertNil(AgentEffectStyle.style(for: .reconnecting))
    }

    func test_style_presentForObservableStates() {
        XCTAssertNotNil(AgentEffectStyle.style(for: .running))
        XCTAssertNotNil(AgentEffectStyle.style(for: .waitingApproval))
        XCTAssertNotNil(AgentEffectStyle.style(for: .waitingInput))
        XCTAssertNotNil(AgentEffectStyle.style(for: .completed))
        XCTAssertNotNil(AgentEffectStyle.style(for: .error))
    }

    func test_layer_nilForUnknown() {
        XCTAssertNil(AgentEffectLayer.make(state: .unknown, geometry: geometry, reduceMotion: false))
    }

    func test_layer_waitsWithFullWidthWash() {
        let layer = AgentEffectLayer.make(state: .waitingApproval, geometry: geometry, reduceMotion: false)
        XCTAssertNotNil(layer)
        // A "needs you" state is a full-width breathing wash — no endpoint dot
        // crowding the menu bar's left edge — plus the yellow edge highlights.
        XCTAssertEqual(layer?.frame.width, 1000)
        XCTAssertEqual(layer?.sublayers?.count, 2)
        XCTAssertNotNil(layer?.sublayers?.first?.sublayers?.first?.animation(forKey: "breathe"))
    }

    func test_waiting_drawsYellowEdgeHighlights() {
        let layer = AgentEffectLayer.make(state: .waitingInput, geometry: geometry, reduceMotion: false)
        let borders = layer?.sublayers?.last
        XCTAssertEqual(borders?.sublayers?.count, 2, "one edge at the top, one at the bottom")
        XCTAssertEqual(borders?.sublayers?.first?.frame.minY, geometry.fillBounds.minY)
        XCTAssertEqual(borders?.sublayers?.first?.frame.width, geometry.fillBounds.width)
        XCTAssertEqual(borders?.sublayers?.last?.frame.maxY, geometry.fillBounds.maxY)
    }

    func test_error_drawsFailureBorder() {
        let layer = AgentEffectLayer.make(state: .error, geometry: geometry, reduceMotion: false)
        XCTAssertEqual(layer?.sublayers?.count, 2, "wash + failure border")
        XCTAssertEqual(AgentEffectStyle.style(for: .error)?.borderColor, AgentEffectStyle.failureBorder)
        XCTAssertEqual(AgentEffectStyle.style(for: .waitingInput)?.borderColor, AgentEffectStyle.attentionBorder)
        XCTAssertNil(AgentEffectStyle.style(for: .running)?.borderColor)
        XCTAssertNil(AgentEffectStyle.style(for: .completed)?.borderColor)
    }

    func test_reduceMotion_suppressesPulse() {
        let layer = AgentEffectLayer.make(state: .waitingApproval, geometry: geometry, reduceMotion: true)
        let wash = layer?.sublayers?.first
        XCTAssertNil(wash?.sublayers?.first?.animation(forKey: "breathe"),
                     "reduce-motion must suppress the breathe animation")
    }

    func test_running_sweepMode_drawsShimmer() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry,
                                          reduceMotion: false, runningEffect: .sweep)
        XCTAssertNotNil(layer)
        XCTAssertEqual(layer?.sublayers?.count, 1, "running draws a single effect layer")
        let band = layer?.sublayers?.first?.sublayers?.first
        XCTAssertNotNil(band?.animation(forKey: "shimmer"))
        XCTAssertEqual(band?.animation(forKey: "shimmer")?.repeatCount, .infinity)
        XCTAssertNil(band?.animation(forKey: "shimmerFade"))
    }

    func test_completed_sweepPlaysOnce() {
        let layer = AgentEffectLayer.make(state: .completed, geometry: geometry, reduceMotion: false)
        let band = layer?.sublayers?.first?.sublayers?.first
        let animation = band?.animation(forKey: "shimmer") as? CABasicAnimation
        XCTAssertNotNil(animation)
        XCTAssertEqual(animation?.repeatCount, 1)
        XCTAssertEqual(animation?.fillMode, .forwards)
        XCTAssertFalse(animation?.isRemovedOnCompletion ?? true)
        let fade = band?.animation(forKey: "shimmerFade") as? CAKeyframeAnimation
        XCTAssertNotNil(fade)
        XCTAssertEqual((fade?.values?.last as? NSNumber)?.doubleValue, 0)
    }

    func test_running_sweepReduceMotion_static() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry,
                                          reduceMotion: true, runningEffect: .sweep)
        let band = layer?.sublayers?.first?.sublayers?.first
        XCTAssertNotNil(band, "the shimmer band still exists without motion")
        XCTAssertNil(band?.animation(forKey: "shimmer"), "reduce-motion suppresses the sweep")
    }

    func test_shimmer_isClippedToTrack() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry,
                                          reduceMotion: false, runningEffect: .sweep)
        let clip = layer?.sublayers?.first
        XCTAssertEqual(clip?.frame, geometry.trackRect)
        XCTAssertTrue(clip?.masksToBounds ?? false, "the sweep must not leave the fill area")
    }

    func test_style_runningIsSweepNotPulse() {
        let style = AgentEffectStyle.style(for: .running)
        XCTAssertEqual(style?.sweep, true)
        XCTAssertEqual(style?.pulse, false)
    }

    func test_running_breathingMode() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry,
                                          reduceMotion: false, runningEffect: .breathing)
        let glow = layer?.sublayers?.first?.sublayers?.first
        XCTAssertNotNil(glow?.animation(forKey: "breathe"), "breathing animates opacity")
    }

    func test_running_sweepMode() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry,
                                          reduceMotion: false, runningEffect: .sweep)
        let band = layer?.sublayers?.first?.sublayers?.first
        XCTAssertNotNil(band?.animation(forKey: "shimmer"))
    }

    func test_running_dotMode() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry,
                                          reduceMotion: false, runningEffect: .dot)
        let container = layer?.sublayers?.first
        XCTAssertEqual(container?.sublayers?.count, 1)
        XCTAssertNotNil(container?.sublayers?.first?.animation(forKey: "pulse"))
    }

    func test_running_spectrumMode_drawsBarsGrowingFromTheLowerEdge() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry, reduceMotion: false,
                                          runningEffect: .spectrum)
        let container = layer?.sublayers?.first
        XCTAssertTrue(container?.masksToBounds ?? false, "bars never leave the strip")
        XCTAssertEqual(container?.frame, geometry.trackRect)

        let bars = container?.sublayers ?? []
        XCTAssertGreaterThan(bars.count, 1)
        for bar in bars {
            XCTAssertEqual(bar.position.y, geometry.fillBounds.minY, "bars sit on the lower edge")
            XCTAssertEqual(bar.anchorPoint, CGPoint(x: 0.5, y: 0), "they grow upward")
            XCTAssertEqual(bar.bounds.width, SpectrumRhythm.barWidth)
            let animation = bar.animation(forKey: "spectrum") as? CAKeyframeAnimation
            XCTAssertNotNil(animation)
            XCTAssertEqual(animation?.repeatCount, .infinity)
            XCTAssertEqual(animation?.duration, SpectrumRhythm.cycleDuration(outputTPS: nil))
        }
    }

    func test_running_spectrumReduceMotion_isStatic() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry, reduceMotion: true,
                                          runningEffect: .spectrum)
        let bars = layer?.sublayers?.first?.sublayers ?? []
        XCTAssertFalse(bars.isEmpty)
        for bar in bars {
            XCTAssertNil(bar.animation(forKey: "spectrum"))
            XCTAssertLessThanOrEqual(bar.bounds.height, geometry.fillBounds.height)
            XCTAssertGreaterThan(bar.bounds.height, 0)
        }
    }

    func test_running_spectrumHonorsTheConfiguredColor() {
        let color = RGBAColor(red: 0.2, green: 0.4, blue: 0.9)
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry, reduceMotion: false,
                                          runningEffect: .spectrum, runningColor: color)
        let bar = layer?.sublayers?.first?.sublayers?.first
        let components = bar?.backgroundColor?.components ?? []
        XCTAssertEqual(components.count, 4)
        XCTAssertEqual(components[0], 0.2, accuracy: 0.001)
        XCTAssertEqual(components[2], 0.9, accuracy: 0.001)
    }

    func test_running_noneMode_drawsNothing() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry,
                                          reduceMotion: false, runningEffect: .none)
        XCTAssertNil(layer)
    }

    func test_runningEffect_defaultIsBreathing() {
        XCTAssertEqual(AppSettings.default.runningEffect, .breathing)
    }

    func test_stateColorsAreDistinct() {
        // Color must encode state, so no two states share a color.
        let states: [AgentState] = [.running, .waitingInput, .waitingApproval, .completed, .error]
        let colors = states.map { AgentEffectStyle.defaultColor(for: $0) }
        XCTAssertEqual(Set(colors.map { "\($0.red),\($0.green),\($0.blue)" }).count, states.count)
    }

    func test_runningColorOverride() {
        let green = AgentEffectStyle.defaultColor(for: .running)
        XCTAssertGreaterThan(green.green, green.red, "running default is green-dominant")
        let custom = RGBAColor(red: 0.1, green: 0.2, blue: 0.9)
        let style = AgentEffectStyle.style(for: .running, runningColor: custom)
        XCTAssertEqual(style?.color, custom)
    }

    func test_waitingColorIsNotOverridable() {
        // Only the running color is configurable; waiting keeps its amber/orange.
        let style = AgentEffectStyle.style(for: .waitingApproval, runningColor: RGBAColor(red: 0, green: 1, blue: 0))
        XCTAssertEqual(style?.color, AgentEffectStyle.defaultColor(for: .waitingApproval))
    }

    func test_runningColorDefaultIsGreen() {
        // Default defers to the theme; with no theme installed that is the
        // built-in green, so the out-of-the-box look is unchanged.
        XCTAssertEqual(AppSettings.default.runningEffectColor, .theme)
        XCTAssertEqual(AgentEffectStyle.style(for: .running, runningColor: nil, theme: nil)?.color,
                       AgentEffectStyle.defaultColor(for: .running))
    }
}
