import Foundation

/// Raw hook input, already parsed to a dictionary. The adapter decides which
/// provider it came from and what it means. Not `Sendable`: `[String: Any]`
/// cannot be, and these values never cross a concurrency boundary — they are
/// produced and consumed on the socket's own queue.
public struct RawAgentEvent {
    public let providerId: String
    public let payload: [String: Any]

    public init(providerId: String, payload: [String: Any]) {
        self.providerId = providerId
        self.payload = payload
    }
}

/// Turns a provider-specific hook payload into a normalized `AgentEvent`.
/// Adapters must never read or forward prompt text, tool arguments, or output —
/// they extract only the session id, event name, and timestamp.
public protocol AgentEventAdapter: Sendable {
    var providerId: String { get }
    func adapt(_ raw: RawAgentEvent) -> AgentEvent?
}

/// Claude Code hook adapter. Recognizes the documented hook event names.
public struct ClaudeCodeAdapter: AgentEventAdapter {
    public let providerId = "claude"

    public init() {}

    public func adapt(_ raw: RawAgentEvent) -> AgentEvent? {
        guard let name = raw.payload["hook_event_name"] as? String,
              let sessionId = raw.payload["session_id"] as? String
        else { return nil }

        let kind = Self.kind(forHookName: name)
        return AgentEvent(providerId: providerId, sessionId: sessionId, kind: kind, at: Date())
    }

    public static func kind(forHookName name: String) -> AgentEventKind {
        switch name {
        case "SessionStart": return .sessionStart
        case "SessionEnd": return .sessionEnd
        case "UserPromptSubmit": return .userPromptSubmitted
        case "PreToolUse": return .toolUseStarted
        case "PostToolUse", "PostToolUseFailure": return .toolUseFinished
        case "PermissionRequest": return .permissionRequested
        case "Notification": return .notification
        case "Stop", "StopFailure": return .stopped
        case "SubagentStart": return .subagentStarted
        case "SubagentStop": return .subagentFinished
        default: return .unknown
        }
    }
}

/// Codex CLI adapter. Codex does not reliably emit a "waiting for free-text
/// answer" event, so anything we cannot classify becomes `.unknown` rather than
/// a fabricated waiting state.
public struct CodexAdapter: AgentEventAdapter {
    public let providerId = "codex"

    public init() {}

    public func adapt(_ raw: RawAgentEvent) -> AgentEvent? {
        guard let sessionId = (raw.payload["session_id"] as? String) ?? (raw.payload["sessionId"] as? String) else {
            return nil
        }
        let name = (raw.payload["hook_event_name"] as? String) ?? (raw.payload["event"] as? String) ?? ""
        return AgentEvent(providerId: providerId, sessionId: sessionId,
                          kind: Self.kind(forEventName: name), at: Date())
    }

    public static func kind(forEventName name: String) -> AgentEventKind {
        switch name.lowercased() {
        case "sessionstart", "session_start": return .sessionStart
        case "sessionend", "session_end": return .sessionEnd
        case "prettooluse", "pretooluse", "tooluse", "tool_start": return .toolUseStarted
        case "posttooluse", "tool_end": return .toolUseFinished
        case "permissionrequest", "approval", "approval_request": return .permissionRequested
        case "stop", "complete", "completed": return .stopped
        // Codex has no reliable "waiting for input"; do not invent one.
        default: return .unknown
        }
    }
}

/// Selects the adapter for a provider id.
public enum AgentAdapters {
    public static func adapter(for providerId: String) -> AgentEventAdapter? {
        switch providerId.lowercased() {
        case "claude", "claude-code": return ClaudeCodeAdapter()
        case "codex": return CodexAdapter()
        default: return nil
        }
    }
}
