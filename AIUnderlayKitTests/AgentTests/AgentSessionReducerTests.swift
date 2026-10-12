import XCTest
@testable import AIUnderlayKit

final class AgentSessionReducerTests: XCTestCase {
    private func event(_ kind: AgentEventKind, session: String = "s1", at: TimeInterval) -> AgentEvent {
        AgentEvent(providerId: "claude", sessionId: session, kind: kind,
                   at: Date(timeIntervalSince1970: at))
    }

    func test_runningThenCompleted() {
        let reducer = AgentSessionReducer()
        XCTAssertEqual(reducer.reduce(event(.userPromptSubmitted, at: 1)).state, .running)
        XCTAssertEqual(reducer.reduce(event(.stopped, at: 2)).state, .completed)
    }

    func test_reviewFocus4_staleEventDoesNotFlipCompleted() {
        let reducer = AgentSessionReducer()
        _ = reducer.reduce(event(.stopped, at: 10))          // completed at t=10
        // A late tool event with an earlier timestamp must not resurrect running.
        let result = reducer.reduce(event(.toolUseStarted, at: 5))
        XCTAssertEqual(result.state, .completed, "a stale event must not overwrite newer state")
    }

    func test_duplicateEventsAreIdempotent() {
        let reducer = AgentSessionReducer()
        let first = reducer.reduce(event(.permissionRequested, at: 3))
        let second = reducer.reduce(event(.permissionRequested, at: 3))
        XCTAssertEqual(first.state, second.state)
        XCTAssertEqual(second.state, .waitingApproval)
    }

    func test_unknownKind_isUnknownNotIdle() {
        let reducer = AgentSessionReducer()
        let result = reducer.reduce(event(.unknown, at: 1))
        XCTAssertEqual(result.state, .unknown)
        XCTAssertEqual(result.confidence, .unknown)
    }

    func test_notificationMapsToWaitingInput() {
        let reducer = AgentSessionReducer()
        XCTAssertEqual(reducer.reduce(event(.notification, at: 1)).state, .waitingInput)
    }

    // MARK: - Aggregation

    func test_aggregate_twoRunningOneWaitingApproval() {
        let sessions = [
            AgentSession(id: "a", providerId: "claude", state: .running, confidence: .exact, observedAt: Date()),
            AgentSession(id: "b", providerId: "claude", state: .running, confidence: .exact, observedAt: Date()),
            AgentSession(id: "c", providerId: "claude", state: .waitingApproval, confidence: .exact, observedAt: Date()),
        ]
        let aggregate = AgentActivityAggregator.aggregate(sessions)
        XCTAssertEqual(aggregate.dominant, .waitingApproval)
        XCTAssertEqual(aggregate.counts[.running], 2)
        XCTAssertEqual(aggregate.counts[.waitingApproval], 1)
    }

    func test_aggregate_unknownIsCountedNotIgnored() {
        let sessions = [
            AgentSession(id: "a", providerId: "codex", state: .unknown, confidence: .unknown, observedAt: Date()),
            AgentSession(id: "b", providerId: "claude", state: .running, confidence: .exact, observedAt: Date()),
        ]
        let aggregate = AgentActivityAggregator.aggregate(sessions)
        XCTAssertEqual(aggregate.dominant, .running)
        XCTAssertEqual(aggregate.unknownCount, 1, "unknown sessions must be reported, not hidden")
    }

    func test_aggregate_errorOutranksEverything() {
        let sessions = [
            AgentSession(id: "a", providerId: "claude", state: .waitingApproval, confidence: .exact, observedAt: Date()),
            AgentSession(id: "b", providerId: "claude", state: .error, confidence: .exact, observedAt: Date()),
        ]
        XCTAssertEqual(AgentActivityAggregator.aggregate(sessions).dominant, .error)
    }

    // MARK: - Staleness

    func test_staleRunningDecaysToIdle() {
        let now = Date()
        let old = now.addingTimeInterval(-(AgentActivityAggregator.runningStaleness + 1))
        let session = AgentSession(id: "a", providerId: "codex", state: .running,
                                   confidence: .exact, observedAt: old)
        XCTAssertEqual(AgentActivityAggregator.effectiveState(session, now: now), .idle)
    }

    func test_freshRunningStaysRunning() {
        let now = Date()
        let recent = now.addingTimeInterval(-10)
        let session = AgentSession(id: "a", providerId: "codex", state: .running,
                                   confidence: .exact, observedAt: recent)
        XCTAssertEqual(AgentActivityAggregator.effectiveState(session, now: now), .running)
    }

    func test_staleCompletedDecaysToIdle() {
        let now = Date()
        let old = now.addingTimeInterval(-(AgentActivityAggregator.completedStaleness + 1))
        let session = AgentSession(id: "a", providerId: "codex", state: .completed,
                                   confidence: .exact, observedAt: old)
        XCTAssertEqual(AgentActivityAggregator.effectiveState(session, now: now), .idle)
    }

    func test_freshCompletedStaysCompleted() {
        let now = Date()
        let recent = now.addingTimeInterval(-5)
        let session = AgentSession(id: "a", providerId: "codex", state: .completed,
                                   confidence: .exact, observedAt: recent)
        XCTAssertEqual(AgentActivityAggregator.effectiveState(session, now: now), .completed)
    }

    func test_staleCompletedDoesNotBeatFreshRunning() {
        let now = Date()
        let sessions = [
            AgentSession(id: "stale", providerId: "codex", state: .completed, confidence: .exact,
                         observedAt: now.addingTimeInterval(-(AgentActivityAggregator.completedStaleness + 1))),
            AgentSession(id: "running", providerId: "codex", state: .running, confidence: .exact,
                         observedAt: now.addingTimeInterval(-5)),
        ]
        XCTAssertEqual(AgentActivityAggregator.aggregate(sessions, now: now).dominant, .running)
    }

    func test_waitingNeverDecaysNoMatterHowOld() {
        // The whole point of a "needs you" light is to survive until you act —
        // a wait from an hour ago is still a wait.
        let now = Date()
        let ancient = now.addingTimeInterval(-3600)
        for state in [AgentState.waitingInput, .waitingApproval, .error] {
            let session = AgentSession(id: "a", providerId: "codex", state: state,
                                       confidence: .exact, observedAt: ancient)
            XCTAssertEqual(AgentActivityAggregator.effectiveState(session, now: now), state,
                           "\(state) must not decay")
        }
    }

    func test_staleRunningDoesNotBeatAFreshWaitingSession() {
        // A silent, stale "running" must never keep the bar green while another
        // session is genuinely waiting on the user.
        let now = Date()
        let sessions = [
            AgentSession(id: "stale", providerId: "codex", state: .running, confidence: .exact,
                         observedAt: now.addingTimeInterval(-(AgentActivityAggregator.runningStaleness + 60))),
            AgentSession(id: "waiting", providerId: "codex", state: .waitingInput, confidence: .exact,
                         observedAt: now.addingTimeInterval(-5)),
        ]
        let aggregate = AgentActivityAggregator.aggregate(sessions, now: now)
        XCTAssertEqual(aggregate.dominant, .waitingInput)
    }

    func test_allStaleRunningAggregatesToIdle() {
        let now = Date()
        let old = now.addingTimeInterval(-(AgentActivityAggregator.runningStaleness + 1))
        let sessions = [
            AgentSession(id: "a", providerId: "codex", state: .running, confidence: .exact, observedAt: old),
            AgentSession(id: "b", providerId: "codex", state: .running, confidence: .exact, observedAt: old),
        ]
        XCTAssertEqual(AgentActivityAggregator.aggregate(sessions, now: now).dominant, .idle)
    }
}
