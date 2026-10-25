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

    func test_managedCommands_quotePathsWithSpaces() throws {
        let home = try makeHome(withSettings: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        // The real socket lives under "Application Support" — a space the shell
        // would split if the path were not quoted.
        let socket = "/Users/x/Library/Application Support/com.lingsmbp.aiunderlay/agent.sock"
        let coordinator = HookSetupCoordinator(home: home, socketPath: socket, provider: .claude)

        for command in coordinator.managedCommands {
            XCTAssertTrue(command.contains("'\(socket)'"), "socket path must be quoted")
            XCTAssertTrue(command.contains("--provider claude"))
        }
    }

    func test_install_migratesOutdatedOwnedEntries() throws {
        // An entry we own but whose command text predates --provider and quoting.
        let stale = "aiunderlay-hook --event Stop --socket /tmp/old.sock --managed-by=com.lingsmbp.aiunderlay"
        let existing = "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"\(stale)\"}]}]}}"
        let home = try makeHome(withSettings: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .claude)

        try coordinator.install(confirmed: true)

        let contents = try String(contentsOf: coordinator.settingsURL, encoding: .utf8)
        XCTAssertFalse(contents.contains("/tmp/old.sock"), "the stale command must be replaced")
        XCTAssertFalse(contents.contains("--event Stop --socket"), "the outdated form must be gone")
        XCTAssertTrue(contents.contains("--provider claude"), "the refreshed command must be present")
        // Exactly one Stop entry — migrated in place, not duplicated.
        let stopEntries = contents.components(separatedBy: AIUnderlayKit.hookMarker).count - 1
        XCTAssertEqual(stopEntries, 8, "one managed entry per event, no duplicates")
    }

    func test_preview_afterMigration_isIdempotent() throws {
        let home = try makeHome(withSettings: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .claude)
        try coordinator.install(confirmed: true)

        let second = try coordinator.preview()
        XCTAssertTrue(second.addedCommands.isEmpty, "a second pass must not rewrite or duplicate")
    }

    func test_isInstalled_falseWhenOwnedEntriesAreOutdated() throws {
        let stale = "aiunderlay-hook --event Stop --socket /tmp/old.sock --managed-by=com.lingsmbp.aiunderlay"
        let existing = "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"\(stale)\"}]}]}}"
        let home = try makeHome(withSettings: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .claude)
        // We own an entry, but it is stale — the UI must offer to (re)install.
        XCTAssertFalse(coordinator.isInstalled())
    }

    // MARK: - Codex

    private func makeCodexHome(withHooks json: String?) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("hook-\(UUID().uuidString)")
        let dir = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let json {
            try json.write(to: dir.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        }
        return home
    }

    func test_codex_writesToHooksJson() throws {
        let home = try makeCodexHome(withHooks: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .codex)
        XCTAssertEqual(coordinator.settingsURL.path, home.appendingPathComponent(".codex/hooks.json").path)

        try coordinator.install(confirmed: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: coordinator.settingsURL.path))
        XCTAssertTrue(coordinator.isInstalled())
    }

    func test_codex_omitsNotificationEvent() throws {
        // Codex has no Notification event; installing one would be dead config.
        let home = try makeCodexHome(withHooks: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .codex)
        XCTAssertFalse(HookSetupCoordinator.Provider.codex.eventNames.contains("Notification"))
        XCTAssertTrue(HookSetupCoordinator.Provider.codex.eventNames.contains("PermissionRequest"))
        for command in coordinator.managedCommands {
            XCTAssertTrue(command.contains("--provider codex"))
        }
    }

    func test_codex_preservesExistingForeignHooks() throws {
        // The user's ~/.codex/hooks.json may already hold another tool's hooks;
        // we must merge, never replace.
        let existing = #"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo orca-owns-this"}]}]}}"#
        let home = try makeCodexHome(withHooks: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .codex)

        try coordinator.install(confirmed: true)
        var contents = try String(contentsOf: coordinator.settingsURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("orca-owns-this"), "the foreign hook must survive install")

        try coordinator.uninstall()
        contents = try String(contentsOf: coordinator.settingsURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("orca-owns-this"), "the foreign hook must survive uninstall")
        XCTAssertFalse(contents.contains(AIUnderlayKit.hookMarker), "only our entries are removed")
    }

    func test_codex_claudeEntriesAreIndependent() throws {
        // Installing one provider must not mark the other as installed.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let claude = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .claude)
        let codex = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .codex)

        try claude.install(confirmed: true)
        XCTAssertTrue(claude.isInstalled())
        XCTAssertFalse(codex.isInstalled(), "a Claude install must not satisfy Codex")
    }

    // MARK: - Ownership detection

    func test_hasManagedEntries_falseWhenFileMissing() throws {
        let home = try makeHome(withSettings: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")
        XCTAssertFalse(try coordinator.hasManagedEntries())
    }

    func test_hasManagedEntries_falseForForeignHooksAndConfig() throws {
        // Regression: the settings file existing is not ownership. Before this
        // check, any existing file (e.g. only foreign hooks) made the UI report
        // "needs update" even though this app had installed nothing.
        let existing = #"{"permissions":{"allow":["Bash"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo user-own"}]}]}}"#
        let home = try makeHome(withSettings: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")
        XCTAssertFalse(try coordinator.hasManagedEntries())
        XCTAssertFalse(coordinator.isInstalled())
    }

    func test_hasManagedEntries_trueForOutdatedOwnedEntries() throws {
        let stale = "aiunderlay-hook --event Stop --socket /tmp/old.sock --managed-by=com.lingsmbp.aiunderlay"
        let existing = "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"\(stale)\"}]}]}}"
        let home = try makeHome(withSettings: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")
        XCTAssertTrue(try coordinator.hasManagedEntries(),
                      "an entry we own but whose command drifted still counts as ours")
        XCTAssertFalse(coordinator.isInstalled())
    }

    func test_hasManagedEntries_codexLifecycle() throws {
        let home = try makeCodexHome(withHooks: nil)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .codex)
        XCTAssertFalse(try coordinator.hasManagedEntries())
        try coordinator.install(confirmed: true)
        XCTAssertTrue(try coordinator.hasManagedEntries())
        try coordinator.uninstall()
        XCTAssertFalse(try coordinator.hasManagedEntries(), "cleanup leaves no owned entries behind")
    }

    func test_hasManagedEntries_isProviderScoped() throws {
        // Installing Claude must never make Codex look like it holds our entries.
        let home = try FileManager.default.temporaryDirectory.appendingPathComponent("hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let claude = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .claude)
        let codex = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .codex)
        try claude.install(confirmed: true)
        XCTAssertTrue(try claude.hasManagedEntries())
        XCTAssertFalse(try codex.hasManagedEntries())
    }

    func test_hasManagedEntries_throwsOnMalformedFile() throws {
        let home = try makeHome(withSettings: "{not json")
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")
        XCTAssertThrowsError(try coordinator.hasManagedEntries()) {
            XCTAssertEqual($0 as? HookSetupCoordinator.HookError, .malformedSettings)
        }
        XCTAssertThrowsError(try coordinator.preview()) {
            XCTAssertEqual($0 as? HookSetupCoordinator.HookError, .malformedSettings,
                           "invalid JSON must surface as malformedSettings, not a Cocoa parse error")
        }
    }

    // MARK: - Cleanup safety

    private func managedCommand(for event: String) -> String {
        "aiunderlay-hook --event \(event) --socket /tmp/x.sock --provider claude "
            + AIUnderlayKit.hookMarker
    }

    func test_uninstall_keepsForeignHandlersInASharedGroup() throws {
        // Regression: a matcher group can hold the user's handler and ours.
        // Cleanup must filter only our command handler, not drop the group.
        let managed = managedCommand(for: "Stop")
        let existing = """
        {"hooks":{"Stop":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo user-own"},{"type":"command","command":"\(managed)"}]}],"SessionEnd":[{"hooks":[{"type":"command","command":"\(managed)"}]}]}}
        """
        let home = try makeHome(withSettings: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")

        try coordinator.uninstall()

        let data = try Data(contentsOf: coordinator.settingsURL)
        let parsed = try JSONSerialization.jsonObject(with: data)
        let root = try XCTUnwrap(parsed as? [String: Any])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertNil(hooks["SessionEnd"], "an event left with no handlers is dropped")
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 1, "the shared group must survive")
        XCTAssertEqual(stop[0]["matcher"] as? String, "Bash", "matcher fields must survive")
        let handlers = try XCTUnwrap(stop[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(handlers.compactMap { $0["command"] as? String }, ["echo user-own"])
    }

    func test_previewAndInstall_refreshKeepsForeignHandlersInASharedGroup() throws {
        // Regression: refreshing a stale owned command must not replace the
        // whole matcher group when other tools share it.
        let stale = "aiunderlay-hook --event Stop --socket /tmp/old.sock --managed-by=com.lingsmbp.aiunderlay"
        let existing = """
        {"hooks":{"Stop":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo user-own"},{"type":"command","command":"\(stale)"}]}]}}
        """
        let home = try makeHome(withSettings: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock", provider: .claude)

        let preview = try coordinator.preview()
        try assertSharedStopGroupIsPreserved(in: Data(preview.after.utf8))

        try coordinator.install(confirmed: true)
        try assertSharedStopGroupIsPreserved(in: Data(contentsOf: coordinator.settingsURL))
    }

    private func assertSharedStopGroupIsPreserved(
        in data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let parsed = try JSONSerialization.jsonObject(with: data)
        let root = try XCTUnwrap(parsed as? [String: Any], file: file, line: line)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any], file: file, line: line)
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]], file: file, line: line)
        XCTAssertEqual(stop.count, 1, file: file, line: line)
        XCTAssertEqual(stop[0]["matcher"] as? String, "Bash", "matcher fields must survive", file: file, line: line)
        let handlers = try XCTUnwrap(stop[0]["hooks"] as? [[String: Any]], file: file, line: line)
        XCTAssertEqual(handlers.count, 2, "the foreign handler must not be dropped", file: file, line: line)
        XCTAssertEqual(handlers[0]["command"] as? String, "echo user-own", file: file, line: line)
        let refreshed = try XCTUnwrap(handlers[1]["command"] as? String, file: file, line: line)
        XCTAssertFalse(refreshed.contains("/tmp/old.sock"), "the stale command must be replaced", file: file, line: line)
        XCTAssertTrue(refreshed.contains("--provider claude"), file: file, line: line)
        XCTAssertTrue(refreshed.contains(AIUnderlayKit.hookMarker), file: file, line: line)
    }

    func test_uninstall_backsUpBeforeRemovingManagedEntries() throws {
        let managed = managedCommand(for: "Stop")
        let existing = "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"\(managed)\"}]}]}}"
        let home = try makeHome(withSettings: existing)
        defer { try? FileManager.default.removeItem(at: home) }
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")

        try coordinator.uninstall()

        let directory = home.appendingPathComponent(".claude")
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains("settings.json.bak") }
        let backupName = try XCTUnwrap(backups.first, "cleanup must leave a backup")
        let backup = try String(contentsOf: directory.appendingPathComponent(backupName), encoding: .utf8)
        XCTAssertTrue(backup.contains(managed), "the backup must hold the pre-cleanup file")
    }

    func test_uninstall_abortsWhenBackupCannotBeWritten() throws {
        try XCTSkipIf(NSUserName() == "root", "permission checks do not fail for root")
        let managed = managedCommand(for: "Stop")
        let existing = "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"\(managed)\"}]}]}}"
        let home = try makeHome(withSettings: existing)
        let directory = home.appendingPathComponent(".claude")
        let settings = directory.appendingPathComponent("settings.json")
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: home)
        }
        let before = try String(contentsOf: settings, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let coordinator = HookSetupCoordinator(home: home, socketPath: "/tmp/x.sock")

        XCTAssertThrowsError(try coordinator.uninstall(),
                             "a failed backup must abort cleanup instead of writing without one")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        let after = try String(contentsOf: settings, encoding: .utf8)
        XCTAssertEqual(after, before, "a failed backup leaves the settings file untouched")
    }
}
