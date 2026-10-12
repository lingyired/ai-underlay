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
/// 3. On uninstall, remove only entries carrying our marker.
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
    /// Existing entries we own are replaced in place when their command text has
    /// changed (e.g. the helper path, socket quoting, or a new `--provider`
    /// argument), so an upgrade migrates old entries instead of leaving them
    /// broken. Entries we do not own are never touched.
    public func preview() throws -> ChangePreview {
        let (object, original) = try loadSettings()
        var updated = object
        var hooks = updated["hooks"] as? [String: Any] ?? [:]

        var added: [String] = []
        for (event, command) in zip(provider.eventNames, managedCommands) {
            var list = hooks[event] as? [[String: Any]] ?? []
            if let index = list.firstIndex(where: { Self.isManaged($0) }) {
                // Refresh our own entry if its command text drifted.
                if !Self.commands(list[index]).contains(command) {
                    list[index] = ["hooks": [["type": "command", "command": command]]]
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

    /// Applies an approved preview, backing up the original first.
    public func install(confirmed: Bool) throws {
        guard confirmed else { throw HookError.notConfirmed }
        let preview = try preview()
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("bak.\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        try preview.after.write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    /// Removes only entries carrying our marker, preserving everything else.
    public func uninstall() throws {
        let (object, _) = try loadSettings()
        var updated = object
        guard var hooks = updated["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var list = value as? [[String: Any]] else { continue }
            list.removeAll { Self.isManaged($0) }
            if list.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = list }
        }
        if hooks.isEmpty { updated.removeValue(forKey: "hooks") } else { updated["hooks"] = hooks }

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

    // MARK: - Helpers

    private func loadSettings() throws -> ([String: Any], String) {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return ([:], "{}")
        }
        let data = try Data(contentsOf: settingsURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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
