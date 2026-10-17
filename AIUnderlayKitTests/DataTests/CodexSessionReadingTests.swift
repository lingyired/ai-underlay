import XCTest
import SQLite3
@testable import AIUnderlayKit

/// The local Codex session reading: the app's own thread index plus the turn
/// boundaries the rollout files write. The case that motivated it — a session
/// started days ago, still working, invisible to a directory scan — is the
/// first test below.
final class CodexSessionReadingTests: XCTestCase {
    private var home: URL!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("aiu-codex-sessions-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    // MARK: - Fixtures

    private func rolloutURL(day: String, id: String) -> URL {
        let directory = home.appendingPathComponent("sessions/2026/\(day)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("rollout-2026-\(day.replacingOccurrences(of: "/", with: "-"))T08-08-16-\(id).jsonl")
    }

    private func boundary(_ kind: String, turn: String = "11111111-1111-7111-8111-111111111111") -> String {
        """
        {"timestamp":"2026-10-14T16:00:00.000Z","type":"event_msg","payload":{"type":"\(kind)","turn_id":"\(turn)"}}
        """
    }

    @discardableResult
    private func writeRollout(_ contents: String, to url: URL, modified: Date? = nil) -> URL {
        try? Data(contents.utf8).write(to: url)
        if let modified {
            try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    private struct ThreadRow {
        var id: String
        var rollout: URL
        var name: String?
        var title: String?
        var cwd: String?
        var archived = 0
        var threadSource: String? = "user"
        var source: String? = "vscode"
        var recencyMilliseconds = Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func writeIndex(_ rows: [ThreadRow], version: Int = 5) throws {
        let url = home.appendingPathComponent("state_\(version).sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        defer { sqlite3_close(handle) }
        let schema = """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL, source TEXT NOT NULL, model_provider TEXT NOT NULL,
            cwd TEXT, title TEXT, archived INTEGER NOT NULL DEFAULT 0,
            recency_at_ms INTEGER NOT NULL, thread_source TEXT, name TEXT
        );
        """
        XCTAssertEqual(sqlite3_exec(handle, schema, nil, nil, nil), SQLITE_OK)
        for row in rows {
            func quote(_ value: String?) -> String {
                guard let value else { return "NULL" }
                return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
            }
            let insert = """
            INSERT INTO threads (id, rollout_path, created_at, updated_at, source, model_provider,
                                 cwd, title, archived, recency_at_ms, thread_source, name)
            VALUES (\(quote(row.id)), \(quote(row.rollout.path)), 0, 0, \(quote(row.source)),
                    'openai', \(quote(row.cwd)), \(quote(row.title)), \(row.archived),
                    \(row.recencyMilliseconds), \(quote(row.threadSource)), \(quote(row.name)));
            """
            XCTAssertEqual(sqlite3_exec(handle, insert, nil, nil, nil), SQLITE_OK)
        }
    }

    // MARK: - The regression: a long-lived session in an old directory

    func test_readerRecognizesAResumedSessionInAnOldDayDirectory() async throws {
        // Started 2026-10-13, still working now: `codexbar sessions` missed
        // exactly this shape, so the light never came on for it.
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/13", id: id)
        writeRollout(boundary("task_started") + "\n", to: url)
        try writeIndex([ThreadRow(id: id, rollout: url, name: "修复 Issue 72 helper 退出",
                                  title: "ignored", cwd: "/Users/someone/Documents/aiwork/status-trio")])

        let sessions = await CodexLocalSessionReader(home: home).sessions()
        let session = try XCTUnwrap(sessions.first { $0.id == id })
        XCTAssertEqual(session.provider, "codex")
        XCTAssertEqual(session.state, "active")
        XCTAssertEqual(session.agentState, .running)
        XCTAssertEqual(session.sessionName, "修复 Issue 72 helper 退出")
        XCTAssertEqual(session.projectName, "status-trio")
    }

    func test_readerReportsAFinishedTurnAsIdle() async throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        writeRollout([boundary("task_started"), boundary("task_complete"), ""].joined(separator: "\n"), to: url)
        try writeIndex([ThreadRow(id: id, rollout: url, title: "done")])

        let sessions = await CodexLocalSessionReader(home: home).sessions()
        XCTAssertEqual(sessions.first { $0.id == id }?.state, "idle")
    }

    func test_readerIgnoresArchivedAndInternalThreads() async throws {
        let archived = UUID().uuidString.lowercased()
        let subagent = UUID().uuidString.lowercased()
        let review = UUID().uuidString.lowercased()
        let live = UUID().uuidString.lowercased()

        var rows: [ThreadRow] = []
        for (id, archived_, threadSource, source) in [
            (archived, 1, "user", "vscode"),
            (subagent, 0, "subagent", "{\"subagent\":{\"thread_spawn\":{\"parent_thread_id\":\"x\"}}}"),
            (review, 0, "guardian_review", "vscode"),
            (live, 0, "user", "vscode"),
        ] {
            let url = rolloutURL(day: "10/14", id: id)
            writeRollout(boundary("task_started") + "\n", to: url)
            rows.append(ThreadRow(id: id, rollout: url, title: id, archived: archived_,
                                  threadSource: threadSource, source: source))
        }
        try writeIndex(rows)

        let sessions = await CodexLocalSessionReader(home: home).sessions()
        XCTAssertEqual(sessions.map(\.id), [live])
    }

    // MARK: - Reading the rollout

    func test_tailReaderFindsABoundaryFarBeyondTheLastChunk() throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        // The turn start sits ~700 KB behind the end: a long tool call writes
        // nothing in between, so only a bounded scan back can see it. The
        // filler is ordinary transcript, not a turn-scoped record, so the
        // boundary is the only claim the file makes.
        let filler = String(repeating: "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\"}}\n", count: 7000)
        writeRollout(boundary("task_started") + "\n" + filler, to: url)

        var reader = CodexRolloutTailReader()
        XCTAssertEqual(reader.phase(of: url), .running)

        // A later completion still wins, and is picked up incrementally.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((boundary("task_complete") + "\n").utf8))
        try handle.close()
        XCTAssertEqual(reader.phase(of: url), .ended)
    }

    func test_tailReaderDoesNotConsumeAPartiallyWrittenLine() throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        writeRollout(boundary("task_started") + "\n", to: url)
        var reader = CodexRolloutTailReader()
        XCTAssertEqual(reader.phase(of: url), .running)

        // Half of a completion record has landed; it must not be skipped.
        let complete = boundary("task_complete") + "\n"
        let partial = String(complete.prefix(complete.count / 2))
        try append(partial, to: url)
        XCTAssertEqual(reader.phase(of: url), .running)

        // Once the rest arrives the same reader must still see it, which only
        // works if the partial line was left unconsumed.
        try append(String(complete.dropFirst(partial.count)), to: url)
        XCTAssertEqual(reader.phase(of: url), .ended)
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    func test_tailReaderIgnoresBoundaryWordsInsideMessageText() throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        let message = """
        {"timestamp":"2026-10-14T16:00:01.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"I will write task_complete next"}]}}
        """
        writeRollout(boundary("task_started") + "\n" + message + "\n", to: url)
        var reader = CodexRolloutTailReader()
        XCTAssertEqual(reader.phase(of: url), .running)
    }

    func test_tailReaderReportsUnknownForAFileWithoutBoundaries() throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        writeRollout("{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\"}}\n", to: url)
        var reader = CodexRolloutTailReader()
        XCTAssertEqual(reader.phase(of: url), .unknown)
    }

    // MARK: - The regression: a turn whose start fell out of the scan window

    private func activity(turn: String, kind: String = "item_completed", at: String) -> String {
        """
        {"timestamp":"\(at)","type":"event_msg","payload":{"type":"\(kind)","thread_id":"x","turn_id":"\(turn)","item":{"type":"CommandExecution"}}}
        """
    }

    /// A long-lived thread keeps every turn in one file. After a busy day the
    /// running turn's `task_started` can be tens of megabytes back — outside
    /// the bounded window — while the turn is still writing records at the end.
    /// Reporting `unknown` there meant "nobody is running", and that is exactly
    /// how a session working on a long build stayed invisible.
    func test_tailReaderSaysRunningWhenOnlyActivitySurvivedTheWindow() throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        let turn = "22222222-2222-7222-8222-222222222222"
        // ~9 MB of transcript between the turn's start and the end pushes the
        // boundary past the 8 MB scan limit.
        let filler = String(repeating: "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\"}}\n", count: 9 * 1024 * 1024 / 60)
        writeRollout(boundary("task_started", turn: turn) + "\n" + filler
                     + activity(turn: turn, at: "2026-10-14T23:59:00.000Z") + "\n", to: url)

        var reader = CodexRolloutTailReader()
        let reading = reader.reading(of: url)
        XCTAssertEqual(reading.phase, .running)
        // The claim is a hedge, not an observed boundary.
        XCTAssertEqual(reading.evidence, .activity)
        XCTAssertEqual(reading.confidence, .inferred)
    }

    /// The reader's own index maps a running reading to an active session, so
    /// the light comes on for that file. This is the end-to-end guard.
    func test_readerReportsAnActiveSessionWhenTheStartFellOutOfTheWindow() async throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        let turn = "33333333-3333-7333-8333-333333333333"
        let filler = String(repeating: "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\"}}\n", count: 9 * 1024 * 1024 / 60)
        writeRollout(boundary("task_started", turn: turn) + "\n" + filler
                     + activity(turn: turn, at: "2026-10-14T23:59:00.000Z") + "\n", to: url)
        try writeIndex([ThreadRow(id: id, rollout: url, title: "long build")])

        let sessions = await CodexLocalSessionReader(home: self.home).sessions()
        XCTAssertEqual(sessions.first { $0.id == id }?.state, "active")
        XCTAssertEqual(sessions.first { $0.id == id }?.agentState, .running)
    }

    /// Codex flushes lifecycle records late: an `item_completed` can land after
    /// the `task_complete` that ended its turn. That must not flip a finished
    /// session back to running.
    func test_lateActivityAfterCompletionDoesNotResurrectTheTurn() throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        let turn = "44444444-4444-7444-8444-444444444444"
        writeRollout([boundary("task_started", turn: turn), boundary("task_complete", turn: turn),
                      activity(turn: turn, at: "2026-10-14T16:05:00.000Z"), ""].joined(separator: "\n"), to: url)

        var reader = CodexRolloutTailReader()
        XCTAssertEqual(reader.reading(of: url).phase, .ended)
    }

    /// The same late flush, arriving after the reader has already cached the
    /// ending, must be ignored as well.
    func test_lateActivityAppendedLaterDoesNotResurrectTheTurn() throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        let turn = "55555555-5555-7555-8555-555555555555"
        writeRollout(boundary("task_complete", turn: turn) + "\n", to: url)

        var reader = CodexRolloutTailReader()
        XCTAssertEqual(reader.reading(of: url).phase, .ended)
        try append(activity(turn: turn, at: "2026-10-14T16:05:00.000Z") + "\n", to: url)
        XCTAssertEqual(reader.reading(of: url).phase, .ended)
    }

    /// `thread_settings_applied` is written both after a turn ends and just
    /// before the next one starts, so it proves nothing on its own.
    func test_settingsRecordAloneStaysUnknown() throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        writeRollout("{\"timestamp\":\"2026-10-14T16:00:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"thread_settings_applied\",\"thread_id\":\"\(id)\"}}\n", to: url)
        var reader = CodexRolloutTailReader()
        XCTAssertEqual(reader.reading(of: url).phase, .unknown)
    }

    func test_readerSkipsFilesThatAreNoLongerRecent() async throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/14", id: id)
        writeRollout(boundary("task_started") + "\n", to: url, modified: Date().addingTimeInterval(-4 * 3600))
        try writeIndex([ThreadRow(id: id, rollout: url, title: "stale")])

        let sessions = await CodexLocalSessionReader(home: home).sessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    // MARK: - Merging with CodexBar

    func test_mergePrefersTheLocalReadingForTheSameSession() {
        let local = AgentSessionInfo(id: "a", provider: "codex", sessionName: "本地",
                                     projectName: "ai-underlay", state: "active",
                                     lastActivityAt: Date(), source: "localRollout")
        let polled = [
            AgentSessionInfo(id: "a", provider: "codex", sessionName: "codexbar",
                             projectName: "ai-underlay", state: "idle",
                             lastActivityAt: Date(), source: "desktopApp"),
            AgentSessionInfo(id: "b", provider: "claude", sessionName: "claude",
                             projectName: "status-trio", state: "active",
                             lastActivityAt: Date(), source: "cli"),
        ]
        let merged = CodexSessionMerge.merged(local: [local], polled: polled)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.id == "a" }?.sessionName, "本地")
        XCTAssertEqual(merged.first { $0.id == "b" }?.provider, "claude")
    }

    /// End to end for the reported bug: a session that is running must survive
    /// reconciliation, because the live list now knows it.
    func test_runningSessionSurvivesReconciliationThroughTheLocalReading() async throws {
        let id = UUID().uuidString.lowercased()
        let url = rolloutURL(day: "10/13", id: id)
        writeRollout(boundary("task_started") + "\n", to: url)
        try writeIndex([ThreadRow(id: id, rollout: url, title: "still working")])

        let now = Date()
        let local = await CodexLocalSessionReader(home: home).sessions(at: now)
        let merged = CodexSessionMerge.merged(local: local, polled: [])
        let signals = AgentSignals.reconciled(
            hook: [AgentSession(id: id, providerId: "codex", state: .running,
                                confidence: .exact, observedAt: now)],
            polled: merged.map(\.asAgentSession),
            now: now
        )
        XCTAssertEqual(signals?.activeCount, 1)
    }
}
