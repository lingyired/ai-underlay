import XCTest
@testable import AIUnderlayKit

final class ProviderCatalogTests: XCTestCase {
    func test_parse_providers() throws {
        let json = """
        [{"enabled":true,"defaultEnabled":true,"provider":"codex","displayName":"Codex"},
         {"enabled":false,"defaultEnabled":false,"provider":"cursor","displayName":"Cursor"}]
        """
        let list = try CodexBarProviderCatalog.parse(Data(json.utf8))
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].id, "codex")
        XCTAssertEqual(list[0].displayName, "Codex")
        XCTAssertTrue(list[0].enabledInCodexBar)
        XCTAssertFalse(list[1].enabledInCodexBar)
    }

    func test_parse_emptyArray() throws {
        XCTAssertTrue(try CodexBarProviderCatalog.parse(Data("[]".utf8)).isEmpty)
    }

    func test_parse_nonArrayThrows() {
        // A non-array payload is a decode error, not silently empty.
        XCTAssertThrowsError(try CodexBarProviderCatalog.parse(Data("not json".utf8)))
    }

    func test_parse_skipsEntriesWithoutProviderKey() throws {
        let json = #"[{"displayName":"NoId"},{"provider":"x","displayName":"X"}]"#
        let list = try CodexBarProviderCatalog.parse(Data(json.utf8))
        XCTAssertEqual(list.map(\.id), ["x"])
    }

    func test_displayedProvidersDefault() {
        XCTAssertEqual(AppSettings.default.displayedProviders, ["codex", "claude"])
    }
}