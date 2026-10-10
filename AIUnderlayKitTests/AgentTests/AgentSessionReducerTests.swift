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
}
