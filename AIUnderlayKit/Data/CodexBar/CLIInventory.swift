import Foundation

/// How usable a discovered CLI candidate is. Discovery is not the same as
/// usability: a binary can exist and be executable yet be the wrong version or
/// simply not logged in, and those are different problems with different fixes.
public enum Compatibility: Sendable, Equatable {
    /// `--version` succeeded and reported a CodexBar CLI.
    case compatible
    /// Found and executable, but the version probe failed or reported something else.
    case incompatible
    /// The CLI runs but has no usable credentials for the requested provider.
    case notLoggedIn
}

/// A discovered CLI executable with its probe result.
public struct CLICandidate: Sendable, Equatable {
    public let url: URL
    public let version: String?
    public let compatibility: Compatibility

    public init(url: URL, version: String?, compatibility: Compatibility) {
        self.url = url
        self.version = version
        self.compatibility = compatibility
    }
}

/// Locates CodexBar CLI executables. Path enumeration is pure and unit-tested;
/// validation touches the filesystem and runs `--version`.
public enum CLIInventory {
    /// Well-known locations in priority order, excluding the manual override.
    public static func wellKnownPaths(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin/codexbar"),
            URL(fileURLWithPath: "/usr/local/bin/codexbar"),
            URL(fileURLWithPath: "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"),
            home.appendingPathComponent("Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"),
            managedCLIPath(home: home),
        ]
    }

    /// App-managed install location (never `/usr/local/bin`, never needs sudo).
    public static func managedCLIPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/\(AIUnderlayKit.bundleIdentifier)/Engines/CodexBar/CodexBarCLI")
    }

    /// Ordered candidate paths: the manual override first, then well-known
    /// locations, then whatever a minimal controlled PATH resolves.
    public static func candidatePaths(
        manualPath: URL?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        pathEntries: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
    ) -> [URL] {
        var paths: [URL] = []
        if let manualPath { paths.append(manualPath) }
        paths.append(contentsOf: wellKnownPaths(home: home))
        for entry in pathEntries {
            paths.append(URL(fileURLWithPath: entry).appendingPathComponent("codexbar"))
        }
        return paths
    }

    /// Validates one candidate. A path that does not exist, is not executable,
    /// or resolves to a directory is skipped (returns nil). `which` is never
    /// used as the sole logic — the binary is always stat'd directly.
    public static func probe(url: URL, runner: (URL) -> String?) -> CLICandidate? {
        let resolved = url.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir),
              !isDir.boolValue,
              FileManager.default.isExecutableFile(atPath: resolved.path)
        else { return nil }

        guard let output = runner(resolved) else {
            return CLICandidate(url: resolved, version: nil, compatibility: .incompatible)
        }
        let version = parseVersion(from: output)
        let compatibility: Compatibility = version == nil ? .incompatible : .compatible
        return CLICandidate(url: resolved, version: version, compatibility: compatibility)
    }

    /// Discovers all usable candidates, de-duplicated by resolved path.
    public static func discover(
        manualPath: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runner: (URL) -> String?
    ) -> [CLICandidate] {
        var seen = Set<String>()
        var results: [CLICandidate] = []
        for path in candidatePaths(manualPath: manualPath, home: home) {
            guard let candidate = probe(url: path, runner: runner) else { continue }
            guard seen.insert(candidate.url.path).inserted else { continue }
            results.append(candidate)
        }
        return results
    }

    /// Extracts a version from `--version` output like "CodexBar 0.58.0".
    /// Returns nil when the output is not a CodexBar CLI.
    public static func parseVersion(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.localizedCaseInsensitiveContains("codexbar") else { return nil }
        let parts = trimmed.split(separator: " ")
        return parts.last.map(String.init)
    }
}