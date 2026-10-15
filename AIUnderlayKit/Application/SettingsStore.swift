import Foundation
import Combine

/// Loads and saves `AppSettings` as JSON in Application Support, and publishes
/// changes to the UI. Non-secret only; credentials never live here.
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var settings: AppSettings

    private let fileURL: URL
    private let changesSubject = PassthroughSubject<AppSettings, Never>()
    /// A stable publisher instance, so `onReceive(store.changes)` does not
    /// resubscribe on every view update.
    private let changesPublisher: AnyPublisher<AppSettings, Never>

    /// Emits *after* a mutation has been applied and persisted.
    ///
    /// `@Published` publishes from `willSet`, so a subscriber that reacts to
    /// `$settings` and re-reads `settings` still sees the previous value. A
    /// renderer driven by that would draw one change behind and only catch up
    /// on the next unrelated refresh. Renderers subscribe here instead: the
    /// value is settled by the time this fires.
    public var changes: AnyPublisher<AppSettings, Never> {
        changesPublisher
    }

    public init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultURL()
        self.fileURL = url
        self.changesPublisher = changesSubject.eraseToAnyPublisher()
        self.settings = Self.load(from: url) ?? .default
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent(AIUnderlayKit.bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    /// Applies a mutation and persists.
    public func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        save()
        changesSubject.send(copy)
    }

    public func save() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persisting settings failing is not fatal; keep running in memory.
        }
    }

    static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}
