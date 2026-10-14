import Foundation
import SQLite3

/// One Codex thread as recorded in the app's local state database.
public struct CodexIndexedThread: Equatable, Sendable {
    public let id: String
    public let rolloutURL: URL
    public let title: String?
    public let cwd: String?
    public let recencyAt: Date?
    public let threadSource: String?
    public let isArchived: Bool
    /// Review tooling (`codex-auto-review`) and spawned subagents run without a
    /// thread the user opened, so they never count as sessions of their own.
    public let isInternal: Bool
}

/// Read-only lookup of Codex's thread index (`~/.codex/state_<N>.sqlite`).
///
/// Rollout files live in a directory named for the day a thread was *created*,
/// so a session started days ago and still in use keeps writing into an old
/// date directory. Scanning recent directories alone therefore misses exactly
/// the long-lived sessions a user is most likely to have running; the app's own
/// index is the only complete list, which is why codex-pacer reads it too.
public enum CodexSessionIndex {
    public static func load(home: URL, limit: Int = 256) -> [CodexIndexedThread] {
        let manager = FileManager.default
        let databases = ((try? manager.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.range(of: #"^state_[0-9]+\.sqlite$"#, options: .regularExpression) != nil }
            .sorted { version($0) > version($1) }
        for database in databases {
            if let entries = read(database, home: home, limit: limit) { return entries }
        }
        return []
    }

    private static func read(_ database: URL, home: URL, limit: Int) -> [CodexIndexedThread]? {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(database.path, &handle, flags, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        defer { sqlite3_close(handle) }
        // The app writes this database while it runs; never wait long for it.
        sqlite3_busy_timeout(handle, 50)

        let columns = tableColumns(handle, table: "threads")
        guard columns.contains("rollout_path") else { return nil }

        let order = ["recency_at_ms", "updated_at_ms", "updated_at", "created_at"].first { columns.contains($0) } ?? "rowid"
        let title = columns.contains("name") && columns.contains("title")
            ? "COALESCE(NULLIF(TRIM(name), ''), title)"
            : columns.contains("name") ? "name" : columns.contains("title") ? "title" : "NULL"
        let source = columns.contains("source") ? "source" : "NULL"
        let cwd = columns.contains("cwd") ? "cwd" : "NULL"
        let recency = columns.contains("recency_at_ms") ? "recency_at_ms" : "NULL"
        let threadSource = columns.contains("thread_source") ? "thread_source" : "NULL"

        let query = """
        SELECT id, rollout_path, \(title), \(source), \(cwd), \(recency), \(threadSource),
               \(columns.contains("archived") ? "COALESCE(archived, 0)" : "0"),
               \(columns.contains("model") ? "COALESCE(model, '')" : "''")
        FROM threads WHERE rollout_path IS NOT NULL
        ORDER BY \(order) DESC LIMIT \(max(1, min(1024, limit)))
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        let sessionsRoot = home.appendingPathComponent("sessions").standardizedFileURL.path + "/"
        var result: [CodexIndexedThread] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = sqlite3_column_text(statement, 0),
                  let rawPath = sqlite3_column_text(statement, 1) else { continue }
            let id = String(cString: rawID)
            let url = URL(fileURLWithPath: String(cString: rawPath)).standardizedFileURL
            guard url.path.hasPrefix(sessionsRoot),
                  url.pathExtension == "jsonl",
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            let sourceJSON = sqlite3_column_text(statement, 3).flatMap { Data(String(cString: $0).utf8) }
            let threadSourceValue = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            let model = sqlite3_column_text(statement, 8).map { String(cString: $0) }
            let milliseconds = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil : sqlite3_column_int64(statement, 5)
            result.append(CodexIndexedThread(
                id: id,
                rolloutURL: url,
                title: sqlite3_column_text(statement, 2).map { String(cString: $0) },
                cwd: sqlite3_column_text(statement, 4).map { String(cString: $0) },
                recencyAt: milliseconds.flatMap { $0 > 0 ? Date(timeIntervalSince1970: Double($0) / 1000) : nil },
                threadSource: threadSourceValue,
                isArchived: sqlite3_column_int(statement, 7) != 0,
                isInternal: isInternal(source: sourceJSON, threadSource: threadSourceValue, model: model)
            ))
        }
        return result
    }

    private static func tableColumns(_ handle: OpaquePointer?, table: String) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) { columns.insert(String(cString: name)) }
        }
        return columns
    }

    /// Subagents carry a `source` payload naming their parent; the review
    /// runners show up in `thread_source` or the model name. Both are internal.
    private static func isInternal(source: Data?, threadSource: String?, model: String?) -> Bool {
        if let threadSource, ["subagent", "guardian_review", "auto_review", "autoreview"].contains(threadSource) {
            return true
        }
        if let model, model.lowercased().hasPrefix("codex-auto-review") { return true }
        guard let source,
              let object = try? JSONSerialization.jsonObject(with: source) as? [String: Any] else { return false }
        return object["subagent"] != nil
    }

    private static func version(_ url: URL) -> Int {
        Int(url.deletingPathExtension().lastPathComponent.dropFirst("state_".count)) ?? 0
    }
}
