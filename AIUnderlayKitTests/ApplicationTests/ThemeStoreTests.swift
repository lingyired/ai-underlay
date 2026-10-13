import XCTest
@testable import AIUnderlayKit

/// The store decides what happens when a file is missing, mid-edit, or wrong.
/// It must never blank the bar and never lose a good theme to a bad edit.
@MainActor
final class ThemeStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiu-theme-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func write(_ json: String, as name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appendingPathComponent(name))
    }

    private var validTheme: String {
        ##"{"schemaVersion":1,"id":"mine","name":"Mine","providers":{"codex":{"spectrumColor":"#FF00FF"}}}"##
    }

    func test_builtInsAreAlwaysAvailable() {
        let store = ThemeStore(directory: directory, watch: false)
        XCTAssertTrue(store.themes.contains { $0.id == ThemePresets.vivid.id })
        XCTAssertNil(store.lastError)
        XCTAssertNil(store.activeTheme, "no theme selected means the built-in look")
    }

    func test_loadsThemeFiles() throws {
        try write(validTheme, as: "mine.json")
        let store = ThemeStore(directory: directory, activeId: "mine", watch: false)
        XCTAssertEqual(store.activeTheme?.id, "mine")
        XCTAssertEqual(store.themes.count, ThemePresets.all.count + 1)
        XCTAssertNil(store.lastError)
    }

    func test_brokenFileIsReportedAndNotUsed() throws {
        try write("{ nope", as: "broken.json")
        let store = ThemeStore(directory: directory, watch: false)
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.themes.count, ThemePresets.all.count)
    }

    /// A bad edit to the *active* theme must keep the last good version on
    /// screen rather than flashing to defaults.
    func test_activeThemeSurvivesABrokenEdit() throws {
        try write(validTheme, as: "mine.json")
        let store = ThemeStore(directory: directory, activeId: "mine", watch: false)
        XCTAssertEqual(store.activeTheme?.name, "Mine")

        try write("{ half-written", as: "mine.json")
        store.reload()
        XCTAssertEqual(store.activeTheme?.name, "Mine", "keep the last good version")
        XCTAssertNotNil(store.lastError, "and say what happened")
    }

    func test_selectingAnUnknownThemeFallsBackAndExplains() {
        let store = ThemeStore(directory: directory, watch: false)
        store.setActive(id: "does-not-exist")
        XCTAssertNil(store.activeTheme)
        XCTAssertNotNil(store.lastError)
    }

    func test_selectingClearsBackToBuiltInLook() throws {
        try write(validTheme, as: "mine.json")
        let store = ThemeStore(directory: directory, activeId: "mine", watch: false)
        store.setActive(id: nil)
        XCTAssertNil(store.activeTheme)
        XCTAssertNil(store.lastError)
    }

    func test_reloadPublishesSoTheOverlayCanRepaint() throws {
        let store = ThemeStore(directory: directory, activeId: "mine", watch: false)
        XCTAssertNil(store.activeTheme)
        let before = store.revision

        try write(validTheme, as: "mine.json")
        store.reload()
        store.setActive(id: "mine")
        XCTAssertEqual(store.activeTheme?.id, "mine")
        XCTAssertGreaterThan(store.revision, before)
    }

    func test_fileWatcherPicksUpANewFile() async throws {
        let store = ThemeStore(directory: directory, activeId: "mine", watch: true)
        XCTAssertNil(store.activeTheme)

        try write(validTheme, as: "mine.json")
        // The watcher debounces directory events; give it room without making
        // the suite slow.
        let deadline = Date().addingTimeInterval(5)
        while store.activeTheme == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(store.activeTheme?.id, "mine")
    }

    /// Editing an existing file is the common case for an agent (and for a
    /// person in a text editor), and it does not change the directory, so it
    /// needs its own watch.
    func test_fileWatcherPicksUpAContentEdit() async throws {
        try write(validTheme, as: "mine.json")
        let store = ThemeStore(directory: directory, activeId: "mine", watch: true)
        XCTAssertEqual(store.activeTheme?.providers?["codex"]?.spectrumColor, "#FF00FF")

        try write(validTheme.replacingOccurrences(of: "#FF00FF", with: "#00FF00"), as: "mine.json")
        let deadline = Date().addingTimeInterval(5)
        while store.activeTheme?.providers?["codex"]?.spectrumColor != "#00FF00" && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(store.activeTheme?.providers?["codex"]?.spectrumColor, "#00FF00")
    }
}
