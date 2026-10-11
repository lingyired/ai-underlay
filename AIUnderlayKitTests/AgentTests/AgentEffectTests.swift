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

    func test_layer_addsDotWithoutChangingFill() {
        let layer = AgentEffectLayer.make(state: .waitingApproval, geometry: geometry, reduceMotion: false)
        XCTAssertNotNil(layer)
        // The effect layer spans the track but contains only the endpoint dot.
        XCTAssertEqual(layer?.frame.width, 1000)
        XCTAssertEqual(layer?.sublayers?.count, 1)
    }

    func test_reduceMotion_suppressesPulse() {
        let layer = AgentEffectLayer.make(state: .waitingApproval, geometry: geometry, reduceMotion: true)
        let dot = layer?.sublayers?.first
        XCTAssertNil(dot?.animation(forKey: "pulse"), "reduce-motion must suppress the pulse animation")
    }

    func test_running_sweepMode_drawsShimmer() {
        let layer = AgentEffectLayer.make(state: .running, geometry: geometry,
                                          reduceMotion: false, runningEffect: .sweep)
        XCTAssertNotNil(layer)
        XCTAssertEqual(layer?.sublayers?.count, 1, "running draws a single effect layer")
        let band = layer?.sublayers?.first?.sublayers?.first
        XCTAssertNotNil(band?.animation(forKey: "shimmer"))
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
        XCTAssertEqual(layer?.sublayers?.count, 1)
        XCTAssertNotNil(layer?.sublayers?.first?.animation(forKey: "pulse"))
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
        XCTAssertEqual(AppSettings.default.runningEffectColor, .green)
    }
}
