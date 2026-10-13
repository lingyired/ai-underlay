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
    private var sessionTimer: Timer?
    private var lastAgentSignature: String?
    /// Live agent sessions from CodexBar, keyed by provider (dominant state).
    public private(set) var agentSessions: [AgentSessionInfo] = []

    /// Providers shown in the overlay and dashboard.
    ///
    /// Deliberately fixed to the supported pair for now (see
    /// `AIUnderlayKit.supportedProviders`). We no longer follow the upstream
    /// CodexBar list: "enabled in CodexBar" is not the same as "supported here",
    /// and showing a provider we cannot render agent state for is misleading.
    public var providers: [String] { AIUnderlayKit.supportedProviders }

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

        settings.$settings
            .sink { [weak self] settings in
                guard let self else { return }
                if self.themes.selectedThemeId != settings.activeThemeId {
                    // setActive publishes `revision`, which renders for us.
                    self.themes.setActive(id: settings.activeThemeId)
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
                    + "session=\(event.sessionId) -> \(session.state.rawValue) (\(session.confidence.rawValue))")
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

    /// Polls `codexbar sessions` for live agent sessions. This works without any
/// hook installation and covers Codex and Claude Code.
    public func startSessionPolling() {
        sessionTimer?.invalidate()
        Task { @MainActor in await self.pollSessions() }
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollSessions() }
        }
    }

    private func pollSessions() async {
        if let engine = engineManager.activeEngine as? AgentSessionEngine,
           let sessions = try? await engine.listAgentSessions() {
            agentSessions = sessions
            dataRevision += 1
        }
        // The staleness rule needs a periodic tick, but rendering every tick
        // rebuilds the band layer tree and restarts running/pulse animations.
        let signature = agentSignature()
        if signature != lastAgentSignature {
            render()
        }
    }

    private func agentSignature() -> String {
        let settings = settings.settings
        guard settings.showAgentEffects else { return "effects-off" }
        if let fixture = settings.previewFixture {
            return "fixture:\(fixture)"
        }
        return providers.map { provider in
            "\(provider):\(dominantAgentState(for: provider)?.rawValue ?? "none")"
        }.joined(separator: "|")
    }

    /// The dominant agent state for a provider, or nil when there is no session.
    /// All of a provider's sessions are merged by priority, so one session
    /// waiting on the user outranks any number of others that are merely
    /// running — the light asks for attention, it does not report the latest
    /// event. Prefers hook-derived sessions (finer states); falls back to
    /// CodexBar's recency-based sessions (coarse: running/idle).
    public func dominantAgentState(for providerId: String) -> AgentState? {
        let now = Date()
        let hookSessions = reducer.allSessions().filter { $0.providerId == providerId }
        if !hookSessions.isEmpty {
            return AgentActivityAggregator.aggregate(hookSessions, now: now).dominant
        }
        let polled = agentSessions.filter { $0.provider == providerId }
        guard !polled.isEmpty else { return nil }
        return AgentActivityAggregator.aggregate(polled.map(\.asAgentSession), now: now).dominant
    }

    /// Session count summary for a provider, for the popup detail.
    public func agentSessionSummary(for providerId: String) -> (running: Int, idle: Int)? {
        let polled = agentSessions.filter { $0.provider == providerId }
        guard !polled.isEmpty else { return nil }
        let running = polled.filter { $0.agentState == .running }.count
        return (running, polled.count - running)
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
    private func fixtureAgentState(for key: String, provider: String) -> AgentState? {
        switch key {
        case "agentRunning": return .running
        case "agentWaiting": return .waitingApproval
        case "agentError": return .error
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
        scheduler?.start(providers: providers)

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
        lastAgentSignature = agentSignature()
        let theme = themes.activeTheme

        if s.previewFixture == nil {
            // Live mode. Before the first snapshot arrives we show empty tracks —
            // never fixture data, which could be mistaken for real usage.
            renderLive(s, theme: theme)
            return
        }

        let key = s.previewFixture!
        let windows = FixtureSnapshots.windows(for: key)
        // A theme may switch the baseline off; it never switches it on against
        // the user's own setting.
        let baseline = s.showBaseline && (theme?.global?.baselineEnabled ?? true)
            ? BaselineSpec(selectedWindowIndex: 0, expectedRemainingFraction: 0.5)
            : nil
        func presentation(_ providerId: String, base: ProviderPalette) -> GaugePresentation {
            GaugePresentation(
                windows: windows,
                palette: ThemeResolver.palette(theme: theme, providerId: providerId, base: base),
                baseline: baseline,
                agentState: s.showAgentEffects ? fixtureAgentState(for: key, provider: providerId) : nil,
                showAgentEffects: s.showAgentEffects,
                reduceMotion: s.reduceMotion,
                runningEffect: s.runningEffect,
                runningColor: Self.runningColor(s.runningEffectColor),
                effectTheme: ThemeResolver.effects(theme: theme, providerId: providerId)
            )
        }
        apply(left: presentation("codex", base: .codex),
              right: presentation("claude", base: .claude),
              settings: s)
    }

    private func renderLive(_ s: AppSettings, theme: ThemeDocument?) {
        func presentation(for provider: String, fallback: ProviderPalette) -> GaugePresentation? {
            guard let snapshot = liveSnapshots[provider] else { return nil }
            let windows = snapshot.windowsLongestFirst
            let base = ProviderPalette.for(providerId: provider)
            let palette = ThemeResolver.palette(theme: theme, providerId: provider, base: base)
            let baseline = s.showBaseline && (theme?.global?.baselineEnabled ?? true)
                ? baselineSpec(for: windows)
                : nil
            let agent = s.showAgentEffects ? dominantAgentState(for: provider) : nil
            return GaugePresentation(
                windows: windows,
                palette: palette == .neutral ? fallback : palette,
                baseline: baseline,
                agentState: agent,
                showAgentEffects: s.showAgentEffects,
                reduceMotion: s.reduceMotion,
                runningEffect: s.runningEffect,
                runningColor: Self.runningColor(s.runningEffectColor),
                effectTheme: ThemeResolver.effects(theme: theme, providerId: provider)
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

    /// Maps the configured running-effect color. `nil` means "follow the theme"
    /// — which, with no theme installed, is the built-in running color.
    static func runningColor(_ c: RunningEffectColor) -> RGBAColor? {
        guard c.isExplicit else { return nil }
        let rgb = c.rgba
        return RGBAColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 0.95)
    }
}
