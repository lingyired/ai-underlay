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

    /// The unread fixtures exist so the green light can be looked at offline
    /// even though production keeps `unreadCount` at 0 until the completion
    /// ledger lands in main.
    func test_unreadFixturesExistForTheOfflineMatrix() {
        for key in ["agentUnread", "agentRunningUnread", "agentAllSignals"] {
            XCTAssertTrue(FixtureSnapshots.allKeys.contains(key))
            XCTAssertFalse(FixtureSnapshots.windows(for: key).isEmpty)
        }
    }

    /// The V5 preview must carry the user's exported numbers per provider:
    /// codex 82/55 and claude 67/36, so the preview shows the real nesting.
    func test_glassV5FixtureCarriesTheSelectedNumbersPerProvider() {
        XCTAssertTrue(FixtureSnapshots.allKeys.contains("glassV5"))
        let codex = FixtureSnapshots.windows(for: "glassV5", providerId: "codex")
        XCTAssertEqual(codex.map { $0.remainingFraction ?? -1 }, [0.82, 0.55])
        let claude = FixtureSnapshots.windows(for: "glassV5", providerId: "claude")
        XCTAssertEqual(claude.map { $0.remainingFraction ?? -1 }, [0.67, 0.36])
    }
}
