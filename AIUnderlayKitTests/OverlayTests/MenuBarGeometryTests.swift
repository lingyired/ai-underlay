import XCTest
import AppKit
@testable import AIUnderlayKit

final class MenuBarGeometryTests: XCTestCase {
    func test_height_matchesByXAndWidth() {
        let quartz = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let bars = [
            CGRect(x: 0, y: 0, width: 1728, height: 33),
            CGRect(x: 2048, y: 0, width: 2560, height: 30),
        ]
        XCTAssertEqual(
            MenuBarGeometry.menuBarHeight(forQuartzFrame: quartz, menuBarWindowBounds: bars),
            33
        )
    }

    func test_height_picksMatchingDisplayNotGlobalMax() {
        let quartz = CGRect(x: 2048, y: 0, width: 2560, height: 1440)
        let bars = [
            CGRect(x: 0, y: 0, width: 1728, height: 33),
            CGRect(x: 2048, y: 0, width: 2560, height: 30),
        ]
        XCTAssertEqual(
            MenuBarGeometry.menuBarHeight(forQuartzFrame: quartz, menuBarWindowBounds: bars),
            30
        )
    }

    func test_height_nilWhenNoMatch() {
        XCTAssertNil(MenuBarGeometry.menuBarHeight(
            forQuartzFrame: CGRect(x: 9, y: 0, width: 1, height: 1),
            menuBarWindowBounds: []
        ))
    }

    func test_height_floorsTinyValueToMinimum() {
        let bars = [CGRect(x: 0, y: 0, width: 100, height: 3)]
        XCTAssertEqual(
            MenuBarGeometry.menuBarHeight(
                forQuartzFrame: CGRect(x: 0, y: 0, width: 100, height: 10),
                menuBarWindowBounds: bars
            ),
            MenuBarGeometry.minimumMenuBarHeight
        )
    }

    func test_quartzFrame_flipsYForPrimaryDisplay() {
        let display = CGRect(x: 0, y: 0, width: 2048, height: 1152)
        let quartz = MenuBarGeometry.quartzFrame(for: display, primaryMaxY: 1152)
        XCTAssertEqual(quartz, CGRect(x: 0, y: 0, width: 2048, height: 1152))
    }

    func test_quartzFrame_flipsYForDisplayAbovePrimary() {
        // A display whose AppKit origin sits at y=1152 (stacked above primary).
        let display = CGRect(x: 0, y: 1152, width: 2048, height: 1152)
        let quartz = MenuBarGeometry.quartzFrame(for: display, primaryMaxY: 1152)
        XCTAssertEqual(quartz.minY, -1152)
    }

    func test_notchEdges_nilWithoutNotch() throws {
        // The primary display on this machine has no notch; nil is the
        // degradation path that must yield a midline split downstream.
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("no screen available")
        }
        if screen.auxiliaryTopLeftArea == nil || screen.auxiliaryTopRightArea == nil {
            XCTAssertNil(MenuBarGeometry.notchEdges(for: screen))
        }
    }
}
