import XCTest
@testable import AIUnderlayKit

final class NestedGaugeTests: XCTestCase {
    func test_threeWindows() {
        XCTAssertEqual(
            NestedGauge.nestedLengths(trackWidth: 100, remaining: [0.8, 0.6, 0.25]),
            [80, 48, 12]
        )
    }

    func test_twoWindows() {
        XCTAssertEqual(
            NestedGauge.nestedLengths(trackWidth: 100, remaining: [0.6, 0.25]),
            [60, 15]
        )
    }

    func test_fullAndEmpty() {
        XCTAssertEqual(NestedGauge.nestedLengths(trackWidth: 100, remaining: [1, 1]), [100, 100])
        XCTAssertEqual(NestedGauge.nestedLengths(trackWidth: 100, remaining: [0, 0.5]), [0, 0])
    }

    func test_nilBreaksChain() {
        let r = NestedGauge.nestedLengths(trackWidth: 100, remaining: [0.8, nil, 0.25])
        XCTAssertEqual(r[0], 80)
        XCTAssertTrue(r[1].isNaN)
        XCTAssertTrue(r[2].isNaN)
    }

    func test_nanAndInfinityBreakChain() {
        let r = NestedGauge.nestedLengths(trackWidth: 100, remaining: [.nan, 0.5])
        XCTAssertTrue(r[0].isNaN)
        XCTAssertTrue(r[1].isNaN)

        let r2 = NestedGauge.nestedLengths(trackWidth: 100, remaining: [.infinity, 0.5])
        XCTAssertTrue(r2[0].isNaN)
        XCTAssertTrue(r2[1].isNaN)
    }

    func test_outerMissingDoesNotAssumeFull() {
        // The critical rule: a missing outer window must not be treated as 100%.
        let r = NestedGauge.nestedLengths(trackWidth: 100, remaining: [nil, 0.5])
        XCTAssertFalse(r[1] == 50, "inner must not be computed from an assumed-full outer")
        XCTAssertTrue(r[1].isNaN)
    }

    func test_zeroWidth() {
        XCTAssertEqual(NestedGauge.nestedLengths(trackWidth: 0, remaining: [0.8, 0.6]), [0, 0])
    }

    func test_emptyInput() {
        XCTAssertEqual(NestedGauge.nestedLengths(trackWidth: 100, remaining: []), [])
    }
}
