import XCTest
@testable import AIUnderlayKit

@MainActor
final class SettingsStoreTests: XCTestCase {
    func test_tolerantDecode_olderFileWithoutNewKeys() throws {
        // A file written before `displayedProviders` existed must still decode,
        // keeping its known values and defaulting the rest — not reset wholesale.
        let json = """
        {"layout":"single","anchor":"notch","showBaseline":false,"previewFixture":"full"}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.layout, .single)
        XCTAssertEqual(settings.anchor, .notch)
        XCTAssertFalse(settings.showBaseline)
        XCTAssertEqual(settings.previewFixture, "full")
        // Absent deprecated key defaults to empty; it no longer affects display.
        XCTAssertTrue(settings.displayedProviders.isEmpty)
        XCTAssertEqual(settings.singleDirection, AppSettings.default.singleDirection)
    }

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

    // MARK: - Legacy visual choices migrate instead of resetting

    func test_legacyRunningEffectNone_becomesReduceMotion() throws {
        // The old `none` meant "don't animate my bar". Its successor is the
        // Reduce Motion switch, which keeps the static colours and the alert
        // ribbon the old option also left visible.
        let json = #"{"layout":"single","anchor":"notch","runningEffect":"none","overlayEnabled":false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.reduceMotion)
        XCTAssertFalse(settings.overlayEnabled, "migration must not reset unrelated fields")
        XCTAssertEqual(settings.layout, .single)
        XCTAssertEqual(settings.anchor, .notch)
    }

    func test_legacyRunningEffectColor_becomesTheRunningSignalLight() throws {
        let json = #"{"runningEffect":"breathing","runningEffectColor":"orange"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.appearance.signalColors[SignalColorKey.running.rawValue], "#FFA64D")
        XCTAssertFalse(settings.reduceMotion, "any other effect migrates to the single engine")
    }

    func test_legacyRunningEffectColor_neverOverwritesAUserChoice() throws {
        let json = #"""
        {"runningEffectColor":"green","appearance":{"signalColors":{"running":"#123456"}}}
        """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.appearance.signalColors[SignalColorKey.running.rawValue], "#123456")
    }

    func test_unknownLegacyValuesNeverFailTheWholeFile() throws {
        let json = #"{"runningEffect":"hyperspace","runningEffectColor":"chartreuse","showBaseline":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertFalse(settings.reduceMotion)
        XCTAssertNil(settings.appearance.signalColors[SignalColorKey.running.rawValue])
        XCTAssertTrue(settings.showBaseline)
    }

    func test_removedVisualKeysAreNotRewrittenOnSave() throws {
        let json = #"{"runningEffect":"none","runningEffectColor":"orange"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        let saved = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        XCTAssertFalse(saved.contains("runningEffect"))
        XCTAssertTrue(saved.contains("reduceMotion"))
    }

    func test_appearanceOverridesSurviveARoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SettingsStore(fileURL: url)
        store.update { settings in
            settings.appearance = GlassAppearance(
                agentThemeColors: ["codex": "#62AC96"],
                quotaBaseColors: ["codex": "#00FF00"],
                signalColors: ["error": "#FF0000", "running": "#D9EEFF"],
                material: GlassMaterialOverrides(grain: 0.4)
            )
        }

        let reloaded = SettingsStore(fileURL: url)
        XCTAssertEqual(reloaded.settings.appearance.quotaBaseColors["codex"], "#00FF00")
        XCTAssertEqual(reloaded.settings.appearance.signalColors["error"], "#FF0000")
        XCTAssertEqual(reloaded.settings.appearance.material?.grain, 0.4)
    }
}
