import Foundation

/// Chooses and holds the active quota engine. Discovery is separate from
/// selection so a non-compatible external CLI is reported as such rather than
/// silently replaced.
@MainActor
public final class QuotaEngineManager {
    public private(set) var candidates: [CLICandidate] = []
    public private(set) var activeEngine: (any QuotaEngine)?

    private let manualPath: URL?
    private let home: URL
    /// When set, overrides the standard search order entirely (used by tests).
    private let searchPaths: [URL]?
    /// Explicit proxy URL passed to the engine, if any.
    private var proxyOverride: String?

    public init(
        manualPath: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        searchPaths: [URL]? = nil,
        proxyOverride: String? = nil
    ) {
        self.manualPath = manualPath
        self.home = home
        self.searchPaths = searchPaths
        self.proxyOverride = proxyOverride
    }

    /// Updates the proxy override and re-resolves the active engine.
    public func setProxyOverride(_ value: String?) {
        proxyOverride = value
        refresh()
    }

    /// Re-runs discovery. The manual override is honoured first; otherwise the
    /// first compatible candidate wins. A candidate that exists but is
    /// incompatible is kept in `candidates` so the UI can offer a managed
    /// install instead of claiming "not installed".
    public func refresh(runner: @escaping @Sendable (URL) -> String? = QuotaEngineManager.defaultVersionRunner) {
        if let searchPaths {
            candidates = CLIInventory.discover(paths: searchPaths, runner: runner)
        } else {
            candidates = CLIInventory.discover(manualPath: manualPath, home: home, runner: runner)
        }
        if let best = candidates.first(where: { $0.compatibility == .compatible }) {
            activeEngine = CodexBarEngine(
                executableURL: best.url,
                version: best.version,
                proxyOverride: proxyOverride
            )
        } else {
            activeEngine = nil
        }
    }

    /// Whether any candidate exists but none is compatible (drives the
    /// "found but incompatible" UI state).
    public var hasIncompatibleOnly: Bool {
        !candidates.isEmpty && candidates.allSatisfy { $0.compatibility != .compatible }
    }

    public nonisolated static func defaultVersionRunner(_ url: URL) -> String? {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
