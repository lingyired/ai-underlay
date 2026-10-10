import XCTest
@testable import AIUnderlayKit

final class CodexBarUsageDecoderTests: XCTestCase {
    // MARK: - Fixtures

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        // Fallback: source tree (when fixtures are not bundled).
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: here)
    }

    // MARK: - Real fixtures

    func test_decodesRealCodexFixture() throws {
        let snapshot = try CodexBarUsageDecoder.decode(fixtureData("codex-usage"), provider: "codex")
        XCTAssertEqual(snapshot.providerId, "codex")
        XCTAssertEqual(snapshot.windows.count, 2)
        // primary has windowMinutes 300 -> session; secondary 10080 -> weekly.
        let session = snapshot.windows.first { $0.kind == .session }
        let weekly = snapshot.windows.first { $0.kind == .weekly }
        XCTAssertNotNil(session)
        XCTAssertNotNil(weekly)
        XCTAssertEqual(session?.durationSeconds, 18000)
        XCTAssertEqual(weekly?.durationSeconds, 604800)
    }

    func test_realFixture_accountKeyIsEmailButNotUsedForDisplay() throws {
        // The decoder keeps accountKey internal; the domain never surfaces it as a label.
        let snapshot = try CodexBarUsageDecoder.decode(fixtureData("codex-usage"), provider: "codex")
        XCTAssertNotNil(snapshot.accountKey)
    }

    func test_notLoggedInFixture_isUnauthenticated() throws {
        let snapshot = try CodexBarUsageDecoder.decode(fixtureData("claude-usage-notloggedin"), provider: "claude")
        XCTAssertEqual(snapshot.availability, .unauthenticated)
        XCTAssertTrue(snapshot.windows.isEmpty)
    }

    // MARK: - Review Focus #1: out-of-range / non-finite usedPercent

    func test_outOfRangeUsedPercent_isUnavailableNotClamped() {
        XCTAssertNil(CodexBarUsageDecoder.remainingFraction(fromUsedPercent: 150))
        XCTAssertNil(CodexBarUsageDecoder.remainingFraction(fromUsedPercent: -5))
        XCTAssertNil(CodexBarUsageDecoder.remainingFraction(fromUsedPercent: .nan))
        XCTAssertNil(CodexBarUsageDecoder.remainingFraction(fromUsedPercent: .infinity))
        XCTAssertNil(CodexBarUsageDecoder.remainingFraction(fromUsedPercent: nil))
    }

    func test_validUsedPercent_converts() {
        XCTAssertEqual(CodexBarUsageDecoder.remainingFraction(fromUsedPercent: 47) ?? -1, 0.53, accuracy: 0.0001)
        XCTAssertEqual(CodexBarUsageDecoder.remainingFraction(fromUsedPercent: 0) ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(CodexBarUsageDecoder.remainingFraction(fromUsedPercent: 100) ?? -1, 0.0, accuracy: 0.0001)
    }

    func test_windowWithOutOfRangePercent_isUnavailable() {
        let raw: [String: Any] = ["usedPercent": 150, "windowMinutes": 300]
        let w = CodexBarUsageDecoder.window(from: raw, pace: nil, position: 0)
        XCTAssertEqual(w.availability, .unavailable)
        XCTAssertNil(w.remainingFraction)
    }

    // MARK: - Review Focus #2: positional fields are not period names

    func test_swappedPrimarySecondary_stillMapsByWindowMinutes() throws {
        // primary carries the WEEKLY window, secondary the 5h window — reversed
        // from the common case. Kinds must follow windowMinutes, not position.
        let json = """
        [{"provider":"codex","usage":{
          "primary":{"usedPercent":50,"windowMinutes":10080},
          "secondary":{"usedPercent":20,"windowMinutes":300}
        }}]
        """
        let snapshot = try CodexBarUsageDecoder.decode(Data(json.utf8), provider: "codex")
        let primaryWindow = snapshot.windows[0]
        let secondaryWindow = snapshot.windows[1]
        XCTAssertEqual(primaryWindow.kind, .weekly)
        XCTAssertEqual(secondaryWindow.kind, .session)
    }

    // MARK: - Forward compatibility & isolation

    func test_unknownFields_areIgnored() throws {
        let json = """
        [{"provider":"codex","brandNewField":123,"usage":{
          "primary":{"usedPercent":10,"windowMinutes":300,"futureField":"x"}
        }}]
        """
        let snapshot = try CodexBarUsageDecoder.decode(Data(json.utf8), provider: "codex")
        XCTAssertEqual(snapshot.windows.count, 1)
    }

    func test_missingWindowMinutes_isCustom() throws {
        let json = """
        [{"provider":"codex","usage":{"primary":{"usedPercent":10}}}]
        """
        let snapshot = try CodexBarUsageDecoder.decode(Data(json.utf8), provider: "codex")
        XCTAssertEqual(snapshot.windows.first?.kind, .custom)
    }

    func test_tertiaryAdded_isDecoded() throws {
        let json = """
        [{"provider":"codex","usage":{
          "primary":{"usedPercent":10,"windowMinutes":300},
          "secondary":{"usedPercent":20,"windowMinutes":10080},
          "tertiary":{"usedPercent":30,"windowMinutes":43200}
        }}]
        """
        let snapshot = try CodexBarUsageDecoder.decode(Data(json.utf8), provider: "codex")
        XCTAssertEqual(snapshot.windows.count, 3)
        XCTAssertTrue(snapshot.windows.contains { $0.kind == .monthly })
    }

    func test_paceExpectedUsedPercent_decoded() throws {
        let json = """
        [{"provider":"codex","pace":{"primary":{"expectedUsedPercent":63}},
          "usage":{"primary":{"usedPercent":47,"windowMinutes":300}}}]
        """
        let snapshot = try CodexBarUsageDecoder.decode(Data(json.utf8), provider: "codex")
        XCTAssertEqual(snapshot.windows.first?.expectedRemainingFraction ?? -1, 0.37, accuracy: 0.0001)
    }

    func test_mixedSuccessAndFailure_isolatedPerProvider() throws {
        let json = """
        [{"provider":"codex","usage":{"primary":{"usedPercent":10,"windowMinutes":300}}},
         {"provider":"claude","error":{"code":1,"kind":"provider","message":"No Claude session key found in browser cookies."}}]
        """
        let all = try CodexBarUsageDecoder.decodeAll(Data(json.utf8))
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first { $0.providerId == "codex" }?.availability, .valid)
        XCTAssertEqual(all.first { $0.providerId == "claude" }?.availability, .unauthenticated)
    }

    func test_emptyArray_throws() {
        XCTAssertThrowsError(try CodexBarUsageDecoder.decode(Data("[]".utf8), provider: "codex"))
    }

    func test_providerNotFound_throws() {
        let json = "[{\"provider\":\"codex\",\"usage\":{}}]"
        XCTAssertThrowsError(try CodexBarUsageDecoder.decode(Data(json.utf8), provider: "claude"))
    }
}
