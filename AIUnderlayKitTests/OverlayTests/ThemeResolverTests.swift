import XCTest
@testable import AIUnderlayKit

/// The resolver is the boundary between "what a theme says" and "how it draws".
/// It must fill in only what the theme names, and it must never touch which
/// state wins — that is `AgentEffectStyle`'s job.
final class ThemeResolverTests: XCTestCase {
    private let theme = ThemeDocument(
        id: "t",
        name: "T",
        global: .init(trackColor: "#102030", trackOpacity: 0.5, baselineColor: "#ABCDEF", baselineOpacity: 0.25),
        providers: [
            "codex": .init(quotaLayers: ["#111111", "#222222", "#333333"], spectrumColor: "#D5F6FF",
                           spectrumOpacity: 0.5),
        ],
        states: [
            "waiting": .init(overlayColor: "#FFAA22", overlayOpacity: 0.2, borderColor: "#FFE15C", borderWidth: 3),
            "error": .init(overlayColor: "#FF355E", borderColor: "#FF526A"),
        ]
    )

    func test_paletteTakesOnlyTheFieldsTheThemeNames() {
        let base = ProviderPalette.codex
        let resolved = ThemeResolver.palette(theme: theme, providerId: "codex", base: base)
        XCTAssertEqual(resolved.outer, RGBAColor(red: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x11 / 255.0))
        XCTAssertEqual(resolved.middle, RGBAColor(red: 0x22 / 255.0, green: 0x22 / 255.0, blue: 0x22 / 255.0))
        XCTAssertEqual(resolved.inner, RGBAColor(red: 0x33 / 255.0, green: 0x33 / 255.0, blue: 0x33 / 255.0))
        XCTAssertEqual(resolved.track.alpha, 0.5, accuracy: 0.0001)
        XCTAssertEqual(resolved.baseline.alpha, 0.25, accuracy: 0.0001)

        // A provider the theme does not name keeps its own quota colors...
        let claude = ThemeResolver.palette(theme: theme, providerId: "claude", base: .claude)
        XCTAssertEqual(claude.outer, ProviderPalette.claude.outer)
        XCTAssertEqual(claude.middle, ProviderPalette.claude.middle)
        // ...while `global` tokens apply to the whole strip, so they do land.
        XCTAssertEqual(claude.track.alpha, 0.5, accuracy: 0.0001)
    }

    func test_paletteWithoutThemeIsTheBasePalette() {
        XCTAssertEqual(ThemeResolver.palette(theme: nil, providerId: "codex", base: .codex), .codex)
    }

    func test_paletteWithASingleLayerFillsEveryTier() {
        let single = ThemeDocument(id: "s", name: "S", providers: ["codex": .init(quotaLayers: ["#000000"])])
        let resolved = ThemeResolver.palette(theme: single, providerId: "codex", base: .codex)
        XCTAssertEqual(resolved.outer, resolved.middle)
        XCTAssertEqual(resolved.middle, resolved.inner)
    }

    func test_effectsCarryWaitingAndErrorAppearance() {
        let effects = ThemeResolver.effects(theme: theme, providerId: "codex")
        XCTAssertEqual(effects?.runningColor?.alpha ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(effects?.waitingBorderWidth, 3)
        XCTAssertEqual(effects?.errorBorderWidth, nil)
        XCTAssertNotNil(effects?.waitingOverlay)
        XCTAssertNotNil(effects?.errorOverlay)
    }

    func test_effectsAreNilWhenTheThemeNamesNothing() {
        let empty = ThemeDocument(id: "e", name: "E")
        XCTAssertNil(ThemeResolver.effects(theme: empty, providerId: "codex"))
        XCTAssertNil(ThemeResolver.effects(theme: nil, providerId: "codex"))
    }

    /// A theme that only describes Waiting can never repaint a failure: the
    /// priority lives in code, not in the file.
    func test_themeCannotRepaintAHigherPriorityState() {
        let waitingOnly = ThemeDocument(
            id: "w", name: "W",
            states: ["waiting": .init(overlayColor: "#00FF00", borderColor: "#00FF00")]
        )
        let theme = ThemeResolver.effects(theme: waitingOnly, providerId: "codex")
        let error = AgentEffectStyle.style(for: .error, runningColor: nil, theme: theme)
        XCTAssertEqual(error?.color, AgentEffectStyle.defaultColor(for: .error))
        XCTAssertEqual(error?.borderColor, AgentEffectStyle.failureBorder)
        let waiting = AgentEffectStyle.style(for: .waitingInput, runningColor: nil, theme: theme)
        XCTAssertEqual(waiting?.borderColor, RGBAColor(red: 0, green: 1, blue: 0))
    }

    func test_explicitUserColorBeatsTheTheme() {
        let explicit = RGBAColor(red: 0.9, green: 0.1, blue: 0.2)
        let style = AgentEffectStyle.style(for: .running, runningColor: explicit,
                                           theme: ThemeResolver.effects(theme: theme, providerId: "codex"))
        XCTAssertEqual(style?.color, explicit)
    }
}
