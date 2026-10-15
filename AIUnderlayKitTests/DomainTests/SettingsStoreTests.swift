import XCTest
import Combine
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

    // MARK: - Baseline motion tempo

    func test_motionFloor_survivesARoundTrip_andDefaultsToNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = SettingsStore(fileURL: url)
        XCTAssertNil(store.settings.motionFloorFrequencyHz, "unset means the built-in floor")

        store.update { $0.motionFloorFrequencyHz = 0.5 }
        XCTAssertEqual(SettingsStore(fileURL: url).settings.motionFloorFrequencyHz, 0.5)

        // Clearing the setting must remove the key, not pin the old value.
        store.update { $0.motionFloorFrequencyHz = nil }
        let saved = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertFalse(saved.contains("motionFloorFrequencyHz"))
        XCTAssertNil(SettingsStore(fileURL: url).settings.motionFloorFrequencyHz)
    }

    func test_motionFloor_olderFilesDecodeWithoutIt() throws {
        let json = #"{"layout":"single","reduceMotion":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.motionFloorFrequencyHz)
        XCTAssertTrue(settings.reduceMotion, "an unrelated field must survive")
    }

    func test_sweepToggles_defaultToOnAndSurviveARoundTrip() throws {
        // The sweeps are opt-out: an older file (or a fresh install) must keep
        // the full V5 look rather than silently turning motion off.
        let legacy = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"layout":"single"}"#.utf8)
        )
        XCTAssertTrue(legacy.showTravelingLight)
        XCTAssertTrue(legacy.showAttentionSweep)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)
        store.update {
            $0.showTravelingLight = false
            $0.showAttentionSweep = false
        }
        let reloaded = SettingsStore(fileURL: url).settings
        XCTAssertFalse(reloaded.showTravelingLight)
        XCTAssertFalse(reloaded.showAttentionSweep)
    }

    func test_sweepToggles_changeEmitsTheSettledValue() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)

        var seen: [Bool] = []
        let cancellable = store.changes.sink { seen.append($0.showTravelingLight) }
        defer { cancellable.cancel() }

        store.update { $0.showTravelingLight = false }
        store.update { $0.showTravelingLight = true }

        XCTAssertEqual(seen, [false, true], "the overlay must hear the new value, not the old one")
    }

    // MARK: - Change notifications must carry the settled value

    func test_changesPublisher_emitsTheValueThatWasJustApplied() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)

        var seen: [LayoutMode] = []
        let cancellable = store.changes.sink { seen.append($0.layout) }
        defer { cancellable.cancel() }

        store.update { $0.layout = .dual }
        store.update { $0.layout = .single }

        XCTAssertEqual(seen, [.dual, .single],
                       "each toggle must report itself, not the previous value")
    }

    /// The regression behind the "settings feel delayed" report: a sink that
    /// re-read `store.settings` while subscribed to `$settings` saw the *old*
    /// value, because `@Published` fires from `willSet`. The effect only showed
    /// on the next unrelated render — so a mode switch looked like it lagged.
    func test_changesPublisher_reportsWhatAReReadingSinkWouldSee() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)

        var layoutWhenNotified: LayoutMode?
        let cancellable = store.changes.sink { _ in layoutWhenNotified = store.settings.layout }
        defer { cancellable.cancel() }

        store.update { $0.layout = .dual }
        XCTAssertEqual(layoutWhenNotified, .dual)
    }

    func test_updatePersistsBeforeNotifying() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(fileURL: url)

        var onDiskWhenNotified: LayoutMode?
        let cancellable = store.changes.sink { _ in
            onDiskWhenNotified = SettingsStore(fileURL: url).settings.layout
        }
        defer { cancellable.cancel() }

        store.update { $0.layout = .dual }
        XCTAssertEqual(onDiskWhenNotified, .dual, "a theme-style hot reload reads the file, so it must be written first")
    }
}
