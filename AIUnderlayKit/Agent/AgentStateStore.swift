import Foundation

/// Persists the reducer's session state to disk so an app restart does not
/// forget a session that is waiting on the user.
///
/// Waiting states never re-fire an event, so without this a restart during a
/// pending approval or question would silently drop the light until the user
/// happens to act. The file holds only the same metadata the reducer already
/// keeps — provider, session id, state, confidence, timestamp — never any
/// conversation content.
public struct AgentStateStore {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            let dir = base.appendingPathComponent(AIUnderlayKit.bundleIdentifier, isDirectory: true)
            self.fileURL = dir.appendingPathComponent("agent-state.json")
        }
    }

    /// Writes the snapshot atomically. Best-effort: a failure to persist must
    /// never disrupt live rendering, so errors are swallowed.
    public func save(_ snapshot: AgentSessionReducer.Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Loads the last snapshot, or nil when there is none / it is unreadable.
    public func load() -> AgentSessionReducer.Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AgentSessionReducer.Snapshot.self, from: data)
    }

    /// Removes the persisted state (used by tests and uninstall).
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}