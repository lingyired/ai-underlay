import Foundation

/// Live Codex sessions read from the local rollout files.
///
/// `codexbar sessions` shells out and only reports what its own scan window
/// covers, which misses sessions that were started days ago and are still in
/// use — the exact case that left a running session unrecognized. This reader
/// follows codex-pacer's approach instead: list the app's own thread index,
/// then ask each rollout file whether its newest turn has ended.
public actor CodexLocalSessionReader {
    /// A turn that has not ended keeps the session active for this long after
    /// its last write: a build, a notarization or a render can run for many
    /// minutes without writing anything the reader could see.
    public static let activeWindow: TimeInterval = 900
    /// Finished sessions stay listed for a while, so the popup can still say
    /// "N sessions idle" after a turn ends.
    public static let idleWindow: TimeInterval = 2 * 3600
    public static let maximumSessions = 16

    private let home: URL
    private var tails = CodexRolloutTailReader()

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true)) {
        self.home = home
    }

    public func sessions(at now: Date = Date()) -> [AgentSessionInfo] {
        var sessions: [AgentSessionInfo] = []
        // Dedupe by thread id: the same file can be reached through different
        // URL spellings (symlinked temporary directories, for one).
        var seen: Set<String> = []

        for thread in CodexSessionIndex.load(home: home) {
            seen.insert(thread.id.lowercased())
            guard !thread.isInternal, !thread.isArchived else { continue }
            if let session = session(id: thread.id, url: thread.rolloutURL,
                                     title: thread.title, cwd: thread.cwd, now: now) {
                sessions.append(session)
            }
        }
        // The directory scan covers threads that are not in the index yet — a
        // session created seconds ago, or one started by a bare CLI run.
        for url in recentRolloutFiles(around: now) {
            guard let id = Self.threadId(from: url), !seen.contains(id) else { continue }
            seen.insert(id)
            if let session = session(id: id, url: url, title: nil, cwd: nil, now: now) {
                sessions.append(session)
            }
        }

        sessions.sort { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
        let running = sessions.filter { $0.agentState == .running }
        let idle = sessions.filter { $0.agentState != .running }
        return Array((running + idle).prefix(Self.maximumSessions))
    }

    private func session(
        id: String, url: URL, title: String?, cwd: String?, now: Date
    ) -> AgentSessionInfo? {
        guard let modified = Self.modificationDate(url) else {
            tails.forget(url)
            return nil
        }
        let age = now.timeIntervalSince(modified)
        // A session whose turn has ended is only interesting while it is
        // recent; a transcript nobody touched for hours is not a session.
        guard age <= Self.idleWindow else {
            tails.forget(url)
            return nil
        }
        let phase = tails.phase(of: url)
        let active = phase == .running && age <= Self.activeWindow
        return AgentSessionInfo(
            id: id,
            provider: "codex",
            sessionName: title ?? "",
            projectName: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            state: active ? "active" : "idle",
            lastActivityAt: modified,
            source: "localRollout"
        )
    }

    /// Rollout directories are named for the day a thread was *created*, so
    /// yesterday's folder still receives appends from a long-lived session;
    /// the index normally covers those, and this scan catches the rest.
    private func recentRolloutFiles(around now: Date) -> [URL] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var urls: [URL] = []
        for dayOffset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let directory = home.appendingPathComponent("sessions/\(formatter.string(from: day))")
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            urls.append(contentsOf: entries.filter { $0.pathExtension == "jsonl" })
        }
        return urls
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
    }

    /// Rollout file names end in the thread's UUID.
    private static func threadId(from url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.count > 36 else { return nil }
        let suffix = String(stem.suffix(36)).lowercased()
        return UUID(uuidString: suffix) != nil ? suffix : nil
    }
}

/// Combines the local rollout reading with `codexbar`'s session list.
///
/// The local entry wins for a session both sides know: it reports the turn
/// boundary the transcript itself wrote, while `codexbar` can only infer
/// recency. Entries only `codexbar` sees (other providers, remote hosts) pass
/// through untouched.
public enum CodexSessionMerge {
    public static func merged(local: [AgentSessionInfo], polled: [AgentSessionInfo]) -> [AgentSessionInfo] {
        let localIds = Set(local.map(\.id))
        return local + polled.filter { !localIds.contains($0.id) }
    }
}
