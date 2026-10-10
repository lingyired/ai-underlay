import XCTest
@testable import AIUnderlayKit

final class QuotaPaceTests: XCTestCase {
    private func window(
        duration: TimeInterval?, resetAt: Date?, expected: Double?
    ) -> QuotaWindow {
        QuotaWindow(
            id: "w", label: "W", kind: .weekly, durationSeconds: duration,
            remainingFraction: 0.5, resetAt: resetAt, expectedRemainingFraction: expected,
            updatedAt: nil, availability: .valid
        )
    }

    func test_prefersUpstreamExpectedRemaining() {
        let w = window(duration: 604800, resetAt: Date().addingTimeInterval(604800), expected: 0.4)
        XCTAssertEqual(QuotaPace.expectedRemaining(window: w), 0.4)
    }

    func test_derivesFromResetAtAndDuration() {
        // Period started 25% ago: expected remaining = 0.75.
        let now = Date()
        let duration: TimeInterval = 1000
        let resetAt = now.addingTimeInterval(duration * 0.75)
        let w = window(duration: duration, resetAt: resetAt, expected: nil)
        let result = QuotaPace.expectedRemaining(window: w, now: now)
        XCTAssertEqual(result ?? -1, 0.75, accuracy: 0.001)
    }

    func test_nilWhenNoCrediblePeriod() {
        let w = window(duration: nil, resetAt: nil, expected: nil)
        XCTAssertNil(QuotaPace.expectedRemaining(window: w))
    }

    func test_nilWhenDurationMissing() {
        let w = window(duration: nil, resetAt: Date().addingTimeInterval(100), expected: nil)
        XCTAssertNil(QuotaPace.expectedRemaining(window: w))
    }

    func test_clampsElapsedBeyondPeriod() {
        let now = Date()
        let w = window(duration: 100, resetAt: now.addingTimeInterval(-500), expected: nil)
        XCTAssertEqual(QuotaPace.expectedRemaining(window: w, now: now), 0)
    }

    func test_markerLength_outermostIsJustExpected() {
        let length = QuotaPace.markerLength(trackWidth: 1000, outerRemaining: [], selectedExpectedRemaining: 0.75)
        XCTAssertEqual(length ?? -1, 750, accuracy: 0.001)
    }

    func test_markerLength_projectsThroughOuterProduct() {
        // Outer actual 0.8, selected expected 0.75 -> 0.6 of track.
        let length = QuotaPace.markerLength(trackWidth: 1000, outerRemaining: [0.8], selectedExpectedRemaining: 0.75)
        XCTAssertEqual(length ?? -1, 600, accuracy: 0.001)
    }

    func test_markerLength_nilWhenOuterUnknown() {
        XCTAssertNil(QuotaPace.markerLength(trackWidth: 1000, outerRemaining: [nil], selectedExpectedRemaining: 0.75))
    }

    func test_markerLength_nilWhenExpectedUnknown() {
        XCTAssertNil(QuotaPace.markerLength(trackWidth: 1000, outerRemaining: [0.8], selectedExpectedRemaining: nil))
    }
}
