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

        let kind = Self.kind(forHookName: name, notificationType: raw.payload["notification_type"] as? String)
        return AgentEvent(providerId: providerId, sessionId: sessionId, kind: kind, at: Date())
    }

    /// Maps a hook event name to a normalized kind. `Notification` carries a
    /// `notification_type`; only the types that genuinely mean "Claude needs
    /// you" become `.notification`. The rest (`auth_success`, `agent_completed`,
    /// quota resumes, …) are `.unknown` so they can never light the amber
    /// "waiting on you" state.
    public static func kind(forHookName name: String, notificationType: String? = nil) -> AgentEventKind {
        switch name {
        case "SessionStart": return .sessionStart
        case "SessionEnd": return .sessionEnd
        case "UserPromptSubmit": return .userPromptSubmitted
        case "PreToolUse": return .toolUseStarted
        case "PostToolUse", "PostToolUseFailure": return .toolUseFinished
        case "PermissionRequest": return .permissionRequested
        case "Notification": return notificationKind(notificationType)
        case "Stop", "StopFailure": return .stopped
        case "SubagentStart": return .subagentStarted
        case "SubagentStop": return .subagentFinished
        default: return .unknown
        }
    }

    /// Notification types that mean the session is waiting on the user. Anything
    /// else — including a missing type — is `.unknown`, never a fabricated wait.
    ///
    /// `permission_prompt` asks for approval (orange), so it maps to the same
    /// kind as `PermissionRequest`; the free-text waits map to `.notification`
    /// (amber). This keeps the two "needs you" states visually distinct.
    public static func notificationKind(_ type: String?) -> AgentEventKind {
        switch type {
        case "permission_prompt": return .permissionRequested
        case "idle_prompt", "agent_needs_input": return .notification
        default: return .unknown
        }
    }
}

/// Codex CLI adapter.
///
/// Codex fires `PreToolUse` for ordinary work *and* for its interactive
/// question tool (`request_user_input`), so the event name alone cannot tell
/// "running" from "waiting on you" — the tool name is what disambiguates. Any
/// event we cannot classify stays `.unknown` rather than a fabricated state.
public struct CodexAdapter: AgentEventAdapter {
    public let providerId = "codex"

    public init() {}

    public func adapt(_ raw: RawAgentEvent) -> AgentEvent? {
        guard let sessionId = (raw.payload["session_id"] as? String) ?? (raw.payload["sessionId"] as? String) else {
            return nil
        }
        let name = (raw.payload["hook_event_name"] as? String) ?? (raw.payload["event"] as? String) ?? ""
        let toolName = raw.payload["tool_name"] as? String
        return AgentEvent(providerId: providerId, sessionId: sessionId,
                          kind: Self.kind(forEventName: name, toolName: toolName), at: Date())
    }

    public static func kind(forEventName name: String, toolName: String? = nil) -> AgentEventKind {
        switch name.lowercased() {
        case "sessionstart", "session_start": return .sessionStart
        case "sessionend", "session_end": return .sessionEnd
        case "prettooluse", "pretooluse", "tooluse", "tool_start":
            // An interactive question tool means Codex is blocked on the user,
            // not working — show "waiting for input", not "running".
            return isInteractiveTool(toolName) ? .notification : .toolUseStarted
        case "posttooluse", "tool_end": return .toolUseFinished
        case "permissionrequest", "approval", "approval_request": return .permissionRequested
        case "stop", "complete", "completed": return .stopped
        default: return .unknown
        }
    }

    /// Codex tools that pause the turn for a user answer. `request_user_input`
    /// is the one observed in real sessions; the others are matched defensively
    /// by name so a renamed variant does not silently become "running".
    public static func isInteractiveTool(_ toolName: String?) -> Bool {
        guard let toolName = toolName?.lowercased() else { return false }
        return toolName == "request_user_input"
            || toolName.contains("ask_user")
            || toolName.contains("user_input")
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
