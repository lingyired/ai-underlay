import XCTest
import AppKit
@testable import AIUnderlayKit

@MainActor
final class GaugeLayerRendererTests: XCTestCase {
    private let renderer = GaugeLayerRenderer()
    private let geometry = GaugeGeometry(
        trackRect: CGRect(x: 0, y: 0, width: 1000, height: 30),
        fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
        growsTowardRight: true
    )

    private func window(_ id: String, remaining: Double?, duration: TimeInterval) -> QuotaWindow {
        QuotaWindow(
            id: id, label: id, kind: .custom, durationSeconds: duration,
            remainingFraction: remaining, resetAt: nil, expectedRemainingFraction: nil,
            updatedAt: nil, availability: remaining == nil ? .unavailable : .valid
        )
    }

    func test_layerCount_trackPlusOneFillPerKnownWindow() {
        let windows = [window("w", remaining: 0.8, duration: 604800),
                       window("s", remaining: 0.5, duration: 18000)]
        let container = renderer.render(windows: windows, geometry: geometry, palette: .codex, baseline: nil)
        // 1 track + 2 fills, no baseline.
        XCTAssertEqual(container.sublayers?.count, 3)
    }

    func test_unknownWindowDrawsNoFill() {
        let windows = [window("w", remaining: 0.8, duration: 604800),
                       window("s", remaining: nil, duration: 18000)]
        let container = renderer.render(windows: windows, geometry: geometry, palette: .codex, baseline: nil)
        // track + 1 fill only.
        XCTAssertEqual(container.sublayers?.count, 2)
    }

    func test_outerFillContainsInnerFill() {
        let windows = [window("w", remaining: 0.8, duration: 604800),
                       window("s", remaining: 0.5, duration: 18000)]
        let container = renderer.render(windows: windows, geometry: geometry, palette: .codex, baseline: nil)
        let fills = Array(container.sublayers!.dropFirst())  // drop track
        XCTAssertEqual(fills[0].frame.width, 800, accuracy: 0.001)
        XCTAssertEqual(fills[1].frame.width, 400, accuracy: 0.001)
        XCTAssertTrue(fills[0].frame.contains(fills[1].frame), "outer fill must contain inner fill")
    }

    func test_trackSpansFullWidthAndIsDark() {
        let container = renderer.render(windows: [], geometry: geometry, palette: .codex, baseline: nil)
        let track = container.sublayers!.first!
        XCTAssertEqual(track.frame.width, 1000)
        let color = track.backgroundColor!
        let alpha = color.alpha
        XCTAssertEqual(Double(alpha), 0.38, accuracy: 0.01)
    }

    func test_baselineMarker_projectsWithOuterProduct() {
        let windows = [window("w", remaining: 0.8, duration: 604800),
                       window("s", remaining: 0.5, duration: 18000)]
        let spec = BaselineSpec(selectedWindowIndex: 1, expectedRemainingFraction: 0.75)
        let container = renderer.render(windows: windows, geometry: geometry, palette: .codex, baseline: spec)
        // track + 2 fills + 1 marker
        XCTAssertEqual(container.sublayers?.count, 4)
        let marker = container.sublayers!.last!
        // markerLength = 1000 * 0.8 * 0.75 = 600 -> x ~ 599 (width 2, centered).
        XCTAssertEqual(marker.frame.midX, 600, accuracy: 1.0)
    }

    func test_subVisibleNonZeroFill_addsEndCap() {
        let windows = [window("w", remaining: 0.0005, duration: 604800)]  // 0.5pt at 1000 width
        let container = renderer.render(windows: windows, geometry: geometry, palette: .codex, baseline: nil)
        let fill = container.sublayers![1]
        XCTAssertEqual(fill.frame.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(fill.sublayers?.count, 1, "expected an end-cap sublayer")
    }

    func test_zeroFillHasNoEndCap() {
        let windows = [window("w", remaining: 0, duration: 604800)]
        let container = renderer.render(windows: windows, geometry: geometry, palette: .codex, baseline: nil)
        let fill = container.sublayers![1]
        XCTAssertEqual(fill.frame.width, 0)
        XCTAssertNil(fill.sublayers)
    }
}
