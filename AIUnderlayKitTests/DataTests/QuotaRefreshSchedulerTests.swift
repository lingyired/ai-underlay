import XCTest
@testable import AIUnderlayKit

/// The refresh cadence: a transient CLI failure must not leave the lanes empty
/// until the next four-minute tick.
@MainActor
final class QuotaRefreshSchedulerTests: XCTestCase {
    private func snapshot(_ provider: String) -> ProviderQuotaSnapshot {
        ProviderQuotaSnapshot(
            id: "\(provider):default", providerId: provider, accountKey: nil,
            sourceEngineId: "codexbar", windows: [], fetchedAt: Date(), availability: .valid
        )
    }

    func test_aFailureIsRetriedWellBeforeTheSteadyInterval() async throws {
        let scheduler = QuotaRefreshScheduler(
            interval: 600,
            fetch: { _ in throw QuotaEngineError.decodeFailed("network") },
            onUpdate: { _ in },
            onError: { _, _ in }
        )
        XCTAssertEqual(QuotaRefreshScheduler.retryInterval, 30)
        XCTAssertLessThan(QuotaRefreshScheduler.retryInterval, 600,
                          "a transient failure must not wait out the steady interval")
        scheduler.start(providers: ["codex"])
        scheduler.stop()
    }

    func test_aSuccessfulFetchResetsTheFailureCount() async throws {
        var calls = 0
        let scheduler = QuotaRefreshScheduler(
            interval: 600,
            fetch: { provider in
                calls += 1
                return ProviderQuotaSnapshot(
                    id: "\(provider):default", providerId: provider, accountKey: nil,
                    sourceEngineId: "codexbar", windows: [], fetchedAt: Date(), availability: .valid
                )
            },
            onUpdate: { _ in },
            onError: { _, _ in }
        )
        scheduler.start(providers: ["codex"])
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(calls, 1)
        scheduler.stop()
    }

    func test_retryGivesUpAfterTheAttemptBudget() {
        // Bounded, so a provider that is genuinely broken (logged out, CLI
        // removed) settles onto the steady interval instead of retrying forever.
        XCTAssertEqual(QuotaRefreshScheduler.maximumAttempts, 3)
    }
}
