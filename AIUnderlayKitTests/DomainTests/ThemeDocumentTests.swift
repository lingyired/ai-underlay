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

    // MARK: - schemaVersion 2 (Glass Spectrum)

    func test_v2SelectedGlassV5RoundTripsThroughJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ThemePresets.selectedGlassV5)
        let decoded = try ThemeLoader.decode(data)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded, ThemePresets.selectedGlassV5)
        XCTAssertEqual(decoded.providers?["codex"]?.quotaBaseColor, "#69BFFF")
        XCTAssertEqual(decoded.providers?["codex"]?.agentThemeColor, "#62AC96")
        XCTAssertEqual(decoded.global?.exhaustedTrackColor, "#000000")
        XCTAssertEqual(decoded.material?.rayDensity, 1.0)
        XCTAssertEqual(decoded.attention?.sweepSecondsError, 4)
    }

    func test_v2ExportIsWhatTheThemeTabHandsToAgents() {
        XCTAssertTrue(ThemePresets.exampleJSON.contains("\"schemaVersion\" : 2"))
        XCTAssertTrue(ThemePresets.exampleJSON.contains("#69BFFF"))
    }

    /// The shipped examples are part of the contract an AI agent copies from;
    /// they must decode and validate with the same rules as any user file.
    func test_shippedExamplesAllDecodeAndValidate() throws {
        let examples = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DomainTests
            .deletingLastPathComponent()   // AIUnderlayKitTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("docs/theme/examples", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: examples, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 2, "vivid (v1) and selected-glass-v5 (v2) must ship")
        for file in files {
            let data = try Data(contentsOf: file)
            XCTAssertNoThrow(try ThemeLoader.decode(data), "\(file.lastPathComponent) must validate")
        }
        // The v2 example mirrors exactly what the app exports today.
        let v5 = try Data(contentsOf: examples.appendingPathComponent("selected-glass-v5.json"))
        XCTAssertEqual(try ThemeLoader.decode(v5), ThemePresets.selectedGlassV5)
    }

    func test_v2FileMayNameOnlyTheRequiredFields() throws {
        let json = #"{"schemaVersion":2,"id":"minimal","name":"Minimal"}"#
        let document = try ThemeLoader.decode(Data(json.utf8))
        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertNil(document.material)
        XCTAssertNil(document.signals)
    }

    /// v1 files keep their own vocabulary; a v2 file may still use v1 fields
    /// (mixed documents are decoded into one resolved theme).
    func test_v1AndV2FieldsCoexistWithoutValidationErrors() throws {
        let json = #"""
        {"schemaVersion":2,"id":"mixed","name":"Mixed",
         "providers":{"codex":{"quotaLayers":["#111111"],"quotaBaseColor":"#69BFFF","agentThemeColor":"#62AC96"}},
         "states":{"waiting":{"borderColor":"#FFE15C"}},
         "signals":{"waiting":{"lightColor":"#FFE1A0"}}}
        """#
        let document = try ThemeLoader.decode(Data(json.utf8))
        XCTAssertEqual(document.providers?["codex"]?.quotaLayers, ["#111111"])
        XCTAssertEqual(document.states?["waiting"]?.borderColor, "#FFE15C")
        XCTAssertEqual(document.signals?.waiting?.lightColor, "#FFE1A0")
    }

    func test_v2ValidationCatchesOutOfRangeMaterialAttentionAndSignals() {
        let document = ThemeDocument(
            schemaVersion: 2,
            id: "v2-bad",
            name: "V2 Bad",
            global: .init(exhaustedTrackColor: "#000000", exhaustedTrackOpacity: 1.5),
            providers: ["codex": .init(quotaBaseColor: "not-a-color")],
            signals: .init(running: .init(lightColor: "#GGGGGG")),
            material: .init(blurRadiusTarget: 40, grain: -0.1),
            attention: .init(bottomRibbonHeight: 12, sweepSecondsError: 0.5)
        )
        let issues = ThemeLoader.validate(document)
        XCTAssertTrue(issues.contains { $0.contains("global.exhaustedTrackOpacity") }, issues.joined(separator: " | "))
        XCTAssertTrue(issues.contains { $0.contains("providers.codex.quotaBaseColor") })
        XCTAssertTrue(issues.contains { $0.contains("signals.running.lightColor") })
        XCTAssertTrue(issues.contains { $0.contains("material.blurRadiusTarget") })
        XCTAssertTrue(issues.contains { $0.contains("material.grain") })
        XCTAssertTrue(issues.contains { $0.contains("attention.bottomRibbonHeight") })
        XCTAssertTrue(issues.contains { $0.contains("attention.sweepSecondsError") })
    }

    func test_invalidV2FileIsRejectedWithReasonsNotHalfApplied() {
        let json = #"{"schemaVersion":2,"id":"x","name":"X","material":{"rayDensity":9}}"#
        XCTAssertThrowsError(try ThemeLoader.decode(Data(json.utf8))) { error in
            guard case .invalid(let issues) = (error as? ThemeLoader.Failure) else {
                return XCTFail("expected .invalid, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.contains("material.rayDensity") })
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
