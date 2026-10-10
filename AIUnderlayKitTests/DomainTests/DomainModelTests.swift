import XCTest
@testable import AIUnderlayKit

final class DomainModelTests: XCTestCase {
    func test_quotaWindow_codableRoundTripPreservesNilRemaining() throws {
        let window = QuotaWindow(
            id: "session", label: "5h", kind: .session, durationSeconds: 18000,
            remainingFraction: nil, resetAt: nil, expectedRemainingFraction: nil,
            updatedAt: nil, availability: .unavailable
        )
        let data = try JSONEncoder().encode(window)
        let back = try JSONDecoder().decode(QuotaWindow.self, from: data)
        XCTAssertEqual(back, window)
        XCTAssertNil(back.remainingFraction)
    }

    func test_windowKind_fromDuration() {
        XCTAssertEqual(QuotaWindow.kind(forWindowMinutes: 300), .session)
        XCTAssertEqual(QuotaWindow.kind(forWindowMinutes: 10080), .weekly)
        XCTAssertEqual(QuotaWindow.kind(forWindowMinutes: 43200), .monthly)
        XCTAssertEqual(QuotaWindow.kind(forWindowMinutes: 60), .custom)
        XCTAssertEqual(QuotaWindow.kind(forWindowMinutes: nil), .custom)
    }

    func test_windowsLongestFirst_ordersByDuration() {
        let snapshot = ProviderQuotaSnapshot(
            id: "codex:default", providerId: "codex", accountKey: nil,
            sourceEngineId: "codexbar", windows: [
                QuotaWindow(id: "s", label: "5h", kind: .session, durationSeconds: 18000,
                            remainingFraction: 0.5, resetAt: nil, expectedRemainingFraction: nil,
                            updatedAt: nil, availability: .valid),
                QuotaWindow(id: "w", label: "Week", kind: .weekly, durationSeconds: 604800,
                            remainingFraction: 0.5, resetAt: nil, expectedRemainingFraction: nil,
                            updatedAt: nil, availability: .valid),
            ], fetchedAt: Date(), availability: .valid
        )
        XCTAssertEqual(snapshot.windowsLongestFirst.map(\.id), ["w", "s"])
    }

    func test_displayConfiguration_codableRoundTrip() throws {
        let config = DisplayConfiguration(
            displayID: "3", isEnabled: true, layout: .dual, anchor: .notch,
            singleDirection: .trailingToLeading, singleProviderId: "codex",
            assignments: [SideAssignment(side: .left, providerId: "codex"),
                          SideAssignment(side: .right, providerId: "claude", accountKey: "a1")]
        )
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(DisplayConfiguration.self, from: data)
        XCTAssertEqual(back, config)
    }

    func test_agentSession_codableRoundTrip() throws {
        let session = AgentSession(id: "s1", providerId: "claude", state: .waitingApproval,
                                   confidence: .exact, observedAt: Date())
        let data = try JSONEncoder().encode(session)
        let back = try JSONDecoder().decode(AgentSession.self, from: data)
        XCTAssertEqual(back, session)
    }
}
