import Foundation

/// One live agent session as reported by `codexbar sessions`.
public struct AgentSessionInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let provider: String
    public let sessionName: String
    public let projectName: String?
    public let state: String        // "active" | "idle" | other
    public let lastActivityAt: Date?
    public let source: String?

    public init(
        id: String, provider: String, sessionName: String, projectName: String?,
        state: String, lastActivityAt: Date?, source: String?
    ) {
        self.id = id
        self.provider = provider
        self.sessionName = sessionName
        self.projectName = projectName
        self.state = state
        self.lastActivityAt = lastActivityAt
        self.source = source
    }

    /// Maps CodexBar's coarse session state to our agent state. Active → running;
    /// idle → idle. Anything else is unknown — we never invent a finer state.
    public var agentState: AgentState {
        switch state.lowercased() {
        case "active", "running", "busy": return .running
        case "idle", "free": return .idle
        default: return .unknown
        }
    }

    /// Our domain session, confidence `inferred` because it is recency-based.
    public var asAgentSession: AgentSession {
        AgentSession(
            id: id,
            providerId: provider,
            state: agentState,
            confidence: .inferred,
            observedAt: lastActivityAt ?? Date()
        )
    }
}

/// Parses `codexbar sessions --json`.
public enum CodexBarSessionCatalog {
    /// CodexBar keeps its own helper processes under this directory. They are
    /// reported by `sessions` exactly like a user session, so the path is how we
    /// tell them apart.
    static let codexBarSupportFragment = "/Library/Application Support/CodexBar/"

    public static func parse(_ data: Data) throws -> [AgentSessionInfo] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return array.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            // CodexBar's own usage probe is not agent activity. It spawns a
            // headless `claude` to read quota, and `sessions` reports that
            // process as a live Claude session — which would otherwise light up
            // "running" for a provider the user never started.
            guard !isSelfProbe(entry) else { return nil }
            let activity = (entry["lastActivityAt"] as? String).flatMap { formatter.date(from: $0) }
            return AgentSessionInfo(
                id: id,
                provider: (entry["provider"] as? String) ?? "unknown",
                sessionName: (entry["sessionName"] as? String) ?? "",
                projectName: entry["projectName"] as? String,
                state: (entry["state"] as? String) ?? "unknown",
                lastActivityAt: activity,
                source: entry["source"] as? String
            )
        }
    }

    /// True only for CodexBar's internal probe, never for a user's own session:
    /// either the probe's fixed project name, or a working directory inside
    /// CodexBar's application-support folder.
    static func isSelfProbe(_ entry: [String: Any]) -> Bool {
        if (entry["projectName"] as? String) == "ClaudeProbe" { return true }
        if let cwd = entry["cwd"] as? String, cwd.contains(codexBarSupportFragment) { return true }
        return false
    }
}

/// A `QuotaEngine` capability: list live agent sessions. This works out of the
/// box (no hook installation) and covers Codex and Claude Code.
public protocol AgentSessionEngine: Sendable {
    func listAgentSessions() async throws -> [AgentSessionInfo]
}

extension CodexBarEngine: AgentSessionEngine {
    public func listAgentSessions() async throws -> [AgentSessionInfo] {
        let env = ProxyEnvironment.mergedEnvironment(override: proxyOverride)
        let data = try await client.run(executable: executableURL,
                                        args: ["sessions", "--json"],
                                        timeout: 15, environment: env)
        return try CodexBarSessionCatalog.parse(data)
    }
}
