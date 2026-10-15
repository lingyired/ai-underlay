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

    // MARK: - Material softness copy and storage compatibility

    func test_materialSoftnessCopy_describesRenderedGlassNotBackdropSampling() {
        XCTAssertEqual(ThemeTab.softnessLabel, "材质柔化")
        let note = ThemeTab.softnessNote
        XCTAssertTrue(note.contains("原生绘制"), "the slider must say it softens drawn material")
        XCTAssertFalse(note.contains("背景模糊"), "it must not claim a system backdrop blur")
        for token in ["0", "17", "32"] {
            XCTAssertTrue(note.contains(token), "the note should name the \(token) steps")
        }
    }

    func test_blurRadiusTarget_keepsItsStoredKeyAndRange() {
        XCTAssertEqual(GlassDefaults.material.blurRadiusTarget, 17, "the V5 default is still 17")
        let legacy = Data(#"{"blurRadiusTarget":21}"#.utf8)
        let overrides = try? JSONDecoder().decode(GlassMaterialOverrides.self, from: legacy)
        XCTAssertEqual(overrides?.blurRadiusTarget, 21, "existing theme/settings files keep parsing")
        XCTAssertEqual(GlassMaterialParameters(blurRadiusTarget: 40).clamped.blurRadiusTarget, 32)
        XCTAssertEqual(GlassMaterialParameters(blurRadiusTarget: -3).clamped.blurRadiusTarget, 0)
    }

    func test_materialSlider_roundTripsThroughTheSettingsStore() {
        let settings = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        settings.update { $0.appearance.material = GlassMaterialOverrides(blurRadiusTarget: 32) }
        XCTAssertEqual(settings.settings.appearance.material?.blurRadiusTarget, 32)
        settings.update { $0.appearance.material = nil }
        XCTAssertNil(settings.settings.appearance.material, "reset falls back to the built-in 17")
    }
}
