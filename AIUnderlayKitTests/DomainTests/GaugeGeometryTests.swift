import XCTest
@testable import AIUnderlayKit

final class GaugeGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 2048, height: 1152)
    private let menuBarHeight: CGFloat = 30
    // Notch: left area ends at 900, right area starts at 1148 (gap 900...1148).
    private let notch: (left: CGFloat, right: CGFloat) = (900, 1148)

    func test_dualNotch_leftAndRightAreSymmetric() {
        let gauges = GaugeLayout.layout(
            mode: .dual, anchor: .notch, singleDirection: .leadingToTrailing,
            screenFrame: screen, menuBarHeight: menuBarHeight, notchEdges: notch
        )
        let left = gauges.first { $0.side == .left }!.geometry
        let right = gauges.first { $0.side == .right }!.geometry
        XCTAssertEqual(left.fillBounds.width, right.fillBounds.width)
        XCTAssertFalse(left.growsTowardRight)
        XCTAssertTrue(right.growsTowardRight)
    }

    func test_dualNotch_trackSpansFullScreen() {
        let gauges = GaugeLayout.layout(
            mode: .dual, anchor: .notch, singleDirection: .leadingToTrailing,
            screenFrame: screen, menuBarHeight: menuBarHeight, notchEdges: notch
        )
        for g in gauges {
            XCTAssertEqual(g.geometry.trackRect.width, screen.width, "track must span full screen even in notch mode")
            XCTAssertEqual(g.geometry.trackRect.minX, screen.minX)
        }
    }

    func test_dualOuterEdge_directionsAreOppositeOfNotch() {
        let gauges = GaugeLayout.layout(
            mode: .dual, anchor: .outerEdge, singleDirection: .leadingToTrailing,
            screenFrame: screen, menuBarHeight: menuBarHeight, notchEdges: notch
        )
        let left = gauges.first { $0.side == .left }!.geometry
        let right = gauges.first { $0.side == .right }!.geometry
        XCTAssertTrue(left.growsTowardRight)
        XCTAssertFalse(right.growsTowardRight)
    }

    func test_dualNoNotch_midlineSplitWithZeroGap() {
        let gauges = GaugeLayout.layout(
            mode: .dual, anchor: .notch, singleDirection: .leadingToTrailing,
            screenFrame: screen, menuBarHeight: menuBarHeight, notchEdges: nil
        )
        let left = gauges.first { $0.side == .left }!.geometry
        let right = gauges.first { $0.side == .right }!.geometry
        XCTAssertEqual(left.fillBounds.maxX, right.fillBounds.minX, "no gap at the midline")
        XCTAssertEqual(left.fillBounds.maxX, screen.midX)
        XCTAssertEqual(left.fillBounds.width + right.fillBounds.width, screen.width)
    }

    func test_single_leadingToTrailing() {
        let gauges = GaugeLayout.layout(
            mode: .single, anchor: .notch, singleDirection: .leadingToTrailing,
            screenFrame: screen, menuBarHeight: menuBarHeight, notchEdges: nil
        )
        let g = gauges.first!.geometry
        XCTAssertTrue(g.growsTowardRight)
        XCTAssertEqual(g.fillBounds, g.trackRect)
    }

    func test_single_trailingToLeading() {
        let gauges = GaugeLayout.layout(
            mode: .single, anchor: .notch, singleDirection: .trailingToLeading,
            screenFrame: screen, menuBarHeight: menuBarHeight, notchEdges: nil
        )
        let g = gauges.first!.geometry
        XCTAssertFalse(g.growsTowardRight)
        XCTAssertEqual(g.anchorX, screen.maxX)
    }

    func test_fillRect_growsRightFromLeadingEdge() {
        let g = GaugeGeometry(
            trackRect: screen, fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
            growsTowardRight: true
        )
        let rect = g.fillRect(forLength: 400)
        XCTAssertEqual(rect.minX, 0)
        XCTAssertEqual(rect.width, 400)
    }

    func test_fillRect_growsLeftFromTrailingEdge() {
        let g = GaugeGeometry(
            trackRect: screen, fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
            growsTowardRight: false
        )
        let rect = g.fillRect(forLength: 400)
        XCTAssertEqual(rect.maxX, 1000)
        XCTAssertEqual(rect.width, 400)
    }

    func test_fillRect_clampsToBounds() {
        let g = GaugeGeometry(
            trackRect: screen, fillBounds: CGRect(x: 0, y: 0, width: 100, height: 30),
            growsTowardRight: true
        )
        XCTAssertEqual(g.fillRect(forLength: 999).width, 100)
        XCTAssertEqual(g.fillRect(forLength: -5).width, 0)
    }
}
