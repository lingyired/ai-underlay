import XCTest
import AppKit
@testable import AIUnderlayKit

@MainActor
final class BandWindowLevelTests: XCTestCase {
    func test_bandLevel_isDesktopIconPlusOne() {
        let expected = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        XCTAssertEqual(MenuBarBandWindow.bandLevelRawValue, expected)
    }

    func test_bandLevel_isBelowMainMenu() {
        XCTAssertLessThan(
            MenuBarBandWindow.bandLevelRawValue,
            Int(CGWindowLevelForKey(.mainMenuWindow))
        )
    }

    func test_window_isClickThroughAndBorderless() {
        let window = MenuBarBandWindow()
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertEqual(window.level.rawValue, MenuBarBandWindow.bandLevelRawValue)
    }
}
