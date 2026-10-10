import Foundation

/// Installs and removes Claude Code hooks in `~/.claude/settings.json`.
///
/// Safety rules, in order of importance:
/// 1. Never install without explicit user confirmation (this type only
///    *produces* a preview and *applies* an approved preview).
/// 2. Preserve the existing file: parse, add only our entries, back up first.
/// 3. On uninstall, remove only entries carrying our marker.
public struct HookSetupCoordinator {
    public static let settingsPath = ".claude/settings.json"

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

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        socketPath: String = AgentEventReceiver.defaultSocketURL().path,
        helperCommand: String = "aiunderlay-hook"
    ) {
        self.home = home
        self.socketPath = socketPath
        self.helperCommand = helperCommand
    }

    public var settingsURL: URL { home.appendingPathComponent(Self.settingsPath) }

    /// The hook entries we would add, each carrying the management marker so we
    /// can find them again on uninstall.
    public var managedCommands: [String] {
        let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                      "PermissionRequest", "Notification", "Stop", "SessionEnd"]
        return events.map { event in
            "\(helperCommand) --event \(event) --socket \(socketPath) \(AIUnderlayKit.hookMarker)"
        }
    }

    /// Produces a diff preview without writing anything.
    public func preview() throws -> ChangePreview {
        let (object, original) = try loadSettings()
        var updated = object
        var hooks = updated["hooks"] as? [String: Any] ?? [:]

        var added: [String] = []
        for (event, command) in zip(Self.eventNames, managedCommands) {
            var list = hooks[event] as? [[String: Any]] ?? []
            if !list.contains(where: { Self.commands($0).contains(where: { $0.contains(AIUnderlayKit.hookMarker) }) }) {
                list.append(["hooks": [["type": "command", "command": command]]])
                added.append(command)
            }
            hooks[event] = list
        }
        updated["hooks"] = hooks

        let after = try serialize(updated)
        return ChangePreview(before: original, after: after, addedCommands: added)
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
            list.removeAll { entry in
                Self.commands(entry).contains { $0.contains(AIUnderlayKit.hookMarker) }
            }
            if list.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = list }
        }
        if hooks.isEmpty { updated.removeValue(forKey: "hooks") } else { updated["hooks"] = hooks }

        try serialize(updated).write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    /// True when our hooks are currently installed.
    public func isInstalled() -> Bool {
        guard let (object, _) = try? loadSettings(),
              let hooks = object["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains { entry in
                Self.commands(entry).contains { $0.contains(AIUnderlayKit.hookMarker) }
            } ?? false
        }
    }

    static let eventNames = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                             "PermissionRequest", "Notification", "Stop", "SessionEnd"]

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
