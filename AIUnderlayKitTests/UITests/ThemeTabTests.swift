import AppKit
import SwiftUI
import XCTest
@testable import AIUnderlayKit

/// Smoke test for the theme tab: it must lay out with a real store behind it,
/// including the error section, which only appears once something is broken.
@MainActor
final class ThemeTabTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiu-theme-tab-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func host(settings: SettingsStore, themes: ThemeStore) -> NSHostingView<ThemeTab> {
        let host = NSHostingView(rootView: ThemeTab(settings: settings, themes: themes))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return host
    }

    func test_rendersWithAStoreAndBuiltInTheme() {
        let settings = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let themes = ThemeStore(directory: directory, watch: false)
        let host = host(settings: settings, themes: themes)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func test_rendersWithABrokenThemeFile() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ half written".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let settings = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let themes = ThemeStore(directory: directory, watch: false)
        XCTAssertNotNil(themes.lastError)
        let host = host(settings: settings, themes: themes)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
