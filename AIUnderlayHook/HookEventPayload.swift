import Foundation

/// Reduces a raw provider hook payload to the minimal metadata the app accepts.
///
/// Hooks run inside the agent's turn, and their stdin may contain prompt text,
/// tool arguments, or model output. Only the fields below are ever forwarded, so
/// conversation content cannot reach the socket, the overlay, or disk.
///
/// This file is compiled into both the `aiunderlay-hook` executable (which must
/// stay dependency-free so it starts fast on every tool call) and the unit-test
/// target, so the reduction rules are covered without linking a framework.
enum HookEventPayload {
    /// Builds the forwarded object from a raw payload plus the values the
    /// installer passed on the command line. Returns nil when there is nothing
    /// useful to send — no session id and no event name.
    static func reduce(
        payload: [String: Any],
        provider: String?,
        event: String?
    ) -> [String: Any]? {
        let provider = provider ?? payload["provider"] as? String
        let sessionId = (payload["session_id"] as? String) ?? (payload["sessionId"] as? String)
        let eventName = (payload["hook_event_name"] as? String)
            ?? (payload["event"] as? String)
            ?? event
        // Claude's Notification carries a type; we forward it so the adapter can
        // tell "waiting on you" from unrelated alerts.
        let notificationType = payload["notification_type"] as? String
        // The tool *name* (e.g. "request_user_input") is metadata, like the event
        // name — it is what tells an interactive question apart from ordinary
        // work. The tool *input* is conversation content and is never forwarded.
        let toolName = payload["tool_name"] as? String

        guard sessionId != nil || eventName != nil else { return nil }

        var reduced: [String: Any] = [:]
        if let provider { reduced["provider"] = provider }
        if let sessionId { reduced["session_id"] = sessionId }
        if let eventName { reduced["hook_event_name"] = eventName }
        if let notificationType { reduced["notification_type"] = notificationType }
        if let toolName { reduced["tool_name"] = toolName }
        return reduced
    }

    /// Encodes the reduced object as one newline-terminated JSON line.
    static func line(payload: [String: Any]) -> Data? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return nil
        }
        return data + Data([0x0A])
    }
}