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
}
