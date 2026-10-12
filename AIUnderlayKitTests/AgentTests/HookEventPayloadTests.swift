import XCTest
@testable import AIUnderlayKit

/// Covers the reduction rules the `aiunderlay-hook` executable applies before
/// anything touches the socket. The same source file is compiled into the
/// executable, so these assertions describe its real behavior.
final class HookEventPayloadTests: XCTestCase {
    func test_reduce_claudePermissionRequest() {
        let raw: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "abc",
            "tool_input": ["command": "rm -rf /"],
        ]
        let reduced = HookEventPayload.reduce(payload: raw, provider: "claude", event: nil)
        XCTAssertEqual(reduced?["provider"] as? String, "claude")
        XCTAssertEqual(reduced?["session_id"] as? String, "abc")
        XCTAssertEqual(reduced?["hook_event_name"] as? String, "PermissionRequest")
        // Tool arguments must never survive the reduction.
        XCTAssertNil(reduced?["tool_input"])
    }

    func test_reduce_neverCarriesPromptOrToolInput() {
        let raw: [String: Any] = [
            "hook_event_name": "UserPromptSubmit",
            "session_id": "x",
            "prompt": "secret",
            "tool_input": ["path": "/etc/passwd"],
            "cwd": "/Users/someone",
        ]
        let reduced = HookEventPayload.reduce(payload: raw, provider: "claude", event: nil)
        let keys = Set((reduced ?? [:]).keys)
        XCTAssertEqual(keys, ["provider", "session_id", "hook_event_name"])
    }

    func test_reduce_dropsToolInputButKeepsToolName() {
        let raw: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "x",
            "tool_name": "request_user_input",
            "tool_input": ["question": "secret", "options": ["a", "b"]],
        ]
        let reduced = HookEventPayload.reduce(payload: raw, provider: "codex", event: nil)
        let keys = Set((reduced ?? [:]).keys)
        XCTAssertEqual(keys, ["provider", "session_id", "hook_event_name", "tool_name"])
    }

    func test_reduce_forwardsNotificationType() {
        let raw: [String: Any] = [
            "hook_event_name": "Notification",
            "session_id": "x",
            "notification_type": "permission_prompt",
            "message": "Claude needs your permission",
        ]
        let reduced = HookEventPayload.reduce(payload: raw, provider: "claude", event: nil)
        XCTAssertEqual(reduced?["notification_type"] as? String, "permission_prompt")
        XCTAssertNil(reduced?["message"], "the notification text must not be forwarded")
    }

    func test_reduce_forwardsToolNameButNotToolInput() {
        // The tool *name* tells an interactive question from ordinary work; the
        // tool *input* is conversation content and must be dropped.
        let raw: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "x",
            "tool_name": "request_user_input",
            "tool_input": ["question": "where should we go?"],
        ]
        let reduced = HookEventPayload.reduce(payload: raw, provider: "codex", event: nil)
        XCTAssertEqual(reduced?["tool_name"] as? String, "request_user_input")
        XCTAssertNil(reduced?["tool_input"])
    }

    func test_reduce_usesCommandLineEventWhenPayloadOmitsIt() {
        // Codex may not echo the event name; the installer passes it explicitly.
        let raw: [String: Any] = ["session_id": "s1"]
        let reduced = HookEventPayload.reduce(payload: raw, provider: "codex", event: "PermissionRequest")
        XCTAssertEqual(reduced?["hook_event_name"] as? String, "PermissionRequest")
        XCTAssertEqual(reduced?["provider"] as? String, "codex")
    }

    func test_reduce_prefersPayloadEventOverCommandLine() {
        let raw: [String: Any] = ["session_id": "s1", "hook_event_name": "Stop"]
        let reduced = HookEventPayload.reduce(payload: raw, provider: "claude", event: "PreToolUse")
        XCTAssertEqual(reduced?["hook_event_name"] as? String, "Stop")
    }

    func test_reduce_nilWhenNothingUseful() {
        XCTAssertNil(HookEventPayload.reduce(payload: ["foo": "bar"], provider: "claude", event: nil))
    }

    func test_reduce_acceptsCamelCaseSessionId() {
        let raw: [String: Any] = ["sessionId": "camel", "event": "stop"]
        let reduced = HookEventPayload.reduce(payload: raw, provider: "codex", event: nil)
        XCTAssertEqual(reduced?["session_id"] as? String, "camel")
        XCTAssertEqual(reduced?["hook_event_name"] as? String, "stop")
    }

    func test_line_isSingleNewlineTerminatedJSON() throws {
        let line = try XCTUnwrap(HookEventPayload.line(payload: ["provider": "claude", "session_id": "x"]))
        XCTAssertEqual(line.last, 0x0A)
        let body = line.dropLast()
        let object = try JSONSerialization.jsonObject(with: Data(body)) as? [String: Any]
        XCTAssertEqual(object?["provider"] as? String, "claude")
    }
}