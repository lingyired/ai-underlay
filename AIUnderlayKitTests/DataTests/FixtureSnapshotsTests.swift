import XCTest
@testable import AIUnderlayKit

/// The offline preview picker lists `allKeys`, and every one of them must draw
/// something — an empty fixture would look like a broken app, not a preview.
final class FixtureSnapshotsTests: XCTestCase {
    func test_everyAdvertisedFixtureDrawsWindows() {
        for key in FixtureSnapshots.allKeys {
            XCTAssertFalse(FixtureSnapshots.windows(for: key).isEmpty,
                           "fixture \(key) must render a bar")
        }
    }

    func test_agentFixturesCoverRunningWaitingAndFailure() {
        for key in ["agentRunning", "agentWaiting", "agentError"] {
            XCTAssertTrue(FixtureSnapshots.allKeys.contains(key))
            XCTAssertFalse(FixtureSnapshots.windows(for: key).isEmpty)
        }
    }

    /// The combinations from the §5.2 matrix need to be look-at-able offline.
    func test_agentCombinationFixturesExist() {
        for key in ["agentRunningWaiting", "agentRunningError"] {
            XCTAssertTrue(FixtureSnapshots.allKeys.contains(key))
            XCTAssertFalse(FixtureSnapshots.windows(for: key).isEmpty)
        }
    }
}
