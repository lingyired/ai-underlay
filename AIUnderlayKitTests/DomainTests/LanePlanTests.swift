import XCTest
@testable import AIUnderlayKit

final class LanePlanTests: XCTestCase {
    private let supported = ["codex", "claude"]

    private func plan(
        _ enabled: [String],
        _ layout: LayoutMode,
        _ split: DualWindowSplit = .none
    ) -> LanePlan {
        LanePlanResolver.plan(
            enabledProviders: enabled,
            supportedProviders: supported,
            layout: layout,
            split: split
        )
    }

    // MARK: - Provider switches

    func test_dual_bothProviders_keepHomeSides() {
        let resolved = plan(["claude", "codex"], .dual)
        XCTAssertEqual(resolved.leftProviderId, "codex")
        XCTAssertEqual(resolved.rightProviderId, "claude")
        XCTAssertNil(resolved.splitSessionSide)
        XCTAssertNil(resolved.singleProviderId)
    }

    func test_dual_oneProviderOff_leavesItsOwnSideEmpty() {
        // The side is part of the provider's identity: Claude stays right when
        // Codex is switched off, instead of sliding over.
        let claudeOnly = plan(["claude"], .dual)
        XCTAssertNil(claudeOnly.leftProviderId)
        XCTAssertEqual(claudeOnly.rightProviderId, "claude")

        let codexOnly = plan(["codex"], .dual)
        XCTAssertEqual(codexOnly.leftProviderId, "codex")
        XCTAssertNil(codexOnly.rightProviderId)
    }

    func test_dual_noProviders_plansNoLanes() {
        let resolved = plan([], .dual)
        XCTAssertNil(resolved.leftProviderId)
        XCTAssertNil(resolved.rightProviderId)
    }

    // MARK: - Dual-window split

    func test_dual_singleProviderSplit_usesBothSidesForSameProvider() {
        let resolved = plan(["codex"], .dual, .sessionLeft)
        XCTAssertEqual(resolved.leftProviderId, "codex")
        XCTAssertEqual(resolved.rightProviderId, "codex")
        XCTAssertEqual(resolved.splitSessionSide, .left)
        XCTAssertNil(resolved.singleProviderId)
    }

    func test_dual_splitIgnored_withTwoProviders() {
        let resolved = plan(["codex", "claude"], .dual, .sessionLeft)
        XCTAssertEqual(resolved.leftProviderId, "codex")
        XCTAssertEqual(resolved.rightProviderId, "claude")
        XCTAssertNil(resolved.splitSessionSide)
    }

    func test_dual_splitIgnored_withNoProvider() {
        let resolved = plan([], .dual, .sessionRight)
        XCTAssertNil(resolved.leftProviderId)
        XCTAssertNil(resolved.rightProviderId)
        XCTAssertNil(resolved.splitSessionSide)
    }

    func test_splitEnum_mapsToItsSessionSide() {
        XCTAssertNil(DualWindowSplit.none.sessionSide)
        XCTAssertEqual(DualWindowSplit.sessionLeft.sessionSide, .left)
        XCTAssertEqual(DualWindowSplit.sessionRight.sessionSide, .right)
    }

    // MARK: - Lane targets (plan + data)

    func test_lanes_split_carriesOnlyTheMatchingWindowsOnEachSide() {
        let windows = [window("w", .weekly), window("s", .session)]
        let resolved = plan(["codex"], .dual, .sessionLeft)
        let lanes = LanePlanResolver.lanes(for: resolved) { _ in windows }

        XCTAssertEqual(lanes.left?.providerId, "codex")
        XCTAssertEqual(lanes.left?.windows.map(\.id), ["s"])
        XCTAssertEqual(lanes.right?.providerId, "codex")
        XCTAssertEqual(lanes.right?.windows.map(\.id), ["w"])
    }

    func test_lanes_splitHonoursTheOppositeSide() {
        let windows = [window("w", .weekly), window("s", .session)]
        let resolved = plan(["claude"], .dual, .sessionRight)
        let lanes = LanePlanResolver.lanes(for: resolved) { _ in windows }

        XCTAssertEqual(lanes.left?.providerId, "claude")
        XCTAssertEqual(lanes.left?.windows.map(\.id), ["w"])
        XCTAssertEqual(lanes.right?.providerId, "claude")
        XCTAssertEqual(lanes.right?.windows.map(\.id), ["s"])
    }

    func test_lanes_offProviderHasNoLaneAtAll() {
        let resolved = plan(["codex"], .dual)
        let lanes = LanePlanResolver.lanes(for: resolved) { _ in [self.window("w", .weekly)] }

        XCTAssertEqual(lanes.left?.providerId, "codex")
        XCTAssertEqual(lanes.left?.windows.map(\.id), ["w"])
        XCTAssertNil(lanes.right, "a switched-off provider must not get an empty lane target")
    }

    func test_lanes_singleModeUsesTheSingleProviderOnTheLeft() {
        let resolved = plan(["claude"], .single)
        let lanes = LanePlanResolver.lanes(for: resolved) { _ in [] }

        XCTAssertEqual(lanes.left?.providerId, "claude")
        XCTAssertTrue(lanes.left?.windows.isEmpty ?? false)
        XCTAssertNil(lanes.right)
    }

    func test_lanes_noProvider_hasNoTargets() {
        let lanes = LanePlanResolver.lanes(for: plan([], .dual)) { _ in [] }
        XCTAssertNil(lanes.left)
        XCTAssertNil(lanes.right)
    }

    // MARK: - Single layout

    func test_single_usesFirstEnabledProvider() {
        XCTAssertEqual(plan(["codex", "claude"], .single).singleProviderId, "codex")
        XCTAssertEqual(plan(["claude"], .single).singleProviderId, "claude")
        XCTAssertNil(plan([], .single).singleProviderId)
        XCTAssertNil(plan(["codex"], .single).leftProviderId, "dual lanes stay unplanned in single mode")
    }

    // MARK: - Window splitting

    func test_windowSplit_sessionGoesToChosenSide_restKeepsOrder() {
        let all = [
            window("m", .monthly),
            window("w", .weekly),
            window("s", .session),
        ]

        let sessionLeft = WindowSplit.split(all, sessionSide: .left)
        XCTAssertEqual(sessionLeft.left.map(\.id), ["s"])
        XCTAssertEqual(sessionLeft.right.map(\.id), ["m", "w"])

        let sessionRight = WindowSplit.split(all, sessionSide: .right)
        XCTAssertEqual(sessionRight.left.map(\.id), ["m", "w"])
        XCTAssertEqual(sessionRight.right.map(\.id), ["s"])
    }

    func test_windowSplit_withoutSession_leavesTheChosenSideEmpty() {
        let split = WindowSplit.split([window("w", .weekly)], sessionSide: .left)
        XCTAssertTrue(split.left.isEmpty)
        XCTAssertEqual(split.right.map(\.id), ["w"])
    }

    func test_windowSplit_neverDuplicatesOrDropsWindows() {
        let all = [window("m", .monthly), window("w", .weekly), window("s", .session)]
        let split = WindowSplit.split(all, sessionSide: .left)
        XCTAssertEqual(Set((split.left + split.right).map(\.id)), Set(all.map(\.id)))
        XCTAssertEqual(split.left.count + split.right.count, all.count)
    }

    // MARK: - Split side roles and colours

    func test_splitRole_namesTheSessionSideAndTheWeeklySide() {
        let sessionLeft = plan(["codex"], .dual, .sessionLeft)
        XCTAssertEqual(sessionLeft.splitRole(for: .left), .session)
        XCTAssertEqual(sessionLeft.splitRole(for: .right), .weekly)

        // Flipping the split moves the colour with the 5-hour window, so the
        // side a colour sits on never changes what it means.
        let sessionRight = plan(["codex"], .dual, .sessionRight)
        XCTAssertEqual(sessionRight.splitRole(for: .left), .weekly)
        XCTAssertEqual(sessionRight.splitRole(for: .right), .session)
    }

    func test_splitRole_isNilWheneverBothLanesAreNotOneSplitProvider() {
        XCTAssertNil(plan(["codex"], .dual, .none).splitRole(for: .left), "no split")
        XCTAssertNil(plan(["codex"], .dual, .none).splitRole(for: .right), "the provider owns its own side")
        XCTAssertNil(plan(["codex", "claude"], .dual, .sessionLeft).splitRole(for: .left),
                     "two providers keep their own colours")
        XCTAssertNil(plan(["codex"], .single, .sessionLeft).splitRole(for: .left), "single layout")
        XCTAssertNil(plan([], .dual, .sessionLeft).splitRole(for: .left), "no provider at all")
    }

    func test_splitColors_weeklyKeepsTheProviderColour_sessionTurnsTheHue() {
        let base = ProviderPalette.codex.inner
        let weekly = SplitLaneColors.baseColor(role: .weekly, providerBase: base)
        let session = SplitLaneColors.baseColor(role: .session, providerBase: base)

        XCTAssertEqual(weekly, base)
        XCTAssertNotEqual(session.hexString, weekly.hexString, "the two sides must not look alike")
        XCTAssertEqual(max(session.red, session.green, session.blue),
                       max(base.red, base.green, base.blue), accuracy: 0.0001,
                       "a split turns the hue only: brightness and chroma stay")
    }

    func test_splitColors_userPickWins_perSideAndPerRole() {
        let base = ProviderPalette.codex.inner
        let overrides = [SplitLaneRole.session.rawValue: "#FF00FF"]
        XCTAssertEqual(SplitLaneColors.baseColor(role: .session, providerBase: base, overrides: overrides),
                       RGBAColor(hex: "#FF00FF"))
        XCTAssertEqual(SplitLaneColors.baseColor(role: .weekly, providerBase: base, overrides: overrides), base,
                       "picking one side must not repaint the other")
    }

    func test_splitColors_invalidHexFallsBackToTheDerivation() {
        let base = ProviderPalette.claude.inner
        let overrides = [SplitLaneRole.session.rawValue: "not-a-colour"]
        XCTAssertEqual(SplitLaneColors.baseColor(role: .session, providerBase: base, overrides: overrides),
                       base.rotatedHue(by: SplitLaneColors.sessionHueShift),
                       "a typo in settings.json must not render black")
    }

    func test_splitColors_greyHasNoHueToTurn() {
        let grey = RGBAColor(red: 0.5, green: 0.5, blue: 0.5)
        XCTAssertEqual(SplitLaneColors.baseColor(role: .session, providerBase: grey), grey)
    }

    private func window(_ id: String, _ kind: QuotaWindowKind) -> QuotaWindow {
        QuotaWindow(
            id: id, label: id, kind: kind, durationSeconds: nil,
            remainingFraction: 0.5, resetAt: nil, expectedRemainingFraction: nil,
            updatedAt: nil, availability: .valid
        )
    }
}
