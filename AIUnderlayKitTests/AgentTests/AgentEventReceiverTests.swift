import XCTest
@testable import AIUnderlayKit

final class AgentEventReceiverTests: XCTestCase {
    func test_parse_claudeHookLine() {
        let json = #"{"provider":"claude","hook_event_name":"PermissionRequest","session_id":"abc"}"#
        let event = AgentEventReceiver.parse(line: Data(json.utf8))
        XCTAssertEqual(event?.providerId, "claude")
        XCTAssertEqual(event?.sessionId, "abc")
        XCTAssertEqual(event?.kind, .permissionRequested)
    }

    func test_parse_codexUnknownEvent_isUnknown() {
        let json = #"{"provider":"codex","event":"mystery","session_id":"x"}"#
        XCTAssertEqual(AgentEventReceiver.parse(line: Data(json.utf8))?.kind, .unknown)
    }

    func test_parse_rejectsMalformed() {
        XCTAssertNil(AgentEventReceiver.parse(line: Data("not json".utf8)))
    }

    func test_parse_rejectsUnknownProvider() {
        let json = #"{"provider":"gemini","hook_event_name":"Stop","session_id":"x"}"#
        XCTAssertNil(AgentEventReceiver.parse(line: Data(json.utf8)))
    }

    func test_parse_rejectsOversizedLine() {
        let big = String(repeating: "a", count: AgentEventReceiver.maxLineBytes + 1)
        XCTAssertNil(AgentEventReceiver.parse(line: Data(big.utf8)))
    }

    func test_parse_neverCarriesPromptText() {
        // Even if a hook payload contains a prompt, the normalized event has no
        // field to carry it.
        let json = #"{"provider":"claude","hook_event_name":"UserPromptSubmit","session_id":"x","prompt":"secret"}"#
        let event = AgentEventReceiver.parse(line: Data(json.utf8))
        XCTAssertEqual(event?.kind, .userPromptSubmitted)
        // The event type has only providerId/sessionId/kind/at.
        let mirror = Mirror(reflecting: event!)
        let fields = mirror.children.compactMap { $0.label }
        XCTAssertEqual(Set(fields), ["providerId", "sessionId", "kind", "at"])
    }
}
