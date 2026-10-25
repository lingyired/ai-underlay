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

    // MARK: - Effective values and scoped resets

    func test_colorFallbackUsesEachRowsProviderThemeValue() {
        let claudeTheme = ThemeDocument(
            id: "per-provider",
            name: "Per provider",
            providers: [
                "codex": .init(quotaBaseColor: "#445566", agentThemeColor: "#112233"),
                "claude": .init(quotaBaseColor: "#DD7744", agentThemeColor: "#AA3355"),
            ]
        )

        let claudeTint = ThemeTabPreviewState.fallbackColor(
            for: .glassTint(providerId: "claude"),
            theme: claudeTheme,
            providerId: "codex",
            appearance: .empty
        )
        let claudeQuota = ThemeTabPreviewState.fallbackColor(
            for: .quotaBase(providerId: "claude"),
            theme: claudeTheme,
            providerId: "codex",
            appearance: .empty
        )

        XCTAssertEqual(claudeTint.hexString, "#AA3355")
        XCTAssertNotEqual(claudeTint.hexString, "#112233")
        XCTAssertEqual(claudeQuota.hexString, "#DD7744")
        XCTAssertNotEqual(claudeQuota.hexString, "#445566")
    }

    func test_themeSourceReflectsWhetherThemeProvidesTheField() {
        let theme = ThemeDocument(
            id: "partial",
            name: "Partial",
            providers: ["claude": .init(agentThemeColor: "#AA3355")]
        )
        XCTAssertEqual(
            ThemeTabPreviewState.source(
                for: .glassTint(providerId: "claude"),
                appearance: .empty,
                theme: theme
            ),
            .theme
        )
        XCTAssertEqual(
            ThemeTabPreviewState.source(
                for: .quotaBase(providerId: "claude"),
                appearance: .empty,
                theme: theme
            ),
            .builtIn
        )
    }

    func test_quotaResetIncludesExhaustedTrackOnly() {
        let appearance = GlassAppearance(
            agentThemeColors: ["codex": "#112233"],
            quotaBaseColors: ["claude": "#445566"],
            splitQuotaBaseColors: ["session": "#778899"],
            signalColors: ["error": "#AA3355"],
            exhaustedTrackColor: "#010203",
            material: GlassMaterialOverrides(blurRadiusTarget: 24)
        )

        let reset = ThemeTabPreviewState.ResetScope.quotaColors.apply(to: appearance)
        XCTAssertTrue(reset.quotaBaseColors.isEmpty)
        XCTAssertNil(reset.exhaustedTrackColor)
        XCTAssertFalse(reset.agentThemeColors.isEmpty)
        XCTAssertFalse(reset.splitQuotaBaseColors.isEmpty)
        XCTAssertFalse(reset.signalColors.isEmpty)
        XCTAssertEqual(reset.material?.blurRadiusTarget, 24)
    }

    func test_materialDisplayUsesResolvedClampedValues() {
        let theme = ThemeDocument(
            id: "material-theme",
            name: "Material theme",
            material: .init(
                blurRadiusTarget: 27,
                ambientGlow: 0.4,
                grain: 0.2,
                rayDensity: 0.6,
                quotaOpacity: 0.8,
                agentThemeStrength: 0.9
            )
        )
        let material = ThemeTabPreviewState.material(
            theme: theme,
            appearance: .empty
        )

        XCTAssertEqual(material.blurRadiusTarget, 27)
        XCTAssertEqual(material.ambientGlow, 0.4)
        XCTAssertEqual(
            ThemeTabPreviewState.MaterialField.softness.display(
                material.blurRadiusTarget
            ),
            "27"
        )
        XCTAssertEqual(
            ThemeTabPreviewState.MaterialField.ambientGlow.display(
                material.ambientGlow
            ),
            "40%"
        )
    }

    func test_materialWriteClampsAndRestoresOnlyThatField() {
        var appearance = GlassAppearance(
            material: GlassMaterialOverrides(ambientGlow: 0.6, grain: 0.3)
        )

        ThemeTabPreviewState.write(-5, for: .softness, to: &appearance)
        XCTAssertEqual(appearance.material?.blurRadiusTarget, 0)
        XCTAssertEqual(appearance.material?.ambientGlow, 0.6)
        XCTAssertEqual(appearance.material?.grain, 0.3)

        ThemeTabPreviewState.clear(.softness, from: &appearance)
        XCTAssertNil(appearance.material?.blurRadiusTarget)
        XCTAssertEqual(appearance.material?.ambientGlow, 0.6)
        XCTAssertEqual(appearance.material?.grain, 0.3)
    }
}
