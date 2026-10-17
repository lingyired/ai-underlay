import AppKit
import Combine
import SwiftUI

/// Top-level orchestrator: owns settings, the overlay controller, the quota
/// engine manager, the snapshot cache, the refresh scheduler, and the status
/// item. It is the only place that turns domain state into an
/// `OverlayPresentation`.
@MainActor
public final class AppCoordinator: ObservableObject {
    /// The live coordinator, so the SwiftUI settings scene can reach it without
    /// threading an instance through the App struct.
    public private(set) static weak var shared: AppCoordinator?

    /// Bumped whenever live data changes, so the dashboard popup re-renders.
    @Published public private(set) var dataRevision = 0

    public let settings: SettingsStore
    public let overlay: MenuBarOverlayController
    public let engineManager: QuotaEngineManager
    public let cache: SnapshotCache
    /// Themes on disk (appearance only). Changes hot-reload and re-render.
    public let themes: ThemeStore

    /// Live snapshots by provider id (from real CLI fetches).
    public private(set) var liveSnapshots: [String: ProviderQuotaSnapshot] = [:]
    /// Last error per provider, for diagnostics.
    public private(set) var lastErrors: [String: String] = [:]

    private var statusItem: StatusItemController?
    private var panel: DashboardPanelController?
    private var scheduler: QuotaRefreshScheduler?
    private var cancellables = Set<AnyCancellable>()
    private var agentReceiver: AgentEventReceiver?
    private let reducer = AgentSessionReducer()
    private let agentStateStore = AgentStateStore()
    private let codexLocalSessions = CodexLocalSessionReader()
    private var sessionTimer: Timer?
    private var lastAgentSignature: String?
    private var lastSessionSignature: String?
    /// Provider list the quota scheduler is currently running with, so a
    /// settings change only touches it when the switches actually changed.
    private var lastEnabledProviders: [String] = []
    /// Live agent sessions: the local rollout reading merged with CodexBar's.
    public private(set) var agentSessions: [AgentSessionInfo] = []

    /// Providers shown in the overlay and dashboard: the supported pair minus
    /// the ones switched off in the app. CodexBar's own enablement never
    /// overrides the user's choice here.
    public var providers: [String] {
        let enabled = settings.settings.enabledProviders
        return AIUnderlayKit.supportedProviders.filter { enabled.contains($0) }
    }

    /// The full provider catalog from the CLI, if an engine is available. Used
    /// only for metadata (display name, login status, upstream enablement) —
    /// never to decide which providers we support.
    public private(set) var availableProviders: [ProviderInfo] = []

    public init(
        settings: SettingsStore = SettingsStore(),
        overlay: MenuBarOverlayController = MenuBarOverlayController(),
        engineManager: QuotaEngineManager = QuotaEngineManager(),
        cache: SnapshotCache = SnapshotCache(),
        themes: ThemeStore? = nil
    ) {
        self.settings = settings
        self.overlay = overlay
        self.engineManager = engineManager
        self.cache = cache
        self.themes = themes ?? ThemeStore(activeId: settings.settings.activeThemeId)
        Self.shared = self
    }

    public func start() {
        overlay.startLifecycle()

        statusItem = StatusItemController(
            onTogglePopover: { [weak self] in self?.togglePopover() },
            onOpenSettings: { SettingsOpener.open() },
            onToggleOverlay: { [weak self] in
                guard let self else { return }
                self.settings.update { $0.overlayEnabled.toggle() }
            }
        )
        statusItem?.setVisible(settings.settings.statusItemVisible)

        // The dashboard popup, anchored to the status item.
        panel = DashboardPanelController(
            anchor: { [weak self] in self?.statusItem?.buttonScreenRect },
            content: AnyView(DashboardView(
                coordinator: self,
                store: settings,
                onRefresh: { [weak self] in self?.refreshNow() },
                onOpenSettings: { SettingsOpener.open() }
            ))
        )

        // `changes`, not `$settings`: `@Published` fires from `willSet`, so a
        // sink that re-read the store would render the *previous* value and
        // every toggle would visibly lag by one change.
        settings.changes
            .sink { [weak self] updated in
                guard let self else { return }
                self.syncProviderSelection()
                if self.themes.selectedThemeId != updated.activeThemeId {
                    // setActive publishes `revision`, which renders for us.
                    self.themes.setActive(id: updated.activeThemeId)
                } else {
                    self.render()
                }
            }
            .store(in: &cancellables)

        // A theme file edit (ours or an agent's) must repaint without a restart.
        themes.$revision
            .dropFirst()
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        startEngine()
        startAgentReceiver()
        startSessionPolling()
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
        // Restore sessions from the last run so a pending wait (which never
        // re-fires an event) survives a restart.
        if let snapshot = agentStateStore.load() {
            reducer.restore(snapshot)
            Log.write("agent state restored: \(reducer.allSessions().count) session(s)")
        }

        let receiver = AgentEventReceiver { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                let session = self.reducer.reduce(event)
                Log.write("agent event: provider=\(event.providerId) kind=\(event.kind.rawValue) "
                    + "session=\(event.sessionId) -> \(session.state.rawValue) (\(session.confidence.rawValue))"
                    + (session.pendingQuestion ? " pending-question" : ""))
                self.agentStateStore.save(self.reducer.snapshot())
                self.render()
            }
        }
        do {
            try receiver.start()
            agentReceiver = receiver
            Log.write("agent receiver listening on \(AgentEventReceiver.defaultSocketURL().path)")
        } catch {
            agentReceiver = nil
            Log.write("agent receiver failed to start: \(error)")
        }
    }

    /// Snapshots for the dashboard: live data normally, or fixtures when a
    /// preview fixture is selected (so the popup can be previewed offline too).
    public func dashboardSnapshots() -> [String: ProviderQuotaSnapshot] {
        if let key = settings.settings.previewFixture {
            let windows = FixtureSnapshots.windows(for: key)
            let now = Date()
            return Dictionary(uniqueKeysWithValues: providers.map { provider in
                (provider, ProviderQuotaSnapshot(
                    id: provider, providerId: provider, accountKey: nil,
                    sourceEngineId: "fixture", windows: windows,
                    fetchedAt: now, availability: .valid
                ))
            })
        }
        return liveSnapshots
    }

    /// Polls for live agent sessions: Codex straight from its local rollout
    /// files (complete, unlike `codexbar sessions`, which misses long-lived
    /// sessions living in old date directories), everything else from
    /// `codexbar sessions`. Works without any hook installation.
    public func startSessionPolling() {
        sessionTimer?.invalidate()
        Task { @MainActor in await self.pollSessions() }
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollSessions() }
        }
    }

    private func pollSessions() async {
        var polled: [AgentSessionInfo] = []
        if let engine = engineManager.activeEngine as? AgentSessionEngine,
           let sessions = try? await engine.listAgentSessions() {
            polled = sessions
        }
        let local = await codexLocalSessions.sessions()
        let merged = CodexSessionMerge.merged(local: local, polled: polled)
        if merged != agentSessions {
            agentSessions = merged
            dataRevision += 1
        }
        // Log only the shape (ids and states), not the timestamps that move on
        // every write, so a busy session does not flood the log.
        let sessionSignature = merged
            .map { "\($0.id.prefix(8)):\($0.state)" }
            .joined(separator: ",")
        if sessionSignature != lastSessionSignature {
            lastSessionSignature = sessionSignature
            let running = merged.filter { $0.agentState == .running }
                .map { String($0.id.prefix(8)) }.joined(separator: ",")
            Log.write("agent sessions: local=\(local.count) codexbar=\(polled.count) "
                + "merged=\(merged.count) running=\(running.isEmpty ? "-" : running)")
        }
        // The staleness rule needs a periodic tick, but rendering every tick
        // rebuilds the band layer tree and restarts running/pulse animations.
        let signature = agentSignature()
        if signature != lastAgentSignature {
            render()
        }
    }

    /// Short ids of the hook sessions the light currently counts as running.
    private func runningHookSessionIds() -> String {
        let now = Date()
        let ids = reducer.allSessions()
            .filter { AgentActivityAggregator.effectiveState($0, now: now) == .running }
            .map { String($0.id.prefix(8)) }
        return ids.isEmpty ? "-" : ids.joined(separator: ",")
    }

    private func agentSignature() -> String {
        let settings = settings.settings
        guard settings.showAgentEffects else { return "effects-off" }
        if let fixture = settings.previewFixture {
            return "fixture:\(fixture)"
        }
        return providers.map { provider in
            let signals = agentSignals(for: provider)
            // Every dimension is part of the signature: waiting + working must
            // repaint even when the highest-priority state did not change.
            let detail = signals.map {
                "a\($0.activeCount)w\($0.waitingCount)e\($0.errorCount)c\($0.completedCount)"
                    + "u\($0.unknownCount)n\($0.unreadCount)"
            } ?? "none"
            return "\(provider):\(detail)"
        }.joined(separator: "|")
    }

    /// Live signals for a provider, or nil when nothing is known about it.
    ///
    /// The dimensions stay separate: a provider whose session A waits for you
    /// while session B works must report both (§4.1). Prefers hook-derived
    /// sessions (finer states); falls back to CodexBar's recency-based sessions
    /// (coarse: running/idle).
    public func agentSignals(for providerId: String) -> AgentSignals? {
        let now = Date()
        let hookSessions = reducer.allSessions().filter { $0.providerId == providerId }
        let polled = agentSessions.filter { $0.provider == providerId }
        // The reconciliation rule lives in the domain so it is testable without
        // an engine: see `AgentSignals.reconciled(hook:polled:now:)`.
        return AgentSignals.reconciled(
            hook: hookSessions,
            polled: polled.map(\.asAgentSession),
            now: now
        )
    }

    /// The single state a caller that can only show one should use, e.g. the
    /// dashboard's one-line summary. Never used for the overlay.
    public func dominantAgentState(for providerId: String) -> AgentState? {
        agentSignals(for: providerId)?.primaryState
    }

    /// Session count summary for a provider, for the popup detail.
    ///
    /// The polled source is coarse — it only knows busy/idle — so a session
    /// that is waiting on the user is reported as running there. The hook
    /// evidence supplies that dimension; it is the only side that can see it.
    public func agentSessionSummary(for providerId: String) -> (running: Int, idle: Int, waiting: Int)? {
        let polled = agentSessions.filter { $0.provider == providerId }
        let hookSessions = reducer.allSessions().filter { $0.providerId == providerId }
        let waiting = AgentSignals.counting(hookSessions).waitingCount
        guard !polled.isEmpty || waiting > 0 else { return nil }
        let running = polled.filter { $0.agentState == .running }.count
        // A session the transcript could not be read for is neither running nor
        // idle: counting it as idle is how "I could not tell" becomes a claim
        // the user can check and find wrong.
        let idle = polled.filter { $0.agentState == .idle }.count
        return (running, idle, waiting)
    }

    public func stop() {
        scheduler?.stop()
        sessionTimer?.invalidate()
        agentReceiver?.stop()
        overlay.stopLifecycle()
        overlay.hideAll()
        statusItem = nil
    }

    /// Agent state shown for the agent fixtures, so the effect channel can be
    /// previewed offline.
    /// Offline preview signals, so every cell of the §5.2 matrix can be looked
    /// at without real providers.
    private func fixtureSignals(for key: String) -> AgentSignals? {
        switch key {
        case "agentRunning": return AgentSignals(activeCount: 1)
        case "agentWaiting": return AgentSignals(waitingApprovalCount: 1)
        case "agentError": return AgentSignals(errorCount: 1)
        case "agentRunningWaiting": return AgentSignals(activeCount: 2, waitingApprovalCount: 1)
        case "agentRunningError": return AgentSignals(activeCount: 1, errorCount: 1)
        // Unread fixtures exist only offline: production has no durable
        // completion ledger yet, and `completedCount` must never stand in.
        case "agentUnread": return AgentSignals(unreadCount: 1)
        case "agentRunningUnread": return AgentSignals(activeCount: 1, unreadCount: 1)
        case "agentAllSignals": return AgentSignals(activeCount: 1, waitingApprovalCount: 1,
                                                    errorCount: 1, unreadCount: 1)
        default: return nil
        }
    }

    public func applyStatusItemVisibility(_ visible: Bool) {
        statusItem?.setVisible(visible)
    }

    /// Toggles the dashboard popup below the status item.
    public func togglePopover() {
        panel?.toggle()
    }

    // MARK: - Engine

    /// Keeps the quota scheduler in step with the app-level provider switches:
    /// turning one on fetches it right away; turning one off only stops future
    /// fetches and leaves its last snapshot cached for an instant re-enable.
    private func syncProviderSelection() {
        let current = providers
        guard current != lastEnabledProviders else { return }
        lastEnabledProviders = current
        scheduler?.updateProviders(current)
        // The dashboard lists exactly these providers; let it rebuild.
        dataRevision += 1
    }

    /// Discovers the CLI and, if a compatible engine exists, begins periodic
    /// refreshes. Without an engine we simply keep rendering fixtures/cache.
    public func startEngine() {
        let currentProviders = providers
        lastEnabledProviders = currentProviders
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
                self.dataRevision += 1
                self.render()
            },
            onError: { [weak self] provider, error in
                guard let self else { return }
                self.lastErrors[provider] = CodexBarCLIClient.desensitize("\(error)")
                // Fall back to the last valid cached snapshot, marked stale.
                if let cached = self.cache.cached(id: "\(provider):default") {
                    self.liveSnapshots[provider] = cached
                }
                self.dataRevision += 1
                self.render()
            }
        )
        scheduler?.start(providers: currentProviders)

        Task { [weak self] in
            guard let self, let catalog = engine as? ProviderCatalogEngine else { return }
            if let list = try? await catalog.listProviders() {
                await MainActor.run {
                    self.availableProviders = list
                    Log.write("catalog: \(list.count) providers; enabled upstream: \(list.filter(\.enabledInCodexBar).map(\.id)); displaying: \(self.providers)")
                }
            }
        }
    }

    /// Fetches the provider catalog on demand and caches it.
    @discardableResult
    public func refreshProviderCatalog() async -> [ProviderInfo] {
        guard let catalog = engineManager.activeEngine as? ProviderCatalogEngine else { return [] }
        if let list = try? await catalog.listProviders() {
            availableProviders = list
            return list
        }
        return availableProviders
    }

    /// Path to the shared CodexBar config, for the UI to explain sharing.
    public static var codexBarConfigPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codexbar/config.json").path
    }

    /// Enables/disables a provider in CodexBar's own config. Modifies shared
    /// config — callers must confirm with the user first.
    public func setCodexBarProviderEnabled(_ provider: String, enabled: Bool) async throws {
        guard let catalog = engineManager.activeEngine as? ProviderCatalogEngine else { return }
        try await catalog.setProviderEnabled(provider, enabled: enabled)
        availableProviders = (try? await catalog.listProviders()) ?? availableProviders
    }

    /// Sets an API key for a provider that supports it (via stdin).
    public func setProviderAPIKey(_ provider: String, key: String) async throws {
        guard let catalog = engineManager.activeEngine as? ProviderCatalogEngine else { return }
        try await catalog.setAPIKey(provider: provider, key: key)
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
        let signature = agentSignature()
        if signature != lastAgentSignature {
            // One line per light change: "which session kept it green" is the
            // question every false-light report has come down to.
            Log.write("agent light: \(signature) running-hooks=\(runningHookSessionIds())")
        }
        lastAgentSignature = signature
        let theme = themes.activeTheme

        if let key = s.previewFixture {
            let composed = composeLanes(
                windowsFor: { FixtureSnapshots.windows(for: key, providerId: $0) },
                signalFor: { _ in fixtureSignals(for: key)?.visualSignal },
                settings: s,
                theme: theme
            )
            apply(plan: composed.plan, left: composed.left, right: composed.right, settings: s)
            return
        }

        // Live mode. Before the first snapshot arrives we show empty tracks —
        // never fixture data, which could be mistaken for real usage.
        let composed = composeLanes(
            windowsFor: { self.liveSnapshots[$0]?.windowsLongestFirst ?? [] },
            signalFor: { self.agentSignals(for: $0)?.visualSignal },
            settings: s,
            theme: theme
        )
        apply(plan: composed.plan, left: composed.left, right: composed.right, settings: s)
    }

    /// One lane's content. Windows arrive longest-first; an empty array is the
    /// neutral groove an offline provider shows. Agent activity must remain
    /// visible even when quota data is unavailable (logged out, stale source,
    /// or before the first fetch), so the signal is independent of the windows.
    ///
    /// A theme may switch the baseline off; it never switches it on against
    /// the user's own setting.
    private func laneContent(
        providerId: String,
        windows: [QuotaWindow],
        signal: ProviderVisualSignal?,
        settings s: AppSettings,
        theme: ThemeDocument?
    ) -> LaneContent {
        let glass = glassTheme(for: providerId, theme: theme, settings: s)
        return LaneContent(
            providerId: providerId,
            windows: windows,
            palette: glass.palette,
            baseline: s.showBaseline && glass.showsBaseline ? baselineSpec(for: windows) : nil,
            glass: glass,
            signal: s.showAgentEffects ? signal : nil,
            reduceMotion: s.reduceMotion,
            spectrumFloorHz: SpectrumRhythm.clampedFloor(s.motionFloorFrequencyHz),
            waveIntensity: SpectrumRhythm.clampedIntensity(s.motionIntensity),
            showsTravelingLight: s.showTravelingLight,
            showsAttentionSweep: s.showAttentionSweep
        )
    }

    /// Both lanes for the current settings, honouring the app-level provider
    /// switches and the single-provider dual-window split. Live and fixture
    /// rendering share this so the semantics cannot drift apart.
    private func composeLanes(
        windowsFor: (String) -> [QuotaWindow],
        signalFor: (String) -> ProviderVisualSignal?,
        settings s: AppSettings,
        theme: ThemeDocument?
    ) -> (plan: LanePlan, left: LaneContent?, right: LaneContent?) {
        let plan = LanePlanResolver.plan(
            enabledProviders: providers,
            supportedProviders: AIUnderlayKit.supportedProviders,
            layout: s.layout,
            split: s.dualWindowSplit
        )
        let targets = LanePlanResolver.lanes(for: plan, windowsForProvider: windowsFor)
        func lane(_ target: LanePlanResolver.LaneTarget?) -> LaneContent? {
            guard let target else { return nil }
            return laneContent(
                providerId: target.providerId,
                windows: target.windows,
                signal: signalFor(target.providerId),
                settings: s,
                theme: theme
            )
        }
        return (plan, lane(targets.left), lane(targets.right))
    }

    /// Resolves the full glass theme for one provider: built-in V5 defaults,
    /// then the active theme file, then the user's own appearance edits.
    private func glassTheme(for providerId: String, theme: ThemeDocument?, settings s: AppSettings) -> ResolvedGlassTheme {
        ThemeResolver.glassTheme(
            theme: theme,
            providerId: providerId,
            base: ProviderPalette.for(providerId: providerId),
            appearance: s.appearance
        )
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

    private func apply(plan: LanePlan, left: LaneContent?, right: LaneContent?, settings s: AppSettings) {
        let config = DisplayConfiguration(
            displayID: "primary",
            isEnabled: s.overlayEnabled,
            layout: s.layout,
            anchor: s.anchor,
            singleDirection: s.singleDirection,
            singleProviderId: s.layout == .single ? plan.singleProviderId : nil,
            assignments: [
                plan.leftProviderId.map { SideAssignment(side: .left, providerId: $0) },
                plan.rightProviderId.map { SideAssignment(side: .right, providerId: $0) },
            ].compactMap { $0 }
        )
        overlay.apply(OverlayPresentation(
            config: config,
            left: left,
            right: config.layout == .dual ? right : nil
        ))
    }
}
