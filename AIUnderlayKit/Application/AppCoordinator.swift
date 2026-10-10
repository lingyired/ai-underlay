import AppKit
import Combine

/// Top-level orchestrator: owns the settings store, overlay controller, status
/// item, and (from P2/P3) the quota engine and agent receiver. It is the only
/// place that decides how domain state becomes an `OverlayPresentation`.
@MainActor
public final class AppCoordinator {
    /// The live coordinator, so the SwiftUI settings scene can reach it without
    /// threading an instance through the App struct.
    public private(set) static weak var shared: AppCoordinator?

    public let settings: SettingsStore
    public let overlay: MenuBarOverlayController

    private var statusItem: StatusItemController?
    private var cancellables = Set<AnyCancellable>()

    public init(settings: SettingsStore = SettingsStore(), overlay: MenuBarOverlayController = MenuBarOverlayController()) {
        self.settings = settings
        self.overlay = overlay
        Self.shared = self
    }

    public func start() {
        overlay.startLifecycle()

        statusItem = StatusItemController(
            onOpenSettings: { SettingsOpener.open() },
            onToggleOverlay: { [weak self] in
                guard let self else { return }
                self.settings.update { $0.previewFixture = $0.previewFixture == nil ? "weekLow" : nil }
            }
        )
        statusItem?.setVisible(settings.settings.statusItemVisible)

        // Re-render whenever settings change.
        settings.$settings
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        render()
    }

    public func stop() {
        overlay.stopLifecycle()
        overlay.hideAll()
        statusItem = nil
    }

    /// Shows or hides the status bar entry point.
    public func applyStatusItemVisibility(_ visible: Bool) {
        statusItem?.setVisible(visible)
    }

    /// Builds the presentation from current settings and applies it.
    /// In P1 this always uses fixture data; P2 replaces the fixture branch with
    /// live snapshots.
    public func render() {
        let s = settings.settings
        let key = s.previewFixture ?? "weekLow"
        let windows = FixtureSnapshots.windows(for: key)

        let baseline = s.showBaseline ? BaselineSpec(selectedWindowIndex: 0, expectedRemainingFraction: 0.5) : nil
        let left = GaugePresentation(windows: windows, palette: .codex, baseline: baseline)
        let right = GaugePresentation(windows: windows, palette: .claude, baseline: baseline)

        let config = DisplayConfiguration(
            displayID: "primary",
            isEnabled: true,
            layout: s.layout,
            anchor: s.anchor,
            singleDirection: s.singleDirection,
            singleProviderId: "codex",
            assignments: [SideAssignment(side: .left, providerId: "codex"),
                          SideAssignment(side: .right, providerId: "claude")]
        )

        overlay.apply(OverlayPresentation(
            config: config,
            left: config.layout == .single ? left : left,
            right: config.layout == .dual ? right : nil
        ))
    }
}