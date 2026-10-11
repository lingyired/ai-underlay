import XCTest
@testable import AIUnderlayKit

final class SessionCatalogTests: XCTestCase {
    func test_parse_sessions() throws {
        let json = """
        [{"provider":"codex","sessionName":"实现独立图标设计器","projectName":"status-trio",
          "source":"desktopApp","state":"active","lastActivityAt":"2026-10-11T15:53:59Z",
          "id":"01a121aa"}]
        """
        let sessions = try CodexBarSessionCatalog.parse(Data(json.utf8))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].provider, "codex")
        XCTAssertEqual(sessions[0].state, "active")
        XCTAssertEqual(sessions[0].agentState, .running)
        XCTAssertNotNil(sessions[0].lastActivityAt)
    }

    func test_stateMapping() {
        func info(_ state: String) -> AgentSessionInfo {
            AgentSessionInfo(id: "x", provider: "codex", sessionName: "", projectName: nil,
                             state: state, lastActivityAt: nil, source: nil)
        }
        XCTAssertEqual(info("active").agentState, .running)
        XCTAssertEqual(info("idle").agentState, .idle)
        // Anything unknown is never promoted to a definite state.
        XCTAssertEqual(info("mystery").agentState, .unknown)
    }

    func test_inferredConfidence() {
        let info = AgentSessionInfo(id: "x", provider: "claude", sessionName: "s", projectName: nil,
                                    state: "active", lastActivityAt: nil, source: nil)
        XCTAssertEqual(info.asAgentSession.confidence, .inferred)
        XCTAssertEqual(info.asAgentSession.providerId, "claude")
    }

    func test_parse_empty() throws {
        XCTAssertTrue(try CodexBarSessionCatalog.parse(Data("[]".utf8)).isEmpty)
    }
}