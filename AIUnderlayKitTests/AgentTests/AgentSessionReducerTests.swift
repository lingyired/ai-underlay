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

    // MARK: - Background questions (Codex's non-blocking question tool)

    func test_questionAskedWaitsAndSurvivesTheToolReturning() {
        let reducer = AgentSessionReducer()
        XCTAssertEqual(reducer.reduce(event(.userQuestionAsked, at: 1)).state, .waitingInput)
        XCTAssertTrue(reducer.session(id: "s1")?.pendingQuestion ?? false)

        // Codex's async question tool returns the moment the question is shown,
        // so the session looks busy again an instant later. The wait must
        // survive that — this is the bug that hid the amber light entirely.
        let running = reducer.reduce(event(.toolUseStarted, at: 2))
        XCTAssertEqual(running.state, .running)
        XCTAssertTrue(running.pendingQuestion, "a tool event must not answer the question for the user")

        let finished = reducer.reduce(event(.toolUseFinished, at: 3))
        XCTAssertTrue(finished.pendingQuestion)
    }

    func test_userPromptSubmitAnswersTheQuestion() {
        let reducer = AgentSessionReducer()
        _ = reducer.reduce(event(.userQuestionAsked, at: 1))
        _ = reducer.reduce(event(.toolUseStarted, at: 2))
        let answered = reducer.reduce(event(.userPromptSubmitted, at: 3))
        XCTAssertFalse(answered.pendingQuestion, "the user's next message is the answer")
        XCTAssertEqual(answered.state, .running)
    }

    func test_sessionEndClearsThePendingQuestion() {
        let reducer = AgentSessionReducer()
        _ = reducer.reduce(event(.userQuestionAsked, at: 1))
        let ended = reducer.reduce(event(.sessionEnd, at: 2))
        XCTAssertFalse(ended.pendingQuestion)
        XCTAssertEqual(ended.state, .idle)
    }

    func test_stoppedSessionStillOwesAnAnswer() {
        // The turn can end while the question is unanswered; the app still shows
        // "待你回复", so the light has to stay until the user answers.
        let reducer = AgentSessionReducer()
        _ = reducer.reduce(event(.userQuestionAsked, at: 1))
        let stopped = reducer.reduce(event(.stopped, at: 2))
        XCTAssertEqual(stopped.state, .completed)
        XCTAssertTrue(stopped.pendingQuestion)
    }

    func test_duplicateQuestionAndOtherSessionsDoNotLeakPending() {
        let reducer = AgentSessionReducer()
        _ = reducer.reduce(event(.userQuestionAsked, session: "a", at: 1))
        _ = reducer.reduce(event(.toolUseStarted, session: "b", at: 2))
        XCTAssertTrue(reducer.session(id: "a")?.pendingQuestion ?? false)
        XCTAssertFalse(reducer.session(id: "b")?.pendingQuestion ?? true)
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

    // MARK: - Signals (the four dimensions together)

    func test_signals_keepWaitingAndWorkingAtTheSameTime() {
        // The bug this guards: collapsing to one `dominant` state made the
        // running spectrum vanish as soon as any session waited for the user.
        let now = Date()
        let sessions = [
            AgentSession(id: "work", providerId: "codex", state: .running, confidence: .exact, observedAt: now),
            AgentSession(id: "work2", providerId: "codex", state: .running, confidence: .exact, observedAt: now),
            AgentSession(id: "ask", providerId: "codex", state: .waitingApproval, confidence: .exact, observedAt: now),
        ]
        let signals = AgentSignals.counting(sessions, now: now)
        XCTAssertEqual(signals.activeCount, 2)
        XCTAssertEqual(signals.waitingCount, 1)
        XCTAssertTrue(signals.hasActive)
        XCTAssertTrue(signals.hasWaiting)
        // The single-state summary still has to pick one, and Waiting wins there.
        XCTAssertEqual(signals.primaryState, .waitingApproval)
    }

    func test_signals_countEveryDimensionSeparately() {
        let now = Date()
        let sessions = [
            AgentSession(id: "a", providerId: "codex", state: .running, confidence: .exact, observedAt: now),
            AgentSession(id: "b", providerId: "codex", state: .waitingInput, confidence: .exact, observedAt: now),
            AgentSession(id: "c", providerId: "codex", state: .error, confidence: .exact, observedAt: now),
            AgentSession(id: "d", providerId: "codex", state: .unknown, confidence: .unknown, observedAt: now),
            AgentSession(id: "e", providerId: "codex", state: .idle, confidence: .exact, observedAt: now),
        ]
        let signals = AgentSignals.counting(sessions, now: now)
        XCTAssertEqual(signals, AgentSignals(activeCount: 1, waitingInputCount: 1, errorCount: 1, unknownCount: 1))
        XCTAssertEqual(signals.primaryState, .error)
    }

    func test_signals_staleRunningIsNotActive() {
        let now = Date()
        let old = now.addingTimeInterval(-(AgentActivityAggregator.runningStaleness + 1))
        let signals = AgentSignals.counting(
            [AgentSession(id: "a", providerId: "codex", state: .running, confidence: .exact, observedAt: old)],
            now: now
        )
        XCTAssertTrue(signals.isEmpty, "silence is not proof of work, and not proof of failure either")
    }

    func test_signals_pendingQuestionShowsEvenWhileTheSessionWorks() {
        // Codex keeps working after asking in the background (`待你回复` next to
        // `思考中`), so the same session has to read as both active and waiting.
        let now = Date()
        let asking = AgentSession(id: "ask", providerId: "codex", state: .running, confidence: .exact,
                                  observedAt: now, pendingQuestion: true)
        let signals = AgentSignals.counting([asking], now: now)
        XCTAssertEqual(signals.activeCount, 1)
        XCTAssertEqual(signals.waitingInputCount, 1)
        XCTAssertTrue(signals.hasActive)
        XCTAssertTrue(signals.hasWaiting)
    }

    func test_signals_pendingQuestionIsNotDoubleCounted() {
        // Right after the question, before any tool fires, the state is already
        // `waitingInput`; the flag must not add a second wait.
        let now = Date()
        let asking = AgentSession(id: "ask", providerId: "codex", state: .waitingInput, confidence: .exact,
                                  observedAt: now, pendingQuestion: true)
        XCTAssertEqual(AgentSignals.counting([asking], now: now), AgentSignals(waitingInputCount: 1))
    }

    func test_signals_pendingQuestionOutlivesAStaleRunningSession() {
        // The agent may go quiet while the question is on screen; the wait is
        // not stale, only the activity is.
        let now = Date()
        let old = now.addingTimeInterval(-(AgentActivityAggregator.runningStaleness + 60))
        let asking = AgentSession(id: "ask", providerId: "codex", state: .running, confidence: .exact,
                                  observedAt: old, pendingQuestion: true)
        let signals = AgentSignals.counting([asking], now: now)
        XCTAssertEqual(signals.activeCount, 0)
        XCTAssertEqual(signals.waitingInputCount, 1)
    }

    // MARK: - Reconciling hook evidence with the live session list

    private func session(_ id: String, _ state: AgentState, at date: Date,
                         confidence: AgentConfidence = .exact) -> AgentSession {
        AgentSession(id: id, providerId: "codex", state: state, confidence: confidence, observedAt: date)
    }

    func test_reconciled_dropsAnAgentNoSessionListKnowsAbout() {
        // Codex fires hooks for background agents (subagents, internal runs)
        // that have no transcript and never appear as a thread. The user saw a
        // green bar with nothing on screen because of exactly this.
        let now = Date()
        let signals = AgentSignals.reconciled(
            hook: [session("ghost", .running, at: now)],
            polled: [session("visible", .idle, at: now, confidence: .inferred)],
            now: now
        )
        // Nothing left to draw: no green, and nil reads the same as all-zero.
        XCTAssertFalse(signals?.hasActive ?? false)
    }

    func test_reconciled_keepsARunningSessionTheListConfirms() {
        let now = Date()
        let signals = AgentSignals.reconciled(
            hook: [session("live", .running, at: now)],
            polled: [session("live", .running, at: now, confidence: .inferred)],
            now: now
        )
        XCTAssertEqual(signals?.activeCount, 1)
    }

    func test_reconciled_idleFromALaterWriteEndsTheGreen() {
        // The turn ended but no `Stop` hook arrived; the live list already saw
        // the finished transcript, so the bar must not stay green for the whole
        // staleness window.
        let now = Date()
        let lastHookEvent = now.addingTimeInterval(-5)
        let signals = AgentSignals.reconciled(
            hook: [session("live", .running, at: lastHookEvent)],
            polled: [session("live", .idle, at: now, confidence: .inferred)],
            now: now
        )
        XCTAssertFalse(signals?.hasActive ?? false)
    }

    func test_reconciled_olderIdleDoesNotEndAFreshRunningSession() {
        // The live list lags behind the hooks; its stale "idle" must not erase
        // a session the hooks just reported working.
        let now = Date()
        let signals = AgentSignals.reconciled(
            hook: [session("live", .running, at: now)],
            polled: [session("live", .idle, at: now.addingTimeInterval(-30), confidence: .inferred)],
            now: now
        )
        XCTAssertEqual(signals?.activeCount, 1)
    }

    func test_reconciled_quietLongToolCallStaysRunningWhileTheListConfirmsIt() {
        // A build or a notarization writes no hook and no transcript record for
        // minutes; the hook goes stale while the agent is still working. The
        // list's reading of the same session is the evidence that keeps it on.
        let now = Date()
        let signals = AgentSignals.reconciled(
            hook: [session("live", .running, at: now.addingTimeInterval(-600))],
            polled: [session("live", .running, at: now.addingTimeInterval(-240), confidence: .inferred)],
            now: now
        )
        XCTAssertEqual(signals?.activeCount, 1)
    }

    func test_reconciled_aStaleRunningClaimFromTheListDoesNotHoldTheLight() {
        // The list's own evidence is old: the session has not been written to
        // for over the window, so an open-looking turn proves nothing now.
        let now = Date()
        let signals = AgentSignals.reconciled(
            hook: [session("live", .running, at: now.addingTimeInterval(-3600))],
            polled: [session("live", .running, at: now.addingTimeInterval(-1800), confidence: .inferred)],
            now: now
        )
        XCTAssertFalse(signals?.hasActive ?? false)
    }

    func test_reconciled_neverGatesAWait() {
        // Waiting states are explicit asks; hiding a pending approval because a
        // coarse list disagrees would be worse than an extra light.
        let now = Date()
        let signals = AgentSignals.reconciled(
            hook: [session("ghost", .waitingApproval, at: now)],
            polled: [],
            now: now
        )
        XCTAssertEqual(signals?.waitingApprovalCount, 1)
    }

    func test_reconciled_countsSessionsOnlyTheListKnows() {
        // Hooks installed but quiet for every session they know: a session the
        // hooks never saw still counts, so a stale hook install does not go dark.
        let now = Date()
        let signals = AgentSignals.reconciled(
            hook: [session("old", .idle, at: now.addingTimeInterval(-3600))],
            polled: [session("other", .running, at: now, confidence: .inferred)],
            now: now
        )
        XCTAssertEqual(signals?.activeCount, 1)
    }

    func test_reconciled_anUnreadableTranscriptDoesNotVetoTheHooks() {
        // Codex's local reader reports `unknown` when it cannot read a
        // transcript. That must not be treated as "the transcript says the turn
        // ended": choosing between a light that stays on and an agent that
        // disappears, we keep the light.
        let now = Date()
        let signals = AgentSignals.reconciled(
            hook: [session("live", .running, at: now)],
            polled: [session("live", .unknown, at: now, confidence: .unknown)],
            now: now
        )
        XCTAssertEqual(signals?.activeCount, 1)
    }

    func test_reconciled_withoutAFreshListTrustsTheHooks() {
        // No engine / no `codexbar` output: hooks are all we have, and a live
        // session must not be dropped just because nothing corroborates it.
        let now = Date()
        let signals = AgentSignals.reconciled(hook: [session("live", .running, at: now)], polled: [], now: now)
        XCTAssertEqual(signals?.activeCount, 1)
    }

    func test_reconciled_nothingAnywhereIsNil() {
        let now = Date()
        XCTAssertNil(AgentSignals.reconciled(hook: [], polled: [], now: now))
        XCTAssertNil(AgentSignals.reconciled(
            hook: [session("old", .idle, at: now.addingTimeInterval(-3600))],
            polled: [], now: now))
    }

    func test_signals_fromASingleState() {
        XCTAssertEqual(AgentSignals(state: .running), AgentSignals(activeCount: 1))
        XCTAssertEqual(AgentSignals(state: .waitingApproval), AgentSignals(waitingApprovalCount: 1))
        XCTAssertEqual(AgentSignals(state: .error), AgentSignals(errorCount: 1))
        XCTAssertEqual(AgentSignals(state: .completed), AgentSignals(completedCount: 1))
        XCTAssertTrue(AgentSignals(state: .idle).isEmpty)
    }
}
