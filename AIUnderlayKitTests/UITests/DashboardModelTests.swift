import XCTest
@testable import AIUnderlayKit

final class DashboardModelTests: XCTestCase {
    private func snapshot(provider: String, windows: [QuotaWindow], availability: DataAvailability = .valid) -> ProviderQuotaSnapshot {
        ProviderQuotaSnapshot(id: provider, providerId: provider, accountKey: nil,
                              sourceEngineId: "codexbar", windows: windows,
                              fetchedAt: Date(), availability: availability)
    }

    private func window(_ id: String, _ kind: QuotaWindowKind, _ remaining: Double?) -> QuotaWindow {
        QuotaWindow(id: id, label: id, kind: kind, durationSeconds: kind == .weekly ? 604800 : 18000,
                    remainingFraction: remaining, resetAt: nil, expectedRemainingFraction: nil,
                    updatedAt: nil, availability: remaining == nil ? .unavailable : .valid)
    }

    func test_sections_haveProviderAndRows() {
        let sections = DashboardModel.sections(
            providers: ["codex", "claude"],
            snapshots: ["codex": snapshot(provider: "codex", windows: [window("w", .weekly, 0.98), window("s", .session, 0.88)])]
        )
        XCTAssertEqual(sections.count, 2)
        let codex = sections.first { $0.providerId == "codex" }!
        XCTAssertEqual(codex.rows.count, 2)
        XCTAssertEqual(codex.displayName, "Codex")
        // claude has no snapshot → section still present, empty, unknown.
        let claude = sections.first { $0.providerId == "claude" }!
        XCTAssertTrue(claude.rows.isEmpty)
        XCTAssertEqual(claude.availability, .unknown)
    }

    func test_labelsAreLocalized() {
        XCTAssertEqual(DashboardModel.label(for: window("s", .session, 0.5)), "5 小时")
        XCTAssertEqual(DashboardModel.label(for: window("w", .weekly, 0.5)), "每周")
        XCTAssertEqual(DashboardModel.label(for: window("m", .monthly, 0.5)), "每月")
    }

    func test_emptyStateTextForUnauthenticated() {
        XCTAssertEqual(DashboardModel.emptyStateText(for: .unauthenticated), "未登录")
        XCTAssertEqual(DashboardModel.emptyStateText(for: .unavailable), "暂无数据")
    }

    func test_resetLabel() {
        let now = Date()
        let row = DashboardRow(id: "x", label: "每周", remainingFraction: 0.5,
                               resetAt: now.addingTimeInterval(3 * 3600 + 25 * 60), availability: .valid)
        XCTAssertEqual(row.resetLabel(now: now), "3 小时 25 分后重置")
        let past = DashboardRow(id: "y", label: "每周", remainingFraction: 0.5,
                                resetAt: now.addingTimeInterval(-10), availability: .valid)
        XCTAssertEqual(past.resetLabel(now: now), "即将重置")
    }

    func test_verdict_comparesActualToExpected() {
        func row(_ actual: Double?, _ expected: Double?) -> DashboardRow {
            DashboardRow(id: "x", label: "每周", remainingFraction: actual,
                         expectedRemainingFraction: expected, resetAt: nil, availability: .valid)
        }
        XCTAssertEqual(row(0.4, 0.7).verdict, .fast)
        XCTAssertEqual(row(0.9, 0.7).verdict, .surplus)
        XCTAssertEqual(row(0.7, 0.7).verdict, .onTrack)
        XCTAssertEqual(row(nil, 0.7).verdict, .unknown)
        XCTAssertEqual(row(0.7, nil).verdict, .unknown)
    }

    func test_paceNote_isNeutral() {
        let fast = DashboardRow(id: "x", label: "每周", remainingFraction: 0.4,
                                expectedRemainingFraction: 0.7, resetAt: nil, availability: .valid)
        XCTAssertEqual(fast.paceNote, "消耗偏快（低于匀速基准）")
        let unknown = DashboardRow(id: "y", label: "每周", remainingFraction: 0.4,
                                   expectedRemainingFraction: nil, resetAt: nil, availability: .valid)
        XCTAssertNil(unknown.paceNote)
    }

    func test_sectionsCarryExpectedFromPace() {
        // A window with a reset and duration should get an expected value.
        let w = QuotaWindow(id: "w", label: "w", kind: .weekly, durationSeconds: 604800,
                            remainingFraction: 0.5, resetAt: Date().addingTimeInterval(604800 * 0.5),
                            expectedRemainingFraction: nil, updatedAt: nil, availability: .valid)
        let sections = DashboardModel.sections(
            providers: ["codex"],
            snapshots: ["codex": snapshot(provider: "codex", windows: [w])]
        )
        XCTAssertNotNil(sections[0].rows[0].expectedRemainingFraction)
    }

    func test_unknownRemainingIsNilNotZero() {
        let sections = DashboardModel.sections(
            providers: ["codex"],
            snapshots: ["codex": snapshot(provider: "codex", windows: [window("w", .weekly, nil)], availability: .stale)]
        )
        XCTAssertNil(sections[0].rows[0].remainingFraction)
    }
}
