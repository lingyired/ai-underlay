import XCTest
@testable import AIUnderlayKit

@MainActor
final class SettingsStoreTests: XCTestCase {
    func test_defaultsWhenFileMissing() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).json")
        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings, .default)
    }

    func test_roundTripPersistsDisplayConfig() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SettingsStore(fileURL: url)
        store.update { settings in
            settings.layout = .single
            settings.singleDirection = .trailingToLeading
            settings.displays = [DisplayConfiguration(
                displayID: "3", isEnabled: true, layout: .dual, anchor: .notch,
                singleDirection: .leadingToTrailing, singleProviderId: "codex",
                assignments: [SideAssignment(side: .left, providerId: "codex"),
                              SideAssignment(side: .right, providerId: "claude")]
            )]
        }

        let reloaded = SettingsStore(fileURL: url)
        XCTAssertEqual(reloaded.settings.layout, .single)
        XCTAssertEqual(reloaded.settings.displays.first?.displayID, "3")
        XCTAssertEqual(reloaded.settings.displays.first?.assignments.count, 2)
    }
}
