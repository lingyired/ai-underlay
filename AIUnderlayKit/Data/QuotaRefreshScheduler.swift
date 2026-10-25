import Foundation

/// Drives periodic refreshes for one source. Deliberately slow (minutes, never
/// seconds) so the CLI (or the stats endpoint) is not hammered. Manual refresh
/// is allowed at any time and is de-duplicated so concurrent calls collapse
/// into one in-flight fetch.
///
/// Generic over the snapshot type so every periodic source (quota, download
/// counts) shares the same retry/backoff behaviour instead of re-implementing
/// it per data type.
///
/// A failed fetch is retried sooner than the steady interval. The CLI reaches
/// the network on every call, so a transient timeout is normal — and with one
/// fixed 4-minute timer a single failure leaves every lane empty (or stale) for
/// the whole period, which reads as "the quota stopped working". The retry is
/// bounded so a genuinely broken provider still settles down.
@MainActor
public final class RefreshScheduler<Snapshot> {
    public typealias Fetch = (String) async throws -> Snapshot

    private var timer: Timer?
    private var inFlight = false
    private var generation = 0
    private var isStopped = true
    private var providers: [String] = []
    private let interval: TimeInterval
    private let fetch: Fetch
    private let onUpdate: (Snapshot) -> Void
    private let onError: (String, Error) -> Void
    private let onRefreshing: (Bool) -> Void

    /// Delay before retrying the providers that failed on the previous pass.
    /// Computed: a generic type cannot have static stored properties.
    public static var retryInterval: TimeInterval { 30 }
    /// Consecutive-failure count at which a provider falls back to the steady
    /// interval instead of the quick retry.
    public static var maximumAttempts: Int { 3 }
    private var failures: [String: Int] = [:]

    public init(
        interval: TimeInterval = 240,
        fetch: @escaping Fetch,
        onUpdate: @escaping (Snapshot) -> Void,
        onError: @escaping (String, Error) -> Void,
        onRefreshing: @escaping (Bool) -> Void = { _ in }
    ) {
        self.interval = interval
        self.fetch = fetch
        self.onUpdate = onUpdate
        self.onError = onError
        self.onRefreshing = onRefreshing
    }

    public func start(providers: [String]) {
        self.providers = providers
        failures.removeAll()
        stop()
        isStopped = false
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    public func stop() {
        generation += 1
        isStopped = true
        inFlight = false
        timer?.invalidate()
        timer = nil
        onRefreshing(false)
    }

    /// Swaps the fetched provider set after the app-level switches changed.
    /// Adding a provider fetches it on the next pass; removing one only stops
    /// future fetches and keeps its cached snapshot for an instant re-enable.
    public func updateProviders(_ providers: [String]) {
        guard providers != self.providers else { return }
        let added = !Set(providers).isSubset(of: Set(self.providers))
        self.providers = providers
        failures = failures.filter { providers.contains($0.key) }
        if added { refreshNow() }
    }

    /// Immediate refresh; collapses if one is already running.
    public func refreshNow() {
        Task { @MainActor in await refresh() }
    }

    private func refresh() async {
        guard !isStopped, !inFlight else { return }
        let currentGeneration = generation
        inFlight = true
        onRefreshing(true)
        defer {
            if generation == currentGeneration {
                inFlight = false
                onRefreshing(false)
            }
        }
        var retry = false
        for provider in providers {
            do {
                let snapshot = try await fetch(provider)
                guard !isStopped, generation == currentGeneration else { return }
                guard providers.contains(provider) else { continue }
                failures[provider] = nil
                onUpdate(snapshot)
            } catch {
                guard !isStopped, generation == currentGeneration else { return }
                guard providers.contains(provider) else { continue }
                let count = (failures[provider] ?? 0) + 1
                failures[provider] = count
                retry = retry || count < Self.maximumAttempts
                onError(provider, error)
            }
        }
        if retry, !isStopped { scheduleRetry() }
    }

    /// One-shot retry, replacing the pending periodic tick so the two cannot
    /// stack. It also stops a still-empty lane from waiting out the full
    /// interval because the network hiccuped once.
    private func scheduleRetry() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.retryThenResume() }
        }
    }

    private func retryThenResume() async {
        await refresh()
        guard !isStopped, timer?.isValid != true else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
}

/// The quota scheduler, kept as a named binding so existing call sites and
/// tests read unchanged.
public typealias QuotaRefreshScheduler = RefreshScheduler<ProviderQuotaSnapshot>
