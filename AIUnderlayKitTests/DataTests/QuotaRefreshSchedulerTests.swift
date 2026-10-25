import XCTest
@testable import AIUnderlayKit

/// The refresh cadence: a transient CLI failure must not leave the lanes empty
/// until the next four-minute tick.
@MainActor
final class QuotaRefreshSchedulerTests: XCTestCase {
    func test_refreshReportsItsActualInFlightState() async {
        var resumeFetch: CheckedContinuation<ProviderQuotaSnapshot, Never>?
        var states: [Bool] = []
        let scheduler = QuotaRefreshScheduler(
            fetch: { _ in await withCheckedContinuation { resumeFetch = $0 } },
            onUpdate: { _ in }, onError: { _, _ in },
            onRefreshing: { states.append($0) }
        )
        scheduler.start(providers: ["codex"])
        while resumeFetch == nil { await Task.yield() }
        XCTAssertEqual(states.last, true)
        resumeFetch?.resume(returning: snapshot("codex"))
        while states.last == true { await Task.yield() }
        XCTAssertEqual(states.suffix(2), [true, false])
        scheduler.stop()
    }

    func test_stoppingIgnoresAResultFromTheOldConnection() async {
        var resumeFetch: CheckedContinuation<ProviderQuotaSnapshot, Never>?
        var applied: [ProviderQuotaSnapshot] = []
        let scheduler = QuotaRefreshScheduler(
            fetch: { _ in await withCheckedContinuation { resumeFetch = $0 } },
            onUpdate: { applied.append($0) }, onError: { _, _ in }
        )
        scheduler.start(providers: ["codex"])
        while resumeFetch == nil { await Task.yield() }
        scheduler.stop()
        resumeFetch?.resume(returning: snapshot("codex"))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(applied.isEmpty, "a removed connection must not publish a late success")
    }

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
