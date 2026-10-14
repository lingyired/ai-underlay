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

    /// CodexBar spawns its own headless `claude` to read quota and reports it as
    /// a live session. It must never be counted as agent activity, or the
    /// provider looks busy while the user has nothing running.
    func test_parse_dropsCodexBarOwnClaudeProbe() throws {
        let json = """
        [{"provider":"claude","state":"active","source":"cli","id":"pid:28131",
          "projectName":"ClaudeProbe",
          "cwd":"/Users/someone/Library/Application Support/CodexBar/ClaudeProbe",
          "startedAt":"2026-10-14T04:57:44Z"}]
        """
        XCTAssertTrue(try CodexBarSessionCatalog.parse(Data(json.utf8)).isEmpty)
    }

    /// A probe without its project name is still recognised by its directory.
    func test_parse_dropsAnySessionInsideCodexBarSupport() throws {
        let json = """
        [{"provider":"claude","state":"active","source":"cli","id":"pid:999",
          "cwd":"/Users/someone/Library/Application Support/CodexBar/ClaudeProbe"}]
        """
        XCTAssertTrue(try CodexBarSessionCatalog.parse(Data(json.utf8)).isEmpty)
    }

    /// The user's own Claude Code session in a normal project must survive.
    func test_parse_keepsARealClaudeSession() throws {
        let json = """
        [{"provider":"claude","sessionName":"修复 Issue 72","projectName":"status-trio",
          "source":"cli","state":"active","id":"pid:4242",
          "cwd":"/Users/someone/Documents/aiwork/status-trio"}]
        """
        let sessions = try CodexBarSessionCatalog.parse(Data(json.utf8))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].provider, "claude")
        XCTAssertEqual(sessions[0].agentState, .running)
    }
}
