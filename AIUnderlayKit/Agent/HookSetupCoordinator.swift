import Foundation

/// Installs and removes agent lifecycle hooks.
///
/// Both supported providers use the same on-disk shape — a JSON file whose
/// `hooks` object maps an event name to a list of matcher groups, each holding
/// command handlers — so one coordinator serves both. They differ only in the
/// file (`~/.claude/settings.json` vs `~/.codex/hooks.json`) and in which events
/// they actually emit.
///
/// Safety rules, in order of importance:
/// 1. Never install without explicit user confirmation (this type only
///    *produces* a preview and *applies* an approved preview).
/// 2. Preserve the existing file: parse, add only our entries, back up first.
/// 3. On uninstall, remove only command handlers carrying our marker and keep
///    every other handler, matcher field, and untouched group intact.
public struct HookSetupCoordinator {
    /// A provider whose hooks we can install.
    public enum Provider: String, Sendable, CaseIterable {
        case claude
        case codex

        /// Path, relative to the home directory, of the file hooks live in.
        public var settingsRelativePath: String {
            switch self {
            case .claude: return ".claude/settings.json"
            case .codex: return ".codex/hooks.json"
            }
        }

        /// The events this provider actually emits. Installing a hook for an
        /// event a provider never fires would just be dead configuration — and
        /// Codex has no `Notification` event, so its "needs you" signal comes
        /// only from `PermissionRequest`.
        public var eventNames: [String] {
            switch self {
            case .claude:
                return ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                        "PermissionRequest", "Notification", "Stop", "SessionEnd"]
            case .codex:
                return ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                        "PermissionRequest", "Stop", "SessionEnd"]
            }
        }
    }

    public struct ChangePreview: Equatable {
        public var before: String
        public var after: String
        public var addedCommands: [String]

        public init(before: String, after: String, addedCommands: [String]) {
            self.before = before
            self.after = after
            self.addedCommands = addedCommands
        }
    }

    public enum HookError: Error, Equatable {
        case malformedSettings
        case notConfirmed
    }

    private let home: URL
    private let socketPath: String
    private let helperCommand: String
    /// The provider whose hooks this instance manages.
    private let provider: Provider

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        socketPath: String = AgentEventReceiver.defaultSocketURL().path,
        helperCommand: String = HookSetupCoordinator.defaultHelperCommand(),
        provider: Provider = .claude
    ) {
        self.home = home
        self.socketPath = socketPath
        self.helperCommand = helperCommand
        self.provider = provider
    }

    /// The path the hook commands should invoke. Prefers the `aiunderlay-hook`
    /// binary embedded in the running app bundle (always present and correctly
    /// versioned); falls back to the bare name when there is no bundle — in
    /// tests, or if a user places the binary on their PATH themselves.
    public static func defaultHelperCommand() -> String {
        let embedded = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/aiunderlay-hook")
        if FileManager.default.isExecutableFile(atPath: embedded.path) {
            return embedded.path
        }
        return "aiunderlay-hook"
    }

    public var settingsURL: URL { home.appendingPathComponent(provider.settingsRelativePath) }

    /// The provider id the installed hooks report as. Claude's hook payload does
    /// not name the provider, so the command line carries it.
    public var providerId: String { provider.rawValue }

    /// The hook entries we would add, each carrying the management marker so we
    /// can find them again on uninstall. Paths are shell-quoted because the
    /// socket lives under "Application Support" — a space the shell would
    /// otherwise split.
    public var managedCommands: [String] {
        provider.eventNames.map { event in
            "\(Self.shellQuote(helperCommand)) --event \(event) --provider \(provider.rawValue) "
                + "--socket \(Self.shellQuote(socketPath)) \(AIUnderlayKit.hookMarker)"
        }
    }

    /// Minimal POSIX single-quote escaping for a path embedded in a hook command.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Produces a diff preview without writing anything.
    ///
    /// Command handlers we own are refreshed in place when their command text
    /// has changed (e.g. the helper path, socket quoting, or a new `--provider`
    /// argument), so an upgrade migrates old entries instead of leaving them
    /// broken. Matcher groups keep their fields and the handlers we do not own
    /// are never touched.
    public func preview() throws -> ChangePreview {
        let (object, original) = try loadSettings()
        var updated = object
        var hooks = updated["hooks"] as? [String: Any] ?? [:]

        var added: [String] = []
        for (event, command) in zip(provider.eventNames, managedCommands) {
            var list = hooks[event] as? [[String: Any]] ?? []
            if let index = list.firstIndex(where: { Self.isManaged($0) }) {
                // Refresh our own handler if its command text drifted.
                if !Self.commands(list[index]).contains(command) {
                    list[index] = Self.refreshedGroup(list[index], command: command)
                    added.append(command)
                }
            } else {
                list.append(["hooks": [["type": "command", "command": command]]])
                added.append(command)
            }
            hooks[event] = list
        }
        updated["hooks"] = hooks

        let after = try serialize(updated)
        return ChangePreview(before: original, after: after, addedCommands: added)
    }

    /// Whether a hook entry carries our management marker.
    static func isManaged(_ entry: [String: Any]) -> Bool {
        commands(entry).contains { $0.contains(AIUnderlayKit.hookMarker) }
    }

    /// Whether one command handler (an entry inside a matcher group's `hooks`
    /// array) carries our management marker.
    static func isManagedHandler(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(AIUnderlayKit.hookMarker) == true
    }

    /// Rewrites a matcher group we own so only our command handler changes:
    /// the matcher, any extra group fields, and every handler we do not own
    /// survive untouched. Additional marker-bearing handlers are duplicates of
    /// ours, so they collapse into the single refreshed command.
    static func refreshedGroup(_ group: [String: Any], command: String) -> [String: Any] {
        var updated = group
        let handlers = group["hooks"] as? [[String: Any]] ?? []
        var result: [[String: Any]] = []
        var refreshed = false
        for handler in handlers {
            guard Self.isManagedHandler(handler) else {
                result.append(handler)
                continue
            }
            guard !refreshed else { continue }
            var updatedHandler = handler
            updatedHandler["type"] = updatedHandler["type"] ?? "command"
            updatedHandler["command"] = command
            result.append(updatedHandler)
            refreshed = true
        }
        if !refreshed {
            // Unreachable for groups `isManaged` accepts, but never leave the
            // group without the command the preview promises to install.
            result = [["type": "command", "command": command]]
        }
        updated["hooks"] = result
        return updated
    }

    /// Applies an approved preview, backing up the original first.
    public func install(confirmed: Bool) throws {
        guard confirmed else { throw HookError.notConfirmed }
        let preview = try preview()
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        try backUpExistingFile()
        try preview.after.write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    /// Removes only command handlers carrying our marker, preserving everything
    /// else. Matcher groups keep their other handlers and fields; a group is
    /// dropped only when removing our handlers leaves it with none. The file is
    /// backed up first, and a failed backup aborts the cleanup without writing.
    public func uninstall() throws {
        let (object, _) = try loadSettings()
        guard let hooks = object["hooks"] as? [String: Any] else { return }

        var updated = object
        var updatedHooks: [String: Any] = [:]
        var removedAny = false

        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                updatedHooks[event] = value
                continue
            }
            var keptGroups: [[String: Any]] = []
            for var group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    keptGroups.append(group)
                    continue
                }
                let remaining = handlers.filter { !Self.isManagedHandler($0) }
                if remaining.count == handlers.count {
                    keptGroups.append(group)
                } else {
                    removedAny = true
                    if !remaining.isEmpty {
                        group["hooks"] = remaining
                        keptGroups.append(group)
                    }
                }
            }
            if !keptGroups.isEmpty { updatedHooks[event] = keptGroups }
        }

        guard removedAny else { return }

        if updatedHooks.isEmpty {
            updated.removeValue(forKey: "hooks")
        } else {
            updated["hooks"] = updatedHooks
        }
        try backUpExistingFile()
        try serialize(updated).write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    /// True when our hooks are installed *and* up to date. An entry we own but
/// whose command text has drifted (older helper path, missing quoting or
/// `--provider`) counts as not installed, so the UI offers to reinstall and
/// migrate it rather than silently leaving a broken command in place.
    public func isInstalled() -> Bool {
        guard let (object, _) = try? loadSettings(),
              let hooks = object["hooks"] as? [String: Any] else { return false }
        for (event, command) in zip(provider.eventNames, managedCommands) {
            let list = hooks[event] as? [[String: Any]] ?? []
            guard list.contains(where: { Self.commands($0).contains(command) }) else { return false }
        }
        return true
    }

    /// Whether the settings file holds any entry we own, up to date or not.
    ///
    /// Unlike `isInstalled()`, this never looks at the current command text, so
    /// outdated entries written by an older version still count. It exists so
    /// the UI can offer cleanup for app-owned hooks, and so "needs update" is
    /// decided by proven ownership rather than by the settings file merely
    /// existing for somebody else's configuration. A missing file is `false`;
    /// an unreadable or malformed file throws.
    public func hasManagedEntries() throws -> Bool {
        let (object, _) = try loadSettings()
        guard let hooks = object["hooks"] as? [String: Any] else { return false }
        for value in hooks.values {
            guard let list = value as? [[String: Any]] else { continue }
            if list.contains(where: { Self.isManaged($0) }) { return true }
        }
        return false
    }

    // MARK: - Helpers

    /// Copies the current file aside before we modify it. A failed copy throws
    /// instead of continuing: writing without the promised backup is worse than
    /// not writing at all, and callers must not report a backup that is absent.
    private func backUpExistingFile() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        try FileManager.default.copyItem(at: settingsURL, to: nextBackupURL())
    }

    /// Timestamped in milliseconds so successive edits (for example install
    /// immediately followed by cleanup) keep distinct backups; the suffix loop
    /// keeps the copy from failing if a name is already taken.
    private func nextBackupURL() -> URL {
        let base = settingsURL.path + ".bak.\(Int(Date().timeIntervalSince1970 * 1000))"
        var candidate = URL(fileURLWithPath: base)
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: "\(base)-\(suffix)")
            suffix += 1
        }
        return candidate
    }

    private func loadSettings() throws -> ([String: Any], String) {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return ([:], "{}")
        }
        let data = try Data(contentsOf: settingsURL)
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            // Normalize every parse failure so the UI explains one condition:
            // the settings file is not valid JSON.
            throw HookError.malformedSettings
        }
        guard let object = parsed as? [String: Any] else {
            throw HookError.malformedSettings
        }
        let original = String(data: data, encoding: .utf8) ?? "{}"
        return (object, original)
    }

    private func serialize(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func commands(_ entry: [String: Any]) -> [String] {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return [] }
        return hooks.compactMap { $0["command"] as? String }
    }
}
