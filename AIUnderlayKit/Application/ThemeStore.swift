import Combine
import Foundation

/// Owns the theme files on disk: loads them, validates them, watches the folder
/// for edits, and publishes the active theme.
///
/// Themes live in Application Support, outside the app bundle, so an app update
/// can never overwrite a theme the user or an agent wrote. A theme that fails to
/// parse is reported and skipped; if it was the active one, the previous good
/// version keeps rendering instead of the bar flashing to defaults.
@MainActor
public final class ThemeStore: ObservableObject {
    /// Everything the picker can offer: built-ins first, then files.
    @Published public private(set) var themes: [ThemeDocument] = ThemePresets.all
    /// Human-readable reason the last reload was not clean, if any.
    @Published public private(set) var lastError: String?
    /// Bumped whenever the resolved theme changes, so the coordinator re-renders.
    @Published public private(set) var revision = 0

    public let directoryURL: URL

    private let fileManager = FileManager.default
    /// The id the user selected, even if it does not resolve right now.
    public private(set) var selectedThemeId: String?
    private var activeDocument: ThemeDocument?
    /// `nonisolated` so `deinit` can cancel it without hopping actors.
    nonisolated(unsafe) private var watcher: DispatchSourceFileSystemObject?
    /// One watcher per theme file. A directory watcher alone only sees files
    /// appearing and disappearing — editing an existing file's contents is a
    /// change to *that file's* vnode, so it needs its own source.
    nonisolated(unsafe) private var fileWatchers: [DispatchSourceFileSystemObject] = []
    private var reloadTask: Task<Void, Never>?

    /// Debounce for file events: editors write in bursts, and a half-written
    /// file must not be parsed as a theme.
    public static let reloadDebounce: Duration = .milliseconds(300)

    public init(directory: URL? = nil, activeId: String? = nil, watch: Bool = true) {
        self.directoryURL = directory ?? Self.defaultDirectory()
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        self.selectedThemeId = activeId
        reload()
        if watch { startWatching() }
    }

    deinit {
        watcher?.cancel()
        fileWatchers.forEach { $0.cancel() }
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent(AIUnderlayKit.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Themes", isDirectory: true)
    }

    /// The theme to render with, or nil for the built-in look.
    public var activeTheme: ThemeDocument? { activeDocument }

    /// Chooses a theme by id. Unknown ids fall back to the built-in look and
    /// report why, rather than silently rendering something else.
    public func setActive(id: String?) {
        selectedThemeId = id
        applyActiveSelection(reportMissing: true)
        revision += 1
    }

    /// Re-reads the folder. Safe to call at any time.
    public func reload() {
        var loaded = ThemePresets.all
        var problems: [String] = []
        var seen = Set(loaded.map(\.id))

        let files = (try? fileManager.contentsOfDirectory(at: directoryURL,
                                                          includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        for file in files {
            let name = file.lastPathComponent
            do {
                let data = try Data(contentsOf: file)
                let document = try ThemeLoader.decode(data)
                if seen.contains(document.id) {
                    loaded.removeAll { $0.id == document.id }
                }
                seen.insert(document.id)
                loaded.append(document)
            } catch let failure as ThemeLoader.Failure {
                problems.append("\(name)：\(failure.message)")
            } catch {
                problems.append("\(name)：\(error)")
            }
        }

        themes = loaded
        lastError = problems.isEmpty ? nil : problems.joined(separator: "\n")
        applyActiveSelection(reportMissing: false)
        // Follow the files that exist now, including any just-added or renamed.
        watchFiles(files)
    }

    /// Resolves `activeId` against the loaded themes.
    ///
    /// - If it resolves, that document is rendered.
    /// - If it does not, and we still hold a previously good document for the
    ///   same id, keep rendering that one (a mid-edit file must not blank the bar).
    /// - Otherwise fall back to the built-in look and say so.
    private func applyActiveSelection(reportMissing: Bool) {
        guard let id = selectedThemeId else {
            activeDocument = nil
            return
        }
        if let match = themes.first(where: { $0.id == id }) {
            activeDocument = match
            return
        }
        if activeDocument?.id == id { return }   // keep the last good version
        activeDocument = nil
        if reportMissing {
            lastError = "找不到主题 \(id)，已回退到内置默认。"
        }
    }

    // MARK: - Watching

    private func startWatching() {
        stopWatching()
        watchDirectory()
        watchFiles(currentThemeFiles())
    }

    private func watchDirectory() {
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        watcher = source
        source.resume()
    }

    private func watchFiles(_ files: [URL]) {
        fileWatchers.forEach { $0.cancel() }
        fileWatchers = files.compactMap { file in
            let descriptor = open(file.path, O_EVTONLY)
            guard descriptor >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.scheduleReload() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        fileWatchers.forEach { $0.cancel() }
        fileWatchers = []
    }

    private func currentThemeFiles() -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "json" } ?? []
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.reloadDebounce)
            guard let self, !Task.isCancelled else { return }
            self.reload()
            self.revision += 1
        }
    }
}
