import Foundation

/// Drives periodic quota refreshes. Deliberately slow (minutes, never seconds)
/// so the CLI is not hammered. Manual refresh is allowed at any time and is
/// de-duplicated so concurrent calls collapse into one in-flight fetch.
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

    /// Immediate refresh; collapses if one is already running.
    public func refreshNow() {
        Task { @MainActor in await refresh() }
    }

    private func refresh() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        for provider in providers {
            do {
                let snapshot = try await fetch(provider)
                onUpdate(snapshot)
            } catch {
                onError(provider, error)
            }
        }
    }
}
