import XCTest
@testable import AIUnderlayKit

@MainActor
final class QuotaEngineManagerTests: XCTestCase {
    private func makeBinary(script: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codexbar-\(UUID().uuidString)")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func test_refresh_noCandidates_isNeitherActiveNorIncompatibleOnly() {
        // An empty search path list discovers nothing.
        let manager = QuotaEngineManager(searchPaths: [])
        manager.refresh { _ in nil }
        XCTAssertTrue(manager.candidates.isEmpty)
        XCTAssertNil(manager.activeEngine)
        XCTAssertFalse(manager.hasIncompatibleOnly, "no candidates at all is not the same as incompatible-only")
    }

    func test_refresh_incompatibleBinary_isIncompatibleOnlyNotNotInstalled() throws {
        // A binary exists but the version probe fails: "found but incompatible",
        // which must not be reported as "not installed".
        let binary = try makeBinary(script: "#!/bin/sh\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: binary) }

        let manager = QuotaEngineManager(searchPaths: [binary])
        manager.refresh { _ in nil }
        XCTAssertFalse(manager.candidates.isEmpty, "the binary must be discovered")
        XCTAssertTrue(manager.hasIncompatibleOnly)
        XCTAssertNil(manager.activeEngine)
    }

    func test_refresh_compatibleBinary_isActive() throws {
        let binary = try makeBinary(script: "#!/bin/sh\necho 'CodexBar 0.58.0'\n")
        defer { try? FileManager.default.removeItem(at: binary) }

        let manager = QuotaEngineManager(searchPaths: [binary])
        manager.refresh { _ in "CodexBar 0.58.0" }
        XCTAssertNotNil(manager.activeEngine)
        XCTAssertFalse(manager.hasIncompatibleOnly)
    }

    func test_cache_marksStaleAfterThreshold() {
        let cache = SnapshotCache(staleThreshold: 10)
        let snapshot = ProviderQuotaSnapshot(
            id: "codex:default", providerId: "codex", accountKey: nil,
            sourceEngineId: "codexbar", windows: [], fetchedAt: Date(), availability: .valid
        )
        let t0 = Date(timeIntervalSince1970: 1000)
        cache.store(snapshot, now: t0)
        XCTAssertEqual(cache.cached(id: "codex:default", now: t0.addingTimeInterval(5))?.availability, .valid)
        XCTAssertEqual(cache.cached(id: "codex:default", now: t0.addingTimeInterval(20))?.availability, .stale)
    }
}
