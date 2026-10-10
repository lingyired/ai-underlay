import Foundation

/// Caches the last valid snapshot per provider+account+window and marks it
/// stale past a threshold. A cached snapshot is never presented as live: when
/// the source is unreachable the snapshot is returned with `.stale`.
@MainActor
public final class SnapshotCache {
    public struct Entry {
        public var snapshot: ProviderQuotaSnapshot
        public var fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    public var staleThreshold: TimeInterval

    public init(staleThreshold: TimeInterval = 15 * 60) {
        self.staleThreshold = staleThreshold
    }

    public func store(_ snapshot: ProviderQuotaSnapshot, now: Date = Date()) {
        entries[snapshot.id] = Entry(snapshot: snapshot, fetchedAt: now)
    }

    /// Returns the cached snapshot marked `.stale` if it is past the threshold.
    public func cached(id: String, now: Date = Date()) -> ProviderQuotaSnapshot? {
        guard let entry = entries[id] else { return nil }
        guard now.timeIntervalSince(entry.fetchedAt) > staleThreshold else { return entry.snapshot }
        var stale = entry.snapshot
        stale = ProviderQuotaSnapshot(
            id: stale.id, providerId: stale.providerId, accountKey: stale.accountKey,
            sourceEngineId: stale.sourceEngineId, windows: stale.windows,
            fetchedAt: stale.fetchedAt, availability: .stale, diagnosticCode: "cached_stale"
        )
        return stale
    }

    public func lastValid(id: String) -> ProviderQuotaSnapshot? {
        entries[id]?.snapshot
    }

    public func clear() { entries.removeAll() }
}
