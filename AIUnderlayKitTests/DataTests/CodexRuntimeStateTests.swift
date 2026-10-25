import XCTest
@testable import AIUnderlayKit

final class CodexRuntimeStateTests: XCTestCase {
    private let id = "019a0000-0000-7000-8000-000000000001"
    private let other = "019a0000-0000-7000-8000-000000000002"
    private let now = Date(timeIntervalSince1970: 10_000)

    private func frame(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value.merging(["hostId": "local"]) { first, _ in first })
    }

    private func connect(_ state: inout CodexRuntimeState, at date: Date? = nil) throws {
        state.consume(try frame(["kind": "status", "connected": true]), at: date ?? now)
    }

    private func event(
        _ method: String, into state: inout CodexRuntimeState,
        values: [String: Any] = [:], thread: String? = nil, at date: Date? = nil
    ) throws {
        let event = ["method": method, "threadId": thread ?? id].merging(values) { _, value in value }
        state.consume(try frame(["kind": "runtimeBatch", "events": [event]]), at: date ?? now)
    }

    private func attention(_ kinds: [String], into state: inout CodexRuntimeState, at date: Date? = nil) throws {
        state.consume(try frame(["kind": "attention", "threadId": id,
                                 "requests": kinds.map { ["kind": $0] }]), at: date ?? now)
    }

    func test_asyncQuestionKeepsRunningAndClearsWhenAnsweredWithoutHook() throws {
        var state = CodexRuntimeState()
        try connect(&state)
        try event("turn/attached", into: &state, values: ["turnId": "turn"])
        try attention(["input"], into: &state)
        var signals = AgentSignals.counting(state.snapshot(at: now).sessions, now: now)
        XCTAssertEqual(signals.activeCount, 1)
        XCTAssertEqual(signals.waitingInputCount, 1)

        try event("item/completed", into: &state)
        signals = AgentSignals.counting(state.snapshot(at: now).sessions, now: now)
        XCTAssertEqual(signals.waitingInputCount, 1, "ordinary tool completion cannot answer a question")
        try attention([], into: &state)
        signals = AgentSignals.counting(state.snapshot(at: now).sessions, now: now)
        XCTAssertEqual(signals.activeCount, 1)
        XCTAssertEqual(signals.waitingCount, 0)
    }

    func test_approvalIsBlockingAndResolvesFromTheRequestStream() throws {
        var state = CodexRuntimeState()
        try connect(&state)
        try event("turn/started", into: &state, values: ["turnId": "turn"])
        try attention(["approval"], into: &state)
        let waiting = AgentSignals.counting(state.snapshot(at: now).sessions, now: now)
        XCTAssertEqual(waiting.waitingApprovalCount, 1)
        XCTAssertEqual(waiting.activeCount, 0)
        try attention([], into: &state)
        XCTAssertEqual(AgentSignals.counting(state.snapshot(at: now).sessions, now: now).activeCount, 1)
    }

    func test_idleBookkeepingCannotEndAnObservedTurn() throws {
        var state = CodexRuntimeState()
        try connect(&state)
        try event("turn/attached", into: &state, values: ["turnId": "turn"])
        try event("thread/status/changed", into: &state, values: ["status": "idle", "flags": []])
        XCTAssertEqual(state.snapshot(at: now).sessions.first?.state, .running)
        try event("turn/completed", into: &state, values: ["turnId": "turn", "status": "completed"])
        try event("stream/released", into: &state)
        XCTAssertFalse(AgentSignals.counting(state.snapshot(at: now).sessions, now: now).hasActive)
        XCTAssertEqual(state.snapshot(at: now.addingTimeInterval(30)).sessions.first?.state, .idle)
    }

    func test_disconnectDropsRunningWithoutInventingCompletionAndKeepsQuestion() throws {
        var state = CodexRuntimeState()
        try connect(&state)
        try event("turn/started", into: &state, values: ["turnId": "turn"])
        state.disconnected()
        XCTAssertEqual(state.snapshot(at: now).status, .fallback)
        XCTAssertTrue(state.snapshot(at: now).sessions.isEmpty)

        try connect(&state)
        try event("turn/attached", into: &state, values: ["turnId": "turn"])
        try attention(["input"], into: &state)
        state.disconnected()
        let signals = AgentSignals.counting(state.snapshot(at: now).sessions, now: now)
        XCTAssertEqual(signals.waitingInputCount, 1)
        XCTAssertEqual(signals.activeCount, 0)
        XCTAssertEqual(signals.completedCount, 0)
    }

    func test_unloadedOwnerFallsBackOnlyForThatThread() throws {
        var state = CodexRuntimeState()
        try connect(&state)
        try event("turn/attached", into: &state, values: ["turnId": "a"])
        try event("turn/attached", into: &state, values: ["turnId": "b"], thread: other)
        state.consume(try frame(["kind": "streamInvalidated", "threadId": id]), at: now)
        XCTAssertEqual(state.snapshot(at: now).sessions.map(\.id), [other])
    }

    func test_healthyHeartbeatKeepsLongToolRunningButSilenceDoesNot() throws {
        var state = CodexRuntimeState()
        try connect(&state)
        try event("turn/attached", into: &state, values: ["turnId": "turn"])
        let later = now.addingTimeInterval(900)
        XCTAssertEqual(state.snapshot(at: later).status, .fallback)
        XCTAssertTrue(state.snapshot(at: later).sessions.isEmpty)
        try connect(&state, at: later)
        XCTAssertEqual(AgentSignals.counting(state.snapshot(at: later).sessions, now: later).activeCount, 1)
    }

    func test_usageAndHistoricalCompletionDoNotCreateActivity() throws {
        var state = CodexRuntimeState()
        try connect(&state)
        try event("thread/tokenUsage/updated", into: &state, values: ["outputTokens": 100])
        try event("turn/completed", into: &state, values: ["turnId": "old", "status": "completed"])
        try event("thread/status/changed", into: &state, values: ["status": "active"])
        XCTAssertTrue(state.snapshot(at: now).sessions.isEmpty)
    }

    func test_reviewMetadataNeverBecomesVisibleAndPrivateValuesAreNotRetained() throws {
        var state = CodexRuntimeState()
        try connect(&state)
        try event("metadata", into: &state, values: ["source": "guardian_review", "name": "PRIVATE", "cwd": "PRIVATE"])
        try event("turn/attached", into: &state, values: ["turnId": "turn"])
        XCTAssertTrue(state.snapshot(at: now).sessions.isEmpty)
        XCTAssertFalse(String(describing: state).contains("PRIVATE"))
        state.consume(try frame(["kind": "status", "hostId": "remote", "connected": false]), at: now)
        XCTAssertEqual(state.snapshot(at: now).status, .connected)
    }

    func test_realTimeAuthorityIsPerThreadAndConfirmedEndOverridesOldLog() {
        let live = AgentSession(id: id, providerId: "codex", state: .idle, confidence: .exact, observedAt: now)
        let result = CodexActivityResolver.sessions(runtime: [live], polled: [log(id, .running), log(other, .running)])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.id == id }?.state, .idle)
        XCTAssertEqual(result.first { $0.id == other }?.state, .running)
    }

    func test_confirmedLogEndingResolvesAWaitRetainedAcrossDisconnect() {
        let retained = AgentSession(id: id, providerId: "codex", state: .waitingInput,
                                    confidence: .inferred, observedAt: now.addingTimeInterval(-10), pendingQuestion: true)
        let result = CodexActivityResolver.sessions(runtime: [retained], polled: [log(id, .idle)])
        XCTAssertEqual(AgentSignals.counting(result, now: now).waitingCount, 0)
    }

    func test_releasedTerminalCannotHideANewerLogTurn() {
        let ended = AgentSession(id: id, providerId: "codex", state: .idle,
                                 confidence: .inferred, observedAt: now.addingTimeInterval(-10))
        let result = CodexActivityResolver.sessions(runtime: [ended], polled: [log(id, .running)])
        XCTAssertEqual(AgentSignals.counting(result, now: now).activeCount, 1)
    }

    private func log(_ id: String, _ state: AgentState) -> AgentSessionInfo {
        AgentSessionInfo(id: id, provider: "codex", sessionName: "", projectName: nil,
                         state: state == .running ? "active" : "idle", lastActivityAt: now, source: "localRollout")
    }
}
