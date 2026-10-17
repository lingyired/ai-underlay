import Foundation

/// Drives periodic quota refreshes. Deliberately slow (minutes, never seconds)
/// so the CLI is not hammered. Manual refresh is allowed at any time and is
/// de-duplicated so concurrent calls collapse into one in-flight fetch.
///
/// A failed fetch is retried sooner than the steady interval. The CLI reaches
/// the network on every call, so a transient timeout is normal — and with one
/// fixed 4-minute timer a single failure leaves every lane empty (or stale) for
/// the whole period, which reads as "the quota stopped working". The retry is
/// bounded so a genuinely broken provider still settles down.
@MainActor
public final class QuotaRefreshScheduler {
    public typealias Fetch = (String) async throws -> ProviderQuotaSnapshot

    private var timer: Timer?
    private var inFlight = false
    private var providers: [String] = []
    private let interval: TimeInterval
    private let fetch: Fetch
    private let onUpdate: (ProviderQuotaSnapshot) -> Void
    private let onError: (String, Error) -> Void

    /// Delay before retrying the providers that failed on the previous pass.
    public static let retryInterval: TimeInterval = 30
    /// Consecutive-failure count at which a provider falls back to the steady
    /// interval instead of the quick retry.
    public static let maximumAttempts = 3
    private var failures: [String: Int] = [:]

    public init(
        interval: TimeInterval = 240,
        fetch: @escaping Fetch,
        onUpdate: @escaping (ProviderQuotaSnapshot) -> Void,
        onError: @escaping (String, Error) -> Void
    ) {
        self.interval = interval
        self.fetch = fetch
        self.onUpdate = onUpdate
        self.onError = onError
    }

    public func start(providers: [String]) {
        self.providers = providers
        failures.removeAll()
        stop()
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
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
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        var retry = false
        for provider in providers {
            do {
                let snapshot = try await fetch(provider)
                failures[provider] = nil
                onUpdate(snapshot)
            } catch {
                let count = (failures[provider] ?? 0) + 1
                failures[provider] = count
                retry = retry || count < Self.maximumAttempts
                onError(provider, error)
            }
        }
        if retry { scheduleRetry() }
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
        guard timer?.isValid != true else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
}
