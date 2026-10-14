import XCTest
@testable import AIUnderlayKit

final class AgentStateStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("agent-state-\(UUID().uuidString).json")
    }

    func test_saveLoadRoundTrip() {
        let store = AgentStateStore(fileURL: tempURL())
        let session = AgentSession(id: "s1", providerId: "codex", state: .waitingInput,
                                   confidence: .exact, observedAt: Date(timeIntervalSince1970: 1000))
        store.save(AgentSessionReducer.Snapshot(sessions: [session], lastEventAt: ["s1": session.observedAt]))

        let loaded = store.load()
        XCTAssertEqual(loaded?.sessions, [session])
    }

    func test_loadMissingReturnsNil() {
        XCTAssertNil(AgentStateStore(fileURL: tempURL()).load())
    }

    func test_load_oldSnapshotWithoutPendingQuestionKey() throws {
        // Snapshots written before `pendingQuestion` existed must still decode —
        // otherwise an upgrade would silently throw away a pending wait.
        let url = tempURL()
        let json = """
        {"sessions":[{"id":"s1","providerId":"codex","state":"waitingInput","confidence":"exact","observedAt":0}],"lastEventAt":{}}
        """
        try Data(json.utf8).write(to: url)
        let loaded = AgentStateStore(fileURL: url).load()
        XCTAssertEqual(loaded?.sessions.count, 1)
        XCTAssertFalse(loaded?.sessions.first?.pendingQuestion ?? true)
    }

    func test_restore_survivesRestartForWaitingSession() {
        // The core scenario: a session is waiting, the app restarts, and the
        // waiting light must come back (a wait never re-fires an event).
        let reducer = AgentSessionReducer()
        let waiting = AgentSession(id: "w", providerId: "codex", state: .waitingInput,
                                   confidence: .exact, observedAt: Date())
        reducer.restore(AgentSessionReducer.Snapshot(sessions: [waiting], lastEventAt: ["w": waiting.observedAt]))
        XCTAssertEqual(reducer.allSessions().count, 1)
        XCTAssertEqual(AgentActivityAggregator.aggregate(reducer.allSessions()).dominant, .waitingInput)
    }

    func test_restore_dropsAncientEntries() {
        let reducer = AgentSessionReducer()
        let ancient = AgentSession(id: "old", providerId: "codex", state: .waitingInput,
                                   confidence: .exact,
                                   observedAt: Date().addingTimeInterval(-(7 * 3600)))
        reducer.restore(AgentSessionReducer.Snapshot(sessions: [ancient], lastEventAt: [:]))
        XCTAssertTrue(reducer.allSessions().isEmpty, "a snapshot from days ago must not resurrect zombie lights")
    }

    func test_restore_keepsRunningForStalenessToHandle() {
        // A recent running session is restored as-is; the staleness rule (not
        // the restore cutoff) decides whether it still counts as running.
        let reducer = AgentSessionReducer()
        let running = AgentSession(id: "r", providerId: "codex", state: .running,
                                   confidence: .exact, observedAt: Date().addingTimeInterval(-10))
        reducer.restore(AgentSessionReducer.Snapshot(sessions: [running], lastEventAt: [:]))
        XCTAssertEqual(reducer.allSessions().first?.state, .running)
    }
}
