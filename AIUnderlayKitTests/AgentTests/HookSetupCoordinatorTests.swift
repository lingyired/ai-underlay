import XCTest
@testable import AIUnderlayKit

final class HookSetupCoordinatorTests: XCTestCase {
    private func makeHome(withSettings json: String?) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("hook-\(UUID().uuidString)")
        let dir = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let json {
            try json.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        }
        return home
    }

    func test_preview_addsManagedCommands() throws {
        let home = try makeHome(withSettings: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")

        let preview = try coordinator.preview()
        XCTAssertFalse(preview.addedCommands.isEmpty)
        XCTAssertTrue(preview.addedCommands.allSatisfy { $0.contains(AIUnderlayKit.hookMarker) })
    }

    func test_install_requiresConfirmation() throws {
        let home = try makeHome(withSettings: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")
        XCTAssertThrowsError(try coordinator.install(confirmed: false)) {
            XCTAssertEqual($0 as? HookSetupCoordinator.HookError, .notConfirmed)
        }
    }

    func test_install_preservesExistingContentAndBacksUp() throws {
        let existing = #"{"permissions":{"allow":["Bash"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo user-own"}]}]}}"#
        let home = try makeHome(withSettings: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")

        try coordinator.install(confirmed: true)

        let contents = try String(contentsOf: coordinator.settingsURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("user-own"), "existing hooks must be preserved")
        XCTAssertTrue(contents.contains(AIUnderlayKit.hookMarker), "our hooks must be added")
        XCTAssertTrue(contents.contains("permissions"), "unrelated keys must be preserved")

        // A backup must exist.
        let backups = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".claude").path)
            .filter { $0.contains("settings.json.bak") }
        XCTAssertFalse(backups.isEmpty, "a backup must be written before modifying")
    }

    func test_uninstall_removesOnlyManagedEntries() throws {
        let existing = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo user-own"}]}]}}"#
        let home = try makeHome(withSettings: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")

        try coordinator.install(confirmed: true)
        try coordinator.uninstall()

        let contents = try String(contentsOf: coordinator.settingsURL, encoding: .utf8)
        XCTAssertFalse(contents.contains(AIUnderlayKit.hookMarker), "our entries must be gone")
        XCTAssertTrue(contents.contains("user-own"), "the user's own hook must remain")
    }

    func test_preview_isIdempotent() throws {
        let home = try makeHome(withSettings: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")
        try coordinator.install(confirmed: true)

        let secondPreview = try coordinator.preview()
        XCTAssertTrue(secondPreview.addedCommands.isEmpty, "re-installing must not duplicate entries")
    }

    func test_isInstalled_reflectsState() throws {
        let home = try makeHome(withSettings: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")
        XCTAssertFalse(coordinator.isInstalled())
        try coordinator.install(confirmed: true)
        XCTAssertTrue(coordinator.isInstalled())
    }
}
