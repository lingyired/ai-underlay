import XCTest
@testable import AIUnderlayKit

final class CLIInventoryTests: XCTestCase {
    func test_parseVersion_readsCodexBarVersion() {
        XCTAssertEqual(CLIInventory.parseVersion(from: "CodexBar 0.58.0\n"), "0.58.0")
    }

    func test_parseVersion_nilForForeignBinary() {
        XCTAssertNil(CLIInventory.parseVersion(from: "jq-1.7\n"))
    }

    func test_candidatePaths_manualComesFirst() {
        let manual = URL(fileURLWithPath: "/custom/bin/codexbar")
        let paths = CLIInventory.candidatePaths(manualPath: manual)
        XCTAssertEqual(paths.first, manual)
    }

    func test_candidatePaths_includesManagedAndHomebrew() {
        let paths = CLIInventory.candidatePaths(manualPath: nil)
        XCTAssertTrue(paths.contains { $0.path == "/opt/homebrew/bin/codexbar" })
        XCTAssertTrue(paths.contains { $0.path.contains("Application Support/com.lingsmbp.aiunderlay/Engines/CodexBar") })
    }

    func test_probe_skipsMissingFile() {
        let missing = URL(fileURLWithPath: "/nonexistent/codexbar-\(UUID().uuidString)")
        XCTAssertNil(CLIInventory.probe(url: missing) { _ in "CodexBar 0.58.0" })
    }

    func test_probe_skipsNonExecutable() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notexec-\(UUID().uuidString)")
        try "data".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Written without the executable bit.
        XCTAssertNil(CLIInventory.probe(url: tmp) { _ in "CodexBar 0.58.0" })
    }

    func test_probe_incompatibleWhenVersionProbeFails() throws {
        let exe = try makeExecutable(script: "#!/bin/sh\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: exe) }
        let candidate = CLIInventory.probe(url: exe) { _ in nil }
        XCTAssertEqual(candidate?.compatibility, .incompatible)
        XCTAssertNil(candidate?.version)
    }

    func test_probe_compatibleWhenVersionParses() throws {
        let exe = try makeExecutable(script: "#!/bin/sh\necho 'CodexBar 0.58.0'\n")
        defer { try? FileManager.default.removeItem(at: exe) }
        let candidate = CLIInventory.probe(url: exe) { _ in "CodexBar 0.58.0" }
        XCTAssertEqual(candidate?.compatibility, .compatible)
        XCTAssertEqual(candidate?.version, "0.58.0")
    }

    func test_discover_deduplicatesResolvedPaths() throws {
        let exe = try makeExecutable(script: "#!/bin/sh\necho 'CodexBar 0.58.0'\n")
        defer { try? FileManager.default.removeItem(at: exe) }
        let results = CLIInventory.discover(manualPath: exe) { _ in "CodexBar 0.58.0" }
        let paths = results.map(\.url.path)
        XCTAssertEqual(paths.count, Set(paths).count)
    }

    // MARK: - Helpers

    private func makeExecutable(script: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codexbar-\(UUID().uuidString)")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}