import XCTest
@testable import AIUnderlayKit

final class AgentEventAdapterTests: XCTestCase {
    // MARK: - Claude Notification filtering

    func test_notification_permissionPromptIsApproval() {
        // A permission prompt is an approval wait, not a free-text wait.
        XCTAssertEqual(ClaudeCodeAdapter.notificationKind("permission_prompt"), .permissionRequested)
    }

    func test_notification_freeTextWaitsAreNotification() {
        XCTAssertEqual(ClaudeCodeAdapter.notificationKind("idle_prompt"), .notification)
        XCTAssertEqual(ClaudeCodeAdapter.notificationKind("agent_needs_input"), .notification)
    }

    func test_notification_unrelatedAlertsAreUnknown() {
        // These must never light the amber "waiting on you" state.
        for type in ["auth_success", "agent_completed", "quota_auto_resume_fired",
                     "quota_auto_resume_stale", "elicitation_dialog"] {
            XCTAssertEqual(ClaudeCodeAdapter.notificationKind(type), .unknown, "\(type) must be unknown")
        }
    }

    func test_notification_missingTypeIsUnknown() {
        XCTAssertEqual(ClaudeCodeAdapter.notificationKind(nil), .unknown)
    }

    func test_claudeAdapter_mapsNotificationViaType() {
        let adapter = ClaudeCodeAdapter()
        let waiting = adapter.adapt(RawAgentEvent(providerId: "claude", payload: [
            "hook_event_name": "Notification", "session_id": "s", "notification_type": "idle_prompt",
        ]))
        XCTAssertEqual(waiting?.kind, .notification)

        let noise = adapter.adapt(RawAgentEvent(providerId: "claude", payload: [
            "hook_event_name": "Notification", "session_id": "s", "notification_type": "auth_success",
        ]))
        XCTAssertEqual(noise?.kind, .unknown)
    }

    func test_claudeAdapter_doesNotCarryPromptText() {
        let adapter = ClaudeCodeAdapter()
        let event = adapter.adapt(RawAgentEvent(providerId: "claude", payload: [
            "hook_event_name": "UserPromptSubmit", "session_id": "s", "prompt": "secret",
        ]))
        let fields = Mirror(reflecting: event!).children.compactMap { $0.label }
        XCTAssertEqual(Set(fields), ["providerId", "sessionId", "kind", "at"])
    }

    // MARK: - Codex

    func test_codexAdapter_mapsUserPromptSubmit() {
        let adapter = CodexAdapter()
        let event = adapter.adapt(RawAgentEvent(providerId: "codex", payload: [
            "hook_event_name": "UserPromptSubmit", "session_id": "t1",
        ]))
        XCTAssertEqual(event?.kind, .userPromptSubmitted)
        XCTAssertEqual(event?.providerId, "codex")
    }

    func test_codexAdapter_mapsPermissionRequest() {
        // Codex's PermissionRequest payload uses session_id + hook_event_name,
        // the same shape as Claude's.
        let adapter = CodexAdapter()
        let event = adapter.adapt(RawAgentEvent(providerId: "codex", payload: [
            "hook_event_name": "PermissionRequest", "session_id": "t1",
        ]))
        XCTAssertEqual(event?.kind, .permissionRequested)
        XCTAssertEqual(event?.providerId, "codex")
    }

    func test_codexAdapter_unknownEventStaysUnknown() {
        // Codex has no reliable "waiting for free-text answer" event.
        let adapter = CodexAdapter()
        let event = adapter.adapt(RawAgentEvent(providerId: "codex", payload: [
            "hook_event_name": "SomethingNew", "session_id": "t1",
        ]))
        XCTAssertEqual(event?.kind, .unknown)
    }

    func test_codexAdapter_interactiveToolIsWaitingInput() {
        // Codex fires PreToolUse for its question tool; that means it is blocked
        // on the user, not running.
        let adapter = CodexAdapter()
        let event = adapter.adapt(RawAgentEvent(providerId: "codex", payload: [
            "hook_event_name": "PreToolUse", "session_id": "t1", "tool_name": "request_user_input",
        ]))
        XCTAssertEqual(event?.kind, .notification)
    }

    func test_codexAdapter_ordinaryToolIsRunning() {
        let adapter = CodexAdapter()
        let event = adapter.adapt(RawAgentEvent(providerId: "codex", payload: [
            "hook_event_name": "PreToolUse", "session_id": "t1", "tool_name": "exec_command",
        ]))
        XCTAssertEqual(event?.kind, .toolUseStarted)
    }

    func test_codexAdapter_interactiveToolDetection() {
        XCTAssertTrue(CodexAdapter.isInteractiveTool("request_user_input"))
        XCTAssertFalse(CodexAdapter.isInteractiveTool("exec_command"))
        XCTAssertFalse(CodexAdapter.isInteractiveTool(nil))
    }

    func test_codexAdapter_requiresSessionId() {
        let adapter = CodexAdapter()
        XCTAssertNil(adapter.adapt(RawAgentEvent(providerId: "codex", payload: ["hook_event_name": "Stop"])))
    }

    // MARK: - Selection

    func test_adapters_onlySelectSupportedProviders() {
        XCTAssertTrue(AgentAdapters.adapter(for: "claude") is ClaudeCodeAdapter)
        XCTAssertTrue(AgentAdapters.adapter(for: "codex") is CodexAdapter)
        XCTAssertNil(AgentAdapters.adapter(for: "cursor"))
        XCTAssertNil(AgentAdapters.adapter(for: "gemini"))
    }
}
