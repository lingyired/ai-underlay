import Foundation
import Combine

/// Loads and saves `AppSettings` as JSON in Application Support, and publishes
/// changes to the UI. Non-secret only; credentials never live here.
@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var settings: AppSettings
    /// Changes still apply in memory if saving fails, but the UI must not say
    /// they will survive a restart until a later save succeeds.
    @Published public private(set) var persistenceError: String?

    private let fileURL: URL
    private var needsRecoveryCopy = false
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
        do {
            let data = try Data(contentsOf: url)
            self.settings = try JSONDecoder().decode(AppSettings.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            self.settings = .default
        } catch {
            self.settings = .default
            self.needsRecoveryCopy = FileManager.default.fileExists(atPath: url.path)
            self.persistenceError = "无法读取已保存的设置，暂时使用默认值。再次保存前会备份原文件。"
        }
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
            if needsRecoveryCopy {
                let backup = fileURL.deletingLastPathComponent()
                    .appendingPathComponent("settings-recovery-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: fileURL, to: backup)
                needsRecoveryCopy = false
            }
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "设置已在本次运行中生效，但未能保存。请检查设置文件夹的可用空间和写入权限，然后重试。"
        }
    }

    static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}
