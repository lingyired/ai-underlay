import XCTest
import SQLite3
@testable import AIUnderlayKit

/// Wire/projection regression for the ported Codex Desktop IPC adapter.
/// Runtime-domain mapping (signals, waiting/completed semantics) is covered by
/// CodexRuntimeStateTests instead.
final class CodexDesktopAdapterTests: XCTestCase {
    private let thread = "019a0000-0000-7000-8000-000000000001"
    private let client = "019a0000-0000-7000-8000-000000000010"
    private let owner = "019a0000-0000-7000-8000-000000000020"
    private let epoch = Date(timeIntervalSince1970: 1000)

    private func view(_ value: [String: Any]) throws -> JSONFieldView {
        try JSONFieldView.document(JSONSerialization.data(withJSONObject: value))
    }

    private func frames(_ session: inout NativeDesktopSession) throws -> [[String: Any]] {
        try session.takeFrames().map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
    }

    /// Flattened `attention` payloads, reduced to the sanitized id/kind pairs
    /// the parent consumes.
    private func requests(_ frames: [[String: Any]]) -> [[String: String]] {
        frames.flatMap { frame -> [[String: Any]] in
            guard frame["kind"] as? String == "attention" else { return [] }
            return frame["requests"] as? [[String: Any]] ?? []
        }.compactMap { request in
            guard let id = request["id"] as? String, let kind = request["kind"] as? String else { return nil }
            return ["id": id, "kind": kind]
        }
    }

    private func state(turns: Int = 1, items: Int = 2) -> [String: Any] {
        var entities: [String: Any] = [:]
        for i in 0..<turns {
            entities["key\(i)"] = ["turnId": "turn\(i)", "status": i == turns - 1 ? "inProgress" : "completed",
                "turnStartedAtMs": 900000 + i, "items": (0..<items).map { j in
                    ["id": "item\(j)", "type": j == 0 ? "reasoning" : "commandExecution",
                     "status": j == 0 ? "completed" : "inProgress", "text": "PRIVATE", "arguments": "PRIVATE"]
                }]
        }
        return ["title": "PRIVATE", "cwd": "/PRIVATE", "latestModel": "model", "requests": [],
            "threadRuntimeStatus": ["type": "active", "activeFlags": []],
            "latestTokenUsageInfo": ["total": ["outputTokens": 10]],
            "turnHistory": ["kind": "canonical", "history": ["entitiesByKey": entities]]]
    }

    func test_handshakeGatesConnectedAndDeclaresItsOwnClientType() throws {
        final class Sent { var values: [[String: Any]] = [] }
        let sent = Sent()
        var session = try NativeDesktopSession(hosts: ["local"]) { sent.values.append($0) }
        XCTAssertEqual(sent.values.first?["method"] as? String, "initialize")
        XCTAssertEqual((sent.values.first?["params"] as? [String: Any])?["clientType"] as? String, "aiunderlay-events")

        try session.status(loopIterations: 1)
        var parsed = try frames(&session)
        XCTAssertEqual(parsed.filter { $0["kind"] as? String == "status" }.map { $0["connected"] as? Bool }, [false],
                       "an observer cannot claim a live stream before the initialize handshake")

        try session.receive(JSONSerialization.data(withJSONObject: [
            "type": "response", "method": "initialize", "resultType": "success", "result": ["clientId": client]]), at: epoch)
        parsed = try frames(&session)
        XCTAssertEqual(parsed.filter { $0["kind"] as? String == "status" }.map { $0["connected"] as? Bool }, [true])
    }

    func test_discoverySeedsQueuedBeforeInitializeAreFollowedAfterHandshake() throws {
        final class Sent { var values: [[String: Any]] = [] }
        let sent = Sent()
        var session = try NativeDesktopSession(hosts: ["local"]) { sent.values.append($0) }
        try session.discover([.init(host: "local", thread: thread)])
        XCTAssertTrue(sent.values.allSatisfy { ($0["params"] as? [String: Any])?["following"] as? Bool != true },
                      "seeds wait for the handshake instead of guessing a stream")

        try session.receive(JSONSerialization.data(withJSONObject: [
            "type": "response", "method": "initialize", "resultType": "success", "result": ["clientId": client]]), at: epoch)
        let followed = sent.values.contains { value in
            let params = value["params"] as? [String: Any]
            return value["method"] as? String == "thread-stream-following-changed"
                && params?["following"] as? Bool == true
                && params?["hostId"] as? String == "local"
                && params?["conversationId"] as? String == thread
        }
        XCTAssertTrue(followed, "startup seeds must be drained right after the handshake")
    }

    func test_revisionGapAndMalformedBatchRollBackAtomically() throws {
        var projection = DesktopWireProjection(threadID: thread)
        _ = try projection.consume(try view(["type": "snapshot", "revision": 4, "conversationState": state()]), owner: owner, at: epoch)
        XCTAssertEqual(projection.revision, 4)
        XCTAssertEqual(projection.currentTurnID, "turn0")
        XCTAssertTrue(projection.isActive)

        XCTAssertThrowsError(try projection.consume(try view(["type": "patches", "baseRevision": 1, "revision": 2, "patches": []]),
                                                    owner: owner, at: epoch))
        XCTAssertEqual(projection.revision, 4, "a gap must not advance the applied revision")

        XCTAssertThrowsError(try projection.consume(try view(["type": "patches", "baseRevision": 4, "revision": 5, "patches": [
            ["op": "replace", "path": ["turnHistory", "history", "entitiesByKey", "key0", "status"], "value": "completed"],
            ["op": "replace", "path": ["turnHistory", "history", "entitiesByKey", "key0", "items", 9999, "status"], "value": "completed"]]]),
            owner: owner, at: epoch))
        XCTAssertEqual(projection.revision, 4, "one rejected patch discards the whole batch")
        XCTAssertTrue(projection.isActive)
        XCTAssertEqual(projection.retainedItemCount, 2)

        XCTAssertThrowsError(try projection.consume(try view(["type": "patches", "baseRevision": 4, "revision": 5, "patches": []]),
                                                    owner: "019a0000-0000-7000-8000-000000000021", at: epoch))
        let text = try projection.consume(try view(["type": "patches", "baseRevision": 4, "revision": 5, "patches": [
            ["op": "replace", "path": ["turnHistory", "history", "entitiesByKey", "key0", "items", 0, "text"], "value": "PRIVATE"]]]),
            owner: owner, at: epoch)
        XCTAssertEqual(projection.revision, 5)
        XCTAssertTrue(text.contains { $0["method"] as? String == "item/reasoning/textDelta" })
        XCTAssertFalse(String(describing: projection).contains("PRIVATE"))
    }

    func test_requestsKeepKindAndHashOnlyAndAsyncMarkersClearOnReply() throws {
        var projection = DesktopWireProjection(threadID: thread)
        var raw = state()
        raw["requests"] = [
            ["id": "approval", "method": "item/commandExecution/requestApproval", "params": ["command": "PRIVATE"]],
            ["id": "question", "request": ["method": "item/tool/requestUserInput",
                "params": ["isBlocking": false, "questions": [["question": "PRIVATE", "options": ["PRIVATE"]]]]]]]
        _ = try projection.consume(try view(["type": "snapshot", "revision": 0, "conversationState": raw]), owner: owner, at: epoch)
        XCTAssertEqual(projection.requests.map(\.kind), [.approval, .input])
        XCTAssertEqual(projection.requests.map(\.id).count, Set(projection.requests.map(\.id)).count)
        XCTAssertFalse(projection.requests.contains { $0.id.contains("approval") || $0.id.contains("question") })
        XCTAssertFalse(String(describing: projection.requests).contains("PRIVATE"))

        // A Desktop async question is agent-message metadata: the reply
        // boundary is the later user message, and no answer text is read.
        var marker = DesktopWireProjection(threadID: thread)
        let turn: [String: Any] = ["turnId": "turn", "status": "inProgress", "turnStartedAtMs": 900000, "items": [
            ["id": "user", "type": "userMessage", "content": "PRIVATE"],
            ["id": "ask", "type": "agentMessage", "text": "PRIVATE", "questions": [["title": "PRIVATE"]]]]]
        _ = try marker.consume(try view(["type": "snapshot", "revision": 0, "conversationState": ["turns": [turn]]]), owner: owner, at: epoch)
        XCTAssertEqual(marker.requests.map(\.kind), [.input])
        XCTAssertTrue(marker.isActive)
        let items: [Any] = ["turns", 0, "items"]
        _ = try marker.consume(try view(["type": "patches", "baseRevision": 0, "revision": 1, "patches": [
            ["op": "add", "path": items + [2], "value": ["id": "reply", "type": "userMessage", "content": "PRIVATE"]]]]), owner: owner, at: epoch)
        XCTAssertTrue(marker.requests.isEmpty)
        _ = try marker.consume(try view(["type": "patches", "baseRevision": 1, "revision": 2, "patches": [
            ["op": "replace", "path": ["turns", 0, "status"], "value": "completed"]]]), owner: owner, at: epoch)
        XCTAssertTrue(marker.requests.isEmpty)
        XCTAssertEqual(marker.retainedItemCount, 0)
        XCTAssertFalse(String(describing: marker).contains("PRIVATE"))
    }

    func test_ownerDisconnectInvalidatesTheStreamAndPendingRequestSurvivesReconnect() throws {
        final class Sent { var values: [[String: Any]] = [] }
        let sent = Sent()
        var session = try NativeDesktopSession(hosts: ["local"]) { sent.values.append($0) }
        func send(_ value: [String: Any]) throws { try session.receive(JSONSerialization.data(withJSONObject: value), at: epoch) }
        func change(_ owner: String, _ value: [String: Any]) throws {
            try send(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": owner,
                "params": ["hostId": "local", "conversationId": thread, "change": value]])
        }
        try send(["type": "response", "method": "initialize", "resultType": "success", "result": ["clientId": client]])
        try send(["type": "broadcast", "method": "thread-stream-following-status-requested", "version": 1,
            "sourceClientId": owner, "params": ["hostId": "local", "conversationId": thread]])
        var raw = state()
        raw["requests"] = [["id": "pending", "method": "item/commandExecution/requestApproval", "params": ["command": "PRIVATE"]]]
        try change(owner, ["type": "snapshot", "revision": 0, "conversationState": raw])
        let initial = requests(try frames(&session))
        XCTAssertEqual(initial.map { $0["kind"] }, ["approval"])

        try send(["type": "broadcast", "method": "client-status-changed", "version": 0, "sourceClientId": owner,
            "params": ["clientId": owner, "status": "disconnected"]])
        let invalidated = try frames(&session)
        XCTAssertTrue(invalidated.contains { $0["kind"] as? String == "streamInvalidated" && $0["threadId"] as? String == thread })
        XCTAssertTrue(sent.values.contains { value in
            let params = value["params"] as? [String: Any]
            return params?["following"] as? Bool == true && params?["conversationId"] as? String == thread
        }, "losing an owner must renew interest instead of silently staying subscribed")

        let renewed = "019a0000-0000-7000-8000-000000000021"
        try send(["type": "broadcast", "method": "thread-stream-following-status-requested", "version": 1,
            "sourceClientId": renewed, "params": ["hostId": "local", "conversationId": thread]])
        try change(renewed, ["type": "snapshot", "revision": 0, "conversationState": raw])
        let resumed = requests(try frames(&session))
        XCTAssertEqual(resumed, initial, "the unresolved request keeps its sanitized identity across an owner replacement")
        XCTAssertFalse(String(describing: resumed).contains("PRIVATE"))
    }

    func test_targetedPatchesForOtherClientsAreIgnored() throws {
        final class Sent { var values: [[String: Any]] = [] }
        let sent = Sent()
        var session = try NativeDesktopSession(hosts: ["local"]) { sent.values.append($0) }
        func send(_ value: [String: Any]) throws { try session.receive(JSONSerialization.data(withJSONObject: value), at: epoch) }
        func change(_ target: String) throws {
            try send(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": owner,
                "targetClientIds": [target],
                "params": ["hostId": "local", "conversationId": thread, "change": ["type": "snapshot", "revision": 0, "conversationState": state()]]])
        }
        try send(["type": "response", "method": "initialize", "resultType": "success", "result": ["clientId": client]])
        try send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
            "params": ["hostId": "local", "conversationId": thread, "following": true]])

        try change("019a0000-0000-7000-8000-000000000099")
        _ = try frames(&session)
        XCTAssertEqual(session.notifications, 0, "another client's patch stream must never be consumed")
        try change(client)
        let parsed = try frames(&session)
        XCTAssertEqual(session.notifications, 1)
        XCTAssertTrue(parsed.contains { $0["kind"] as? String == "attention" })
    }

    func test_terminalTurnRetiresDormantButKeepsTheNextTurnVisible() throws {
        final class Sent { var values: [[String: Any]] = [] }
        let sent = Sent()
        var session = try NativeDesktopSession(hosts: ["local"]) { sent.values.append($0) }
        func send(_ value: [String: Any]) throws { try session.receive(JSONSerialization.data(withJSONObject: value), at: epoch) }
        func change(_ value: [String: Any]) throws {
            try send(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": owner,
                "targetClientIds": [client],
                "params": ["hostId": "local", "conversationId": thread, "change": value]])
        }
        try send(["type": "response", "method": "initialize", "resultType": "success", "result": ["clientId": client]])
        try send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
            "params": ["hostId": "local", "conversationId": thread, "following": true]])
        try change(["type": "snapshot", "revision": 0, "conversationState": ["turns": [
            ["turnId": "old", "status": "inProgress", "turnStartedAtMs": 800000, "items": [["id": "answer", "type": "agentMessage"]]]]]])
        try session.publishEvents(); _ = try frames(&session)

        try change(["type": "patches", "baseRevision": 0, "revision": 1, "patches": [
            ["op": "replace", "path": ["turns", 0, "status"], "value": "completed"]]])
        // Real owners send token/status bookkeeping after the terminal patch,
        // often before the batch interval has delivered that ending.
        try change(["type": "patches", "baseRevision": 1, "revision": 2, "patches": [
            ["op": "replace", "path": ["threadRuntimeStatus"], "value": ["type": "idle", "activeFlags": []]]]])
        try session.publishEvents()
        let ended = try frames(&session)
        XCTAssertFalse(ended.contains { $0["kind"] as? String == "streamInvalidated" })
        XCTAssertEqual(ended.compactMap { $0["events"] as? [[String: Any]] }.flatMap { $0 }
            .filter { $0["method"] as? String == "turn/completed" }.count, 1,
            "a trailing patch must not discard the queued completion")
        XCTAssertEqual(session.dormantSubscriptionCount, 1)
        XCTAssertEqual(session.retainedItemCount, 0)
        XCTAssertFalse(sent.values.contains { ($0["params"] as? [String: Any])?["following"] as? Bool == false },
                       "a dormant interest keeps following so the next turn is not missed")

        try change(["type": "patches", "baseRevision": 2, "revision": 3, "patches": [
            ["op": "add", "path": ["turns", 1], "value": ["turnId": "next", "status": "inProgress", "turnStartedAtMs": 900000,
                "items": [["id": "reasoning", "type": "reasoning"]]]]]])
        try session.publishEvents()
        let events = try frames(&session).compactMap { $0["events"] as? [[String: Any]] }.flatMap { $0 }
        XCTAssertTrue(events.contains { $0["method"] as? String == "turn/started" && $0["turnId"] as? String == "next" })
        XCTAssertEqual(session.dormantSubscriptionCount, 0)
    }

    func test_routeHintsBoundBootstrapWithoutLosingLaterTasks() throws {
        let home = URL(fileURLWithPath: "/private/tmp/aiunderlay-route-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let host = "remote-ssh-discovered:synthetic", file = home.appendingPathComponent(".codex-global-state.json")
        var routes = Dictionary(uniqueKeysWithValues: (1...100).map { (String(format: "019a0000-0000-7000-8000-%012d", $0), host) })
        func save() throws {
            try JSONSerialization.data(withJSONObject: ["thread-project-membership-host-ids": routes, "unrelated": "PRIVATE"])
                .write(to: file, options: .atomic)
        }
        try save()
        var reader = DesktopRouteHints()
        XCTAssertEqual(reader.changed(home: home, hosts: [host]).count, 8, "a metadata bootstrap stays bounded")
        XCTAssertTrue(reader.changed(home: home, hosts: [host]).isEmpty)
        routes[thread] = host
        let new = "019b0000-0000-7000-8000-000000000001"
        routes[new] = host; routes[UUID().uuidString] = "disabled-host"
        try save()
        XCTAssertEqual(reader.changed(home: home, hosts: [host]), [.init(host: host, thread: new)])
        XCTAssertFalse(String(describing: reader).contains("PRIVATE"))
    }

    func test_indexedSeedsStayLocalRecentUnarchivedAndNoninternal() throws {
        let home = URL(fileURLWithPath: "/private/tmp/aiunderlay-seed-" + UUID().uuidString)
        let sessions = home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let ordinary = (0..<40).map { String(format: "019a0000-0000-7000-8001-%012d", $0) }
        var rows: [(id: String, recency: Int, archived: Int, source: String, threadSource: String)] = ordinary.enumerated()
            .map { ($0.element, 5000 - $0.offset, 0, "null", "") }
        // Real metadata sits above the ordinary rows: if either filter regresses
        // it would displace a live thread at the front of the bounded seed.
        rows.append((String(format: "019a0000-0000-7000-8002-%012d", 0), 9000, 1, "null", ""))
        rows.append((String(format: "019a0000-0000-7000-8003-%012d", 0), 8999, 0, #"{"subagent":{"parent_thread_id":"PRIVATE"}}"#, ""))
        rows.append((String(format: "019a0000-0000-7000-8004-%012d", 0), 8998, 0, "null", "auto_review"))
        rows.append(("not-a-uuid", 8997, 0, "null", ""))

        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(home.appendingPathComponent("state_5.sqlite").path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, """
        CREATE TABLE threads (id TEXT, rollout_path TEXT, name TEXT, title TEXT, source TEXT, cwd TEXT,
            recency_at_ms INTEGER, thread_source TEXT, archived INTEGER, model TEXT)
        """, nil, nil, nil), SQLITE_OK)
        for row in rows {
            let rollout = sessions.appendingPathComponent(row.id + ".jsonl")
            try Data().write(to: rollout)
            let insert = "INSERT INTO threads (id, rollout_path, name, title, source, cwd, recency_at_ms, thread_source, archived, model) VALUES "
                + "('\(row.id)', '\(rollout.path)', 'PRIVATE name', 'PRIVATE title', '\(row.source)', '/PRIVATE', \(row.recency), '\(row.threadSource)', \(row.archived), '')"
            XCTAssertEqual(sqlite3_exec(handle, insert, nil, nil, nil), SQLITE_OK)
        }

        let seeds = NativeDesktopCollector.indexedSeeds(home: home, hosts: ["local"])
        XCTAssertEqual(seeds.count, 32)
        XCTAssertEqual(Set(seeds.map(\.thread)), Set(ordinary.prefix(32)))
        XCTAssertTrue(seeds.allSatisfy { $0.host == "local" })
        XCTAssertTrue(NativeDesktopCollector.indexedSeeds(home: home, hosts: ["remote-ssh-discovered:synthetic"]).isEmpty)
        XCTAssertFalse(String(describing: seeds).contains("PRIVATE"))
    }

    func test_snapshotPendingRequestEstablishesLifecycleBeforeAttention() throws {
        final class Sent { var values: [[String: Any]] = [] }
        let sent = Sent()
        var session = try NativeDesktopSession(hosts: ["local"]) { sent.values.append($0) }
        func send(_ value: [String: Any]) throws { try session.receive(JSONSerialization.data(withJSONObject: value), at: epoch) }
        try send(["type": "response", "method": "initialize", "resultType": "success", "result": ["clientId": client]])
        try send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
            "params": ["hostId": "local", "conversationId": thread, "following": true]])
        var raw = state()
        raw["requests"] = [["id": "pending", "method": "item/tool/requestUserInput",
            "params": ["isBlocking": false, "questions": [["question": "PRIVATE"]]]]]
        try send(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": owner,
            "params": ["hostId": "local", "conversationId": thread,
                "change": ["type": "snapshot", "revision": 0, "conversationState": raw]]])

        let bytes = session.takeFrames()
        let parsed = try bytes.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
        let attached = try XCTUnwrap(parsed.firstIndex { frame in
            frame["kind"] as? String == "runtimeBatch" && (frame["events"] as? [[String: Any]] ?? [])
                .contains { $0["method"] as? String == "turn/attached" }
        }, "the snapshot must establish the turn before announcing it")
        let attention = try XCTUnwrap(parsed.firstIndex { $0["kind"] as? String == "attention" })
        XCTAssertLessThan(attached, attention, "a pending request cannot arrive before the turn it belongs to")
        XCTAssertEqual(requests(parsed).map { $0["kind"] }, ["input"])

        // Replaying the frame order is the integration contract: the parent
        // clears stale requests when a turn attaches, so a reversed order would
        // discard this live question.
        var state = CodexRuntimeState()
        for frame in bytes { state.consume(frame, at: epoch) }
        let signals = AgentSignals.counting(state.snapshot(at: epoch).sessions, now: epoch)
        XCTAssertEqual(signals.waitingInputCount, 1)
        XCTAssertEqual(signals.activeCount, 1, "an unanswered question does not pause the turn")
        XCTAssertEqual(state.snapshot(at: epoch).sessions.first?.pendingQuestion, true)
        XCTAssertFalse(String(decoding: bytes.reduce(into: Data()) { $0.append($1) }, as: UTF8.self).contains("PRIVATE"))
    }

    func test_queuedBatchIsPublishedBeforeATrailingAttentionChange() throws {
        final class Sent { var values: [[String: Any]] = [] }
        let sent = Sent()
        var session = try NativeDesktopSession(hosts: ["local"]) { sent.values.append($0) }
        func send(_ value: [String: Any]) throws { try session.receive(JSONSerialization.data(withJSONObject: value), at: epoch) }
        func patch(_ revision: Int, _ path: [Any], _ value: Any) throws {
            try send(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": owner,
                "params": ["hostId": "local", "conversationId": thread,
                    "change": ["type": "patches", "baseRevision": revision - 1, "revision": revision,
                        "patches": [["op": "replace", "path": path, "value": value]]]]])
        }
        try send(["type": "response", "method": "initialize", "resultType": "success", "result": ["clientId": client]])
        try send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
            "params": ["hostId": "local", "conversationId": thread, "following": true]])
        try send(["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": owner,
            "params": ["hostId": "local", "conversationId": thread,
                "change": ["type": "snapshot", "revision": 0, "conversationState": ["turns": [
                    ["turnId": "turn", "status": "inProgress", "turnStartedAtMs": 900000,
                     "items": [["id": "answer", "type": "agentMessage"]]]]]]]])
        _ = session.takeFrames()

        let text: [Any] = ["turns", 0, "items", 0, "content"]
        try patch(1, text, "PRIVATE")
        _ = session.takeFrames()
        try patch(2, text, "PRIVATE again")
        XCTAssertTrue(session.hasEvents, "a later text delta stays in the ordinary batch")
        try patch(3, ["requests"], [["id": "pending", "method": "item/commandExecution/requestApproval", "params": ["command": "PRIVATE"]]])

        let parsed = try frames(&session)
        XCTAssertFalse(session.hasEvents, "a changed attention publishes the pending batch instead of overtaking it")
        let batch = try XCTUnwrap(parsed.firstIndex { $0["kind"] as? String == "runtimeBatch" })
        let attention = try XCTUnwrap(parsed.firstIndex { $0["kind"] as? String == "attention" })
        XCTAssertLessThan(batch, attention)
        XCTAssertTrue((parsed[batch]["events"] as? [[String: Any]] ?? [])
            .contains { $0["method"] as? String == "item/agentMessage/delta" })
        XCTAssertEqual(requests(parsed).map { $0["kind"] }, ["approval"])
        XCTAssertFalse(String(describing: parsed).contains("PRIVATE"))
    }
}
