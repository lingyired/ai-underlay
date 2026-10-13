import XCTest
@testable import AIUnderlayKit

/// The theme format is the contract an AI agent writes against, so it is pinned
/// here: the documented shape parses, and everything malformed is rejected with
/// a reason instead of being half-applied.
final class ThemeDocumentTests: XCTestCase {

    /// The example from the product consensus (§7.3), verbatim.
    private let specExample = """
    {
      "schemaVersion": 1,
      "id": "my-vivid-theme",
      "name": "My Vivid Theme",
      "global": {
        "trackColor": "#253043",
        "trackOpacity": 0.40,
        "baselineColor": "#FFFFFF",
        "baselineEnabled": true
      },
      "providers": {
        "codex": { "quotaLayers": ["#4361EE", "#48C7FF"], "spectrumColor": "#D5F6FF" },
        "claude": { "quotaLayers": ["#F66A42", "#FFB071"], "spectrumColor": "#FFF0C2" }
      },
      "states": {
        "waiting": {
          "overlayColor": "#FFAA22", "overlayOpacity": 0.20,
          "spectrumColor": "#FFC247", "borderColor": "#FFE15C", "borderWidth": 2
        },
        "error": {
          "overlayColor": "#FF355E", "overlayOpacity": 0.22,
          "spectrumColor": "#FF5578", "borderColor": "#FF526A", "borderWidth": 2
        }
      }
    }
    """

    func test_specExampleDecodesAndValidates() throws {
        let document = try ThemeLoader.decode(Data(specExample.utf8))
        XCTAssertEqual(document.id, "my-vivid-theme")
        XCTAssertEqual(document.name, "My Vivid Theme")
        XCTAssertEqual(document.providers?["codex"]?.quotaLayers, ["#4361EE", "#48C7FF"])
        XCTAssertEqual(document.states?["waiting"]?.borderColor, "#FFE15C")
        XCTAssertTrue(ThemeLoader.validate(document).isEmpty)
    }

    func test_builtInThemesAreValid() {
        for theme in ThemePresets.all {
            XCTAssertTrue(ThemeLoader.validate(theme).isEmpty, "\(theme.id) must be valid")
        }
    }

    func test_unsupportedSchemaVersionIsRejectedNotGuessed() {
        let json = #"{"schemaVersion": 7, "id": "x", "name": "X"}"#
        XCTAssertThrowsError(try ThemeLoader.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ThemeLoader.Failure, .unsupportedSchemaVersion(7))
        }
    }

    func test_malformedJSONIsReported() {
        XCTAssertThrowsError(try ThemeLoader.decode(Data("{ not json".utf8))) { error in
            guard case .unreadable = (error as? ThemeLoader.Failure) else {
                return XCTFail("expected .unreadable, got \(error)")
            }
        }
    }

    func test_validationCatchesBadColorsIdsAndRanges() {
        let document = ThemeDocument(
            id: "bad/id",
            name: " ",
            global: .init(trackColor: "#GGGGGG", trackOpacity: 1.5),
            providers: ["codex": .init(quotaLayers: ["#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF"],
                                       spectrumColor: "red")],
            states: ["waiting": .init(borderWidth: 42)]
        )
        let issues = ThemeLoader.validate(document)
        XCTAssertEqual(issues.count, 7, issues.joined(separator: " | "))
        XCTAssertTrue(issues.contains { $0.contains("id 不能包含路径分隔符") })
        XCTAssertTrue(issues.contains { $0.contains("name 不能为空") })
        XCTAssertTrue(issues.contains { $0.contains("不是合法颜色") })
        XCTAssertTrue(issues.contains { $0.contains("0…1") })
        XCTAssertTrue(issues.contains { $0.contains("最多 3 层") })
        XCTAssertTrue(issues.contains { $0.contains("borderWidth") })
    }

    // MARK: - ThemeColor

    func test_hexParsing() {
        XCTAssertEqual(ThemeColor(hex: "#FF8000"),
                       ThemeColor(red: 1, green: 128.0 / 255, blue: 0, alpha: 1))
        XCTAssertEqual(ThemeColor(hex: "FF8000"),
                       ThemeColor(red: 1, green: 128.0 / 255, blue: 0, alpha: 1))
        XCTAssertEqual(ThemeColor(hex: "#F80"),
                       ThemeColor(red: 1, green: 8.0 / 15, blue: 0, alpha: 1))
        XCTAssertEqual(ThemeColor(hex: "#00000080")?.alpha ?? 1, 128.0 / 255, accuracy: 0.001)
    }

    func test_hexRejectsGarbage() {
        for bad in ["", "#12", "#12345", "#GGGGGG", "rgb(1,2,3)"] {
            XCTAssertNil(ThemeColor(hex: bad), "\(bad) must not parse")
        }
    }
}
