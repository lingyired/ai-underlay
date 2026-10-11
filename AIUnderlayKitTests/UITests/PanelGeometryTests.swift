import XCTest
@testable import AIUnderlayKit

final class PanelGeometryTests: XCTestCase {
    func test_clampedTopLeft_alignsToButtonLeft() {
        let button = CGRect(x: 500, y: 1100, width: 24, height: 24)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let topLeft = PanelGeometry.clampedTopLeft(below: button, width: 320, visibleFrame: visible)
        XCTAssertEqual(topLeft.x, 500)
        XCTAssertEqual(topLeft.y, button.minY - PanelGeometry.topGap)
    }

    func test_clampedTopLeft_clampsToRightEdge() {
        let button = CGRect(x: 1400, y: 1100, width: 24, height: 24)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let topLeft = PanelGeometry.clampedTopLeft(below: button, width: 320, visibleFrame: visible)
        // Must not run past the right edge minus the margin.
        XCTAssertLessThanOrEqual(topLeft.x + 320, 1440 - PanelGeometry.screenMargin)
    }

    func test_frame_hangsBelowTopLeft() {
        let rect = PanelGeometry.frame(topLeft: CGPoint(x: 10, y: 900), width: 320, height: 300)
        XCTAssertEqual(rect.minX, 10)
        XCTAssertEqual(rect.maxY, 900)
        XCTAssertEqual(rect.height, 300)
    }

    func test_clampedHeight_respectsMinimumAndMaximum() {
        XCTAssertEqual(PanelGeometry.clampedHeight(10, maximum: 500), PanelGeometry.minimumHeight)
        XCTAssertEqual(PanelGeometry.clampedHeight(9999, maximum: 500), 500)
        XCTAssertEqual(PanelGeometry.clampedHeight(300, maximum: 500), 300)
    }

    func test_maximumHeight_limitedByRoomBelow() {
        let topLeft = CGPoint(x: 0, y: 200)
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 900)
        // Only ~192pt of room below (200 - 0 - 8).
        XCTAssertEqual(PanelGeometry.maximumHeight(topLeft: topLeft, visibleFrame: visible), 192)
    }
}
