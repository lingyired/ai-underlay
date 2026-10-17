import XCTest
@testable import AIUnderlayKit

/// The resolver is the boundary between "what a theme says" and "how it draws".
/// It must fill in only what the theme names, keep the three colour roles
/// separate, and never touch which state wins.
final class ThemeResolverTests: XCTestCase {
    private let v1Theme = ThemeDocument(
        schemaVersion: 1,
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

    private let v2Theme = ThemeDocument(
        schemaVersion: 2,
        id: "v2",
        name: "V2",
        global: .init(baselineColor: "#FFFFFF", exhaustedTrackColor: "#000000", exhaustedTrackOpacity: 0.9),
        providers: [
            "codex": .init(quotaBaseColor: "#00FF00", agentThemeColor: "#FF00FF"),
        ],
        signals: .init(
            running: .init(lightColor: "#123456"),
            error: .init(lightColor: "#654321")
        ),
        material: .init(ambientGlow: 0.5, rayDensity: 0.4),
        attention: .init(bottomRibbonHeight: 8, sweepSecondsError: 12)
    )

    // MARK: - Palette

    func test_v1PaletteTakesOnlyTheFieldsTheThemeNames() {
        let resolved = ThemeResolver.palette(theme: v1Theme, providerId: "codex", base: .codex)
        XCTAssertEqual(resolved.outer, RGBAColor(red: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x11 / 255.0))
        XCTAssertEqual(resolved.middle, RGBAColor(red: 0x22 / 255.0, green: 0x22 / 255.0, blue: 0x22 / 255.0))
        XCTAssertEqual(resolved.inner, RGBAColor(red: 0x33 / 255.0, green: 0x33 / 255.0, blue: 0x33 / 255.0))
        XCTAssertEqual(resolved.track.alpha, 0.5, accuracy: 0.0001)
        XCTAssertEqual(resolved.baseline.alpha, 0.25, accuracy: 0.0001)

        // A provider the theme does not name keeps its own quota colours...
        let claude = ThemeResolver.palette(theme: v1Theme, providerId: "claude", base: .claude)
        XCTAssertEqual(claude.outer, ProviderPalette.claude.outer)
        // ...while global tokens apply to the whole strip.
        XCTAssertEqual(claude.track.alpha, 0.5, accuracy: 0.0001)
    }

    func test_v2QuotaBaseColor_derivesAVisibleTierLadder() {
        let resolved = ThemeResolver.palette(theme: v2Theme, providerId: "codex", base: .codex)
        let base = RGBAColor(hex: "#00FF00")!
        XCTAssertEqual(resolved.inner, base)
        XCTAssertLessThan(resolved.outer.luminance, resolved.inner.luminance)
        XCTAssertGreaterThan(resolved.outer.luminance, 0, "the derived tier is not black")
    }

    func test_userQuotaColorOutranksTheTheme() {
        let appearance = GlassAppearance(quotaBaseColors: ["codex": "#FF0000"])
        let resolved = ThemeResolver.palette(theme: v2Theme, providerId: "codex", base: .codex, appearance: appearance)
        XCTAssertEqual(resolved.inner, RGBAColor(hex: "#FF0000"))
    }

    func test_noThemeIsTheV5BasePalette() {
        XCTAssertEqual(ThemeResolver.palette(theme: nil, providerId: "codex", base: .codex), .codex)
        XCTAssertEqual(ProviderPalette.codex.inner, RGBAColor(hex: "#69BFFF")!)
        XCTAssertEqual(ProviderPalette.claude.inner, RGBAColor(hex: "#FFB08A")!)
    }

    // MARK: - Split side colours

    func test_splitRole_paintsTheTwoSidesDifferently() {
        let weekly = ThemeResolver.palette(theme: nil, providerId: "codex", base: .codex, splitRole: .weekly)
        let session = ThemeResolver.palette(theme: nil, providerId: "codex", base: .codex, splitRole: .session)

        XCTAssertEqual(weekly, .codex, "the weekly side keeps the provider look untouched")
        XCTAssertNotEqual(session.inner, weekly.inner, "a split must be visible at a glance")
        XCTAssertLessThan(session.outer.luminance, session.inner.luminance,
                          "the derived tier ladder still holds on the split side")
    }

    func test_splitRole_neverTouchesTrackOrBaseline() {
        let resolved = ThemeResolver.palette(
            theme: v1Theme, providerId: "codex", base: .codex, splitRole: .session
        )
        XCTAssertEqual(resolved.track.alpha, 0.5, accuracy: 0.0001)
        XCTAssertEqual(resolved.baseline.alpha, 0.25, accuracy: 0.0001)
    }

    func test_splitRole_userSplitColourOutranksTheDerivation() {
        let appearance = GlassAppearance(splitQuotaBaseColors: ["session": "#FF0000"])
        let session = ThemeResolver.palette(
            theme: nil, providerId: "codex", base: .codex, appearance: appearance, splitRole: .session
        )
        XCTAssertEqual(session.inner, RGBAColor(hex: "#FF0000"))

        let weekly = ThemeResolver.palette(
            theme: nil, providerId: "codex", base: .codex, appearance: appearance, splitRole: .weekly
        )
        XCTAssertEqual(weekly, .codex, "one side's colour never leaks into the other")
    }

    func test_splitRole_staysInsideTheProvidersOwnColour() {
        // A user or theme colour for the provider is the source both sides
        // derive from: the split must not fall back to the built-in V5 base.
        let appearance = GlassAppearance(quotaBaseColors: ["codex": "#00FF00"])
        let session = ThemeResolver.palette(
            theme: nil, providerId: "codex", base: .codex, appearance: appearance, splitRole: .session
        )
        XCTAssertEqual(session.inner, RGBAColor(hex: "#00FF00")!.rotatedHue(by: SplitLaneColors.sessionHueShift))
    }

    func test_splitRoleIsIgnoredWithoutASplit() {
        let plain = ThemeResolver.palette(theme: nil, providerId: "codex", base: .codex)
        XCTAssertEqual(plain, .codex)
    }

    // MARK: - Agent glass tint

    func test_agentThemeDefaultsAreTheUsersV5Selection() {
        let codex = ThemeResolver.glassTheme(theme: nil, providerId: "codex", base: .codex)
        let claude = ThemeResolver.glassTheme(theme: nil, providerId: "claude", base: .claude)
        XCTAssertEqual(codex.agentThemeColor, RGBAColor(hex: "#62AC96"))
        XCTAssertEqual(claude.agentThemeColor, RGBAColor(hex: "#FFFFFF"))
    }

    func test_agentTheme_precedenceUserThenThemeThenDefault() {
        let fromTheme = ThemeResolver.glassTheme(theme: v2Theme, providerId: "codex", base: .codex)
        XCTAssertEqual(fromTheme.agentThemeColor, RGBAColor(hex: "#FF00FF"))

        let appearance = GlassAppearance(agentThemeColors: ["codex": "#123123"])
        let fromUser = ThemeResolver.glassTheme(theme: v2Theme, providerId: "codex", base: .codex,
                                                appearance: appearance)
        XCTAssertEqual(fromUser.agentThemeColor, RGBAColor(hex: "#123123"))
    }

    func test_agentThemeIsPerProvider() {
        let codex = ThemeResolver.glassTheme(theme: v2Theme, providerId: "codex", base: .codex)
        let claude = ThemeResolver.glassTheme(theme: v2Theme, providerId: "claude", base: .claude)
        XCTAssertEqual(claude.agentThemeColor, GlassDefaults.claudeAgentTheme)
        XCTAssertNotEqual(codex.agentThemeColor, claude.agentThemeColor)
    }

    func test_invalidUserHexIsIgnored_notRenderedAsBlack() {
        let appearance = GlassAppearance(agentThemeColors: ["codex": "not-a-colour"])
        let resolved = ThemeResolver.glassTheme(theme: nil, providerId: "codex", base: .codex, appearance: appearance)
        XCTAssertEqual(resolved.agentThemeColor, GlassDefaults.codexAgentTheme)
    }

    // MARK: - Signals

    func test_signalsDefaultsAreTheV5Lights() {
        let glass = ThemeResolver.glassTheme(theme: nil, providerId: "codex", base: .codex)
        XCTAssertEqual(glass.signalLights.running, RGBAColor(hex: "#D9EEFF"))
        XCTAssertEqual(glass.signalLights.error, RGBAColor(hex: "#FF7596"))
        XCTAssertEqual(glass.signalLights.waiting, RGBAColor(hex: "#FFE1A0"))
        XCTAssertEqual(glass.signalLights.unread, RGBAColor(hex: "#64F1BD"))
    }

    func test_v2SignalsAreGlobalAndPerKind() {
        let codex = ThemeResolver.glassTheme(theme: v2Theme, providerId: "codex", base: .codex)
        let claude = ThemeResolver.glassTheme(theme: v2Theme, providerId: "claude", base: .claude)
        XCTAssertEqual(codex.signalLights.running, RGBAColor(hex: "#123456"))
        XCTAssertEqual(codex.signalLights.error, RGBAColor(hex: "#654321"))
        XCTAssertEqual(claude.signalLights.running, codex.signalLights.running,
                       "signal lights are global semantics, not per provider")
        // A kind the theme did not name keeps the V5 default.
        XCTAssertEqual(codex.signalLights.waiting, GlassDefaults.signalLights.waiting)
    }

    func test_userSignalColorOutranksEverything() {
        let appearance = GlassAppearance(signalColors: ["error": "#00FFFF"])
        let resolved = ThemeResolver.glassTheme(theme: v2Theme, providerId: "codex", base: .codex,
                                                appearance: appearance)
        XCTAssertEqual(resolved.signalLights.error, RGBAColor(hex: "#00FFFF"))
    }

    /// Legacy v1 mapping: `states.waiting` / `states.error` collapse to one
    /// light each, taking the old ribbon colour first.
    func test_v1StatesMapToSignalLights() {
        let resolved = ThemeResolver.glassTheme(theme: v1Theme, providerId: "codex", base: .codex)
        XCTAssertEqual(resolved.signalLights.waiting, RGBAColor(hex: "#FFE15C"))
        XCTAssertEqual(resolved.signalLights.error, RGBAColor(hex: "#FF526A"))
    }

    func test_v1SpectrumColor_mapsToTheRunningLightOnlyWhenUnambiguous() {
        let single = ThemeResolver.glassTheme(theme: v1Theme, providerId: "codex", base: .codex)
        XCTAssertEqual(single.signalLights.running, RGBAColor(hex: "#D5F6FF"))

        let ambiguous = ThemeDocument(
            schemaVersion: 1, id: "a", name: "A",
            providers: [
                "codex": .init(spectrumColor: "#111111"),
                "claude": .init(spectrumColor: "#222222"),
            ]
        )
        let resolved = ThemeResolver.glassTheme(theme: ambiguous, providerId: "codex", base: .codex)
        XCTAssertEqual(resolved.signalLights.running, GlassDefaults.signalLights.running,
                       "two different provider colours must not be merged into one state semantic")
    }

    // MARK: - Material & attention

    func test_materialPrecedenceDefaultThemeUser() {
        let themeOnly = ThemeResolver.glassTheme(theme: v2Theme, providerId: "codex", base: .codex)
        XCTAssertEqual(themeOnly.material.rayDensity, 0.4, accuracy: 0.0001)
        XCTAssertEqual(themeOnly.material.ambientGlow, 0.5, accuracy: 0.0001)
        XCTAssertEqual(themeOnly.material.quotaOpacity, 1.0, accuracy: 0.0001, "unnamed fields keep V5 defaults")

        let appearance = GlassAppearance(material: GlassMaterialOverrides(rayDensity: 0.7))
        let user = ThemeResolver.glassTheme(theme: v2Theme, providerId: "codex", base: .codex, appearance: appearance)
        XCTAssertEqual(user.material.rayDensity, 0.7, accuracy: 0.0001, "the user's edit wins")
        XCTAssertEqual(user.material.ambientGlow, 0.5, accuracy: 0.0001, "other fields still follow the theme")
    }

    func test_materialIsClampedEvenFromASettingsFile() {
        let appearance = GlassAppearance(material: GlassMaterialOverrides(rayDensity: 5, agentThemeStrength: -2))
        let resolved = ThemeResolver.glassTheme(theme: nil, providerId: "codex", base: .codex, appearance: appearance)
        XCTAssertEqual(resolved.material.rayDensity, 1.0, accuracy: 0.0001)
        XCTAssertEqual(resolved.material.agentThemeStrength, 0, accuracy: 0.0001)
    }

    func test_attentionGeometryFromThemeIsClamped() {
        let resolved = ThemeResolver.glassTheme(theme: v2Theme, providerId: "codex", base: .codex)
        XCTAssertEqual(resolved.attention.bottomRibbonHeight, 8, accuracy: 0.0001)
        XCTAssertEqual(resolved.attention.sweepSecondsError, 12, accuracy: 0.0001)
        XCTAssertEqual(resolved.attention.topLineHeight, 2, accuracy: 0.0001, "unnamed fields keep V5 defaults")
    }

    func test_exhaustedTrack_defaultsToOpaqueBlack() {
        let resolved = ThemeResolver.glassTheme(theme: nil, providerId: "codex", base: .codex)
        XCTAssertEqual(resolved.exhaustedTrack, RGBAColor(red: 0, green: 0, blue: 0, alpha: 1))
    }

    func test_baselineEnabledNeverTurnsOnAgainstTheUser() {
        let off = ThemeDocument(schemaVersion: 2, id: "b", name: "B",
                                global: .init(baselineEnabled: false))
        XCTAssertFalse(ThemeResolver.glassTheme(theme: off, providerId: "codex", base: .codex).showsBaseline)
        XCTAssertTrue(ThemeResolver.glassTheme(theme: nil, providerId: "codex", base: .codex).showsBaseline)
    }
}
