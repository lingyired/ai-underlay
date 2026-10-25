import XCTest
@testable import AIUnderlayKit

final class AgentSettingsLogicTests: XCTestCase {
    func test_status_installedWinsEvenWithOwnedEntries() {
        XCTAssertEqual(
            AgentSettingsLogic.hookStatus(isInstalled: true, hasManagedEntries: true),
            .installed
        )
    }

    func test_status_plainExistingFileIsNotInstalled() {
        // The file existing in any form must not imply this app's hooks.
        XCTAssertEqual(
            AgentSettingsLogic.hookStatus(isInstalled: false, hasManagedEntries: false),
            .notInstalled
        )
    }

    func test_status_outdatedOwnedEntriesNeedUpdate() {
        XCTAssertEqual(
            AgentSettingsLogic.hookStatus(isInstalled: false, hasManagedEntries: true),
            .updateRequired
        )
    }
}
