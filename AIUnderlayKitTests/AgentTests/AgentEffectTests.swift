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
}
