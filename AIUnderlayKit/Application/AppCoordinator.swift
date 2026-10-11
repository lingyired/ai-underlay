import AppKit
import Combine

/// Top-level orchestrator: owns settings, the overlay controller, the quota
/// engine manager, the snapshot cache, the refresh scheduler, and the status
/// item. It is the only place that turns domain state into an
/// `OverlayPresentation`.
@MainActor
public final class AppCoordinator {
    /// The live coordinator, so the SwiftUI settings scene can reach it without
    /// threading an instance through the App struct.
    public private(set) static weak var shared: AppCoordinator?

    public let settings: SettingsStore
    public let overlay: MenuBarOverlayController
    public let engineManager: QuotaEngineManager
    public let cache: SnapshotCache

    /// Live snapshots by provider id (from real CLI fetches).
    public private(set) var liveSnapshots: [String: ProviderQuotaSnapshot] = [:]
    /// Last error per provider, for diagnostics.
    public private(set) var lastErrors: [String: String] = [:]

    private var statusItem: StatusItemController?
    private var scheduler: QuotaRefreshScheduler?
    private var cancellables = Set<AnyCancellable>()
    private var agentReceiver: AgentEventReceiver?
    private let reducer = AgentSessionReducer()

    /// Providers we try to display. Configurable in a later pass.
    public var providers: [String] = ["codex", "claude"]

    public init(
        settings: SettingsStore = SettingsStore(),
        overlay: MenuBarOverlayController = MenuBarOverlayController(),
        engineManager: QuotaEngineManager = QuotaEngineManager(),
        cache: SnapshotCache = SnapshotCache()
    ) {
        self.settings = settings
        self.overlay = overlay
        self.engineManager = engineManager
        self.cache = cache
        Self.shared = self
    }

    public func start() {
        overlay.startLifecycle()

        statusItem = StatusItemController(
            onOpenSettings: { SettingsOpener.open() },
            onToggleOverlay: { [weak self] in
                guard let self else { return }
                self.settings.update { $0.overlayEnabled.toggle() }
            }
        )
        statusItem?.setVisible(settings.settings.statusItemVisible)

        settings.$settings
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        startEngine()
        startAgentReceiver()
        render()

        // A second launch of the app asks us to open settings (see the
        // single-instance guard in the app delegate).
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.lingsmbp.aiunderlay.openSettings"),
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SettingsOpener.open() }
        }
    }

    /// Starts the Unix-socket receiver for agent hook events. Failure to bind is
    /// non-fatal: the overlay simply shows no agent activity.
    public func startAgentReceiver() {
        let receiver = AgentEventReceiver { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                _ = self.reducer.reduce(event)
                self.render()
            }
        }
        do {
            try receiver.start()
            agentReceiver = receiver
        } catch {
            agentReceiver = nil
        }
    }

    /// The dominant agent state for a provider, or nil when there is no session.
    public func dominantAgentState(for providerId: String) -> AgentState? {
        let sessions = reducer.allSessions().filter { $0.providerId == providerId }
        guard !sessions.isEmpty else { return nil }
        return AgentActivityAggregator.aggregate(sessions).dominant
    }

    public func stop() {
        scheduler?.stop()
        agentReceiver?.stop()
        overlay.stopLifecycle()
        overlay.hideAll()
        statusItem = nil
    }

    /// Agent state shown for the agent fixtures, so the effect channel can be
    /// previewed offline.
    private func fixtureAgentState(for key: String, provider: String) -> AgentState? {
        switch key {
        case "agentRunning": return .running
        case "agentWaiting": return .waitingApproval
        default: return nil
        }
    }

    public func applyStatusItemVisibility(_ visible: Bool) {
        statusItem?.setVisible(visible)
    }

    // MARK: - Engine

    /// Discovers the CLI and, if a compatible engine exists, begins periodic
    /// refreshes. Without an engine we simply keep rendering fixtures/cache.
    public func startEngine() {
        let override = settings.settings.proxyOverride
        engineManager.setProxyOverride(override.isEmpty ? nil : override)
        guard let engine = engineManager.activeEngine else { return }

        scheduler = QuotaRefreshScheduler(
            interval: 240,
            fetch: { provider in try await engine.fetch(provider: provider, account: nil) },
            onUpdate: { [weak self] snapshot in
                guard let self else { return }
                self.liveSnapshots[snapshot.providerId] = snapshot
                self.cache.store(snapshot)
                self.lastErrors[snapshot.providerId] = nil
                self.render()
            },
            onError: { [weak self] provider, error in
                guard let self else { return }
                self.lastErrors[provider] = CodexBarCLIClient.desensitize("\(error)")
                // Fall back to the last valid cached snapshot, marked stale.
                if let cached = self.cache.cached(id: "\(provider):default") {
                    self.liveSnapshots[provider] = cached
                }
                self.render()
            }
        )
        scheduler?.start(providers: providers)
    }

    public func refreshNow() {
        scheduler?.refreshNow()
    }

    /// Removes only the app-managed CLI binary, if present.
    public func uninstallManagedCLI() {
        let managed = CLIInventory.managedCLIPath()
        try? FileManager.default.removeItem(at: managed)
    }

    // MARK: - Rendering

    public func render() {
        let s = settings.settings

        if s.previewFixture == nil {
            // Live mode. Before the first snapshot arrives we show empty tracks —
            // never fixture data, which could be mistaken for real usage.
            renderLive(s)
            return
        }

        let key = s.previewFixture!
        let windows = FixtureSnapshots.windows(for: key)
        let baseline = s.showBaseline
            ? BaselineSpec(selectedWindowIndex: 0, expectedRemainingFraction: 0.5)
            : nil
        let left = GaugePresentation(windows: windows, palette: .codex, baseline: baseline,
                                     agentState: s.showAgentEffects ? fixtureAgentState(for: key, provider: "codex") : nil,
                                     showAgentEffects: s.showAgentEffects, reduceMotion: s.reduceMotion)
        let right = GaugePresentation(windows: windows, palette: .claude, baseline: baseline,
                                      agentState: s.showAgentEffects ? fixtureAgentState(for: key, provider: "claude") : nil,
                                      showAgentEffects: s.showAgentEffects, reduceMotion: s.reduceMotion)
        apply(left: left, right: right, settings: s)
    }

    private func renderLive(_ s: AppSettings) {
        func presentation(for provider: String, fallback: ProviderPalette) -> GaugePresentation? {
            guard let snapshot = liveSnapshots[provider] else { return nil }
            let windows = snapshot.windowsLongestFirst
            let palette = ProviderPalette.for(providerId: provider)
            let baseline = s.showBaseline ? baselineSpec(for: windows) : nil
            let agent = s.showAgentEffects ? dominantAgentState(for: provider) : nil
            return GaugePresentation(
                windows: windows,
                palette: palette == .neutral ? fallback : palette,
                baseline: baseline,
                agentState: agent,
                showAgentEffects: s.showAgentEffects,
                reduceMotion: s.reduceMotion
            )
        }

        let left = presentation(for: "codex", fallback: .codex)
        let right = presentation(for: "claude", fallback: .claude)
        apply(left: left, right: right, settings: s)
    }

    /// Binds the baseline to the outermost window with a known expected value.
    private func baselineSpec(for windows: [QuotaWindow]) -> BaselineSpec? {
        for (index, window) in windows.enumerated() {
            if let expected = window.expectedRemainingFraction {
                return BaselineSpec(selectedWindowIndex: index, expectedRemainingFraction: expected)
            }
        }
        return nil
    }

    private func apply(left: GaugePresentation?, right: GaugePresentation?, settings s: AppSettings) {
        let config = DisplayConfiguration(
            displayID: "primary",
            isEnabled: s.overlayEnabled,
            layout: s.layout,
            anchor: s.anchor,
            singleDirection: s.singleDirection,
            singleProviderId: "codex",
            assignments: [SideAssignment(side: .left, providerId: "codex"),
                          SideAssignment(side: .right, providerId: "claude")]
        )
        overlay.apply(OverlayPresentation(
            config: config,
            left: left,
            right: config.layout == .dual ? right : nil
        ))
    }
}