import XCTest
@testable import AIUnderlayKit

final class BandWatchdogTests: XCTestCase {
    func test_needsReassert_trueWhenMissing() {
        XCTAssertTrue(BandWatchdog.needsReassert(managedBands: 2, onScreenBands: 1))
    }

    func test_needsReassert_falseWhenEqual() {
        XCTAssertFalse(BandWatchdog.needsReassert(managedBands: 2, onScreenBands: 2))
    }

    func test_needsReassert_falseWhenMoreOnScreen() {
        XCTAssertFalse(BandWatchdog.needsReassert(managedBands: 1, onScreenBands: 3))
    }

    func test_needsReassert_falseWhenNoManaged() {
        XCTAssertFalse(BandWatchdog.needsReassert(managedBands: 0, onScreenBands: 0))
    }
}
