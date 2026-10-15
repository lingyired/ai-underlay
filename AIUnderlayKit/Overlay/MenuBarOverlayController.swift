import AppKit

/// Owns one band window per display and renders the glass lanes into them.
///
/// The controller is the only place that touches `NSScreen` and window
/// geometry; all placement math is delegated to the pure `GaugeLayout`, and
/// every lane is drawn by a persistent `GlassLayerHost` so updates diff
/// properties instead of destroying the layer tree.
@MainActor
public final class MenuBarOverlayController {
    private var windows: [String: MenuBarBandWindow] = [:]
    private var views: [String: NSView] = [:]
    private var laneHosts: [String: [GaugeSide: GlassLayerHost]] = [:]
    private var watchdogTimer: Timer?
    private var lastPresentation: OverlayPresentation?

    public init() {}

    // MARK: - Rendering

    /// Renders the presentation on every enabled display and keeps windows alive.
    public func apply(_ presentation: OverlayPresentation) {
        lastPresentation = presentation

        var seen = Set<String>()
        for screen in NSScreen.screens {
            let displayID = Self.displayID(for: screen)
            seen.insert(displayID)

            // Primary display uses the live config; other displays render the
            // same content until per-display configs are surfaced in the UI.
            guard presentation.config.isEnabled else {
                windows[displayID]?.orderOut(nil)
                continue
            }
            render(screen: screen, displayID: displayID, presentation: presentation)
        }

        // Tear down windows for displays that went away.
        for (id, window) in windows where !seen.contains(id) {
            window.orderOut(nil)
            windows.removeValue(forKey: id)
            views.removeValue(forKey: id)
            laneHosts[id]?.values.forEach { $0.teardown() }
            laneHosts.removeValue(forKey: id)
        }
    }

    private func render(screen: NSScreen, displayID: String, presentation: OverlayPresentation) {
        let window = windows[displayID] ?? {
            let created = MenuBarBandWindow()
            windows[displayID] = created
            return created
        }()

        let menuBarHeight = Self.menuBarHeight(for: screen)
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarHeight,
            width: screen.frame.width,
            height: menuBarHeight
        )
        window.setFrame(frame, display: false)

        let view = views[displayID] ?? {
            let created = NSView(frame: .zero)
            created.wantsLayer = true
            window.contentView = created
            views[displayID] = created
            return created
        }()
        view.frame = NSRect(origin: .zero, size: frame.size)

        let notch = MenuBarGeometry.notchEdges(for: screen)
        let placed = GaugeLayout.layout(
            mode: presentation.config.layout,
            anchor: presentation.config.anchor,
            singleDirection: presentation.config.singleDirection,
            screenFrame: CGRect(origin: .zero, size: frame.size),
            menuBarHeight: menuBarHeight,
            notchEdges: notch
        )

        var hosts = laneHosts[displayID] ?? [:]
        var seenSides = Set<GaugeSide>()
        for gauge in placed {
            seenSides.insert(gauge.side)
            let side: LaneContent?
            switch (presentation.config.layout, gauge.side) {
            case (.single, _): side = presentation.left
            case (.dual, .left): side = presentation.left
            case (.dual, .right): side = presentation.right
            }
            // Always draw the lane so an empty/offline side shows the neutral
            // glass groove rather than nothing at all.
            let content = side ?? LaneContent.empty(
                providerId: "neutral",
                reduceMotion: presentation.left?.reduceMotion ?? false,
                spectrumFloorHz: presentation.left?.spectrumFloorHz
                    ?? SpectrumRhythm.floorFrequencyHz,
                showsTravelingLight: presentation.left?.showsTravelingLight ?? true,
                showsAttentionSweep: presentation.left?.showsAttentionSweep ?? true
            )
            let spec = content.spec(geometry: gauge.geometry)
            let host = hosts[gauge.side] ?? {
                let created = GlassLayerHost()
                view.layer?.addSublayer(created.root)
                hosts[gauge.side] = created
                return created
            }()
            host.root.contentsScale = screen.backingScaleFactor
            host.update(spec)
        }
        // Lanes that are no longer placed (e.g. after a layout change) stop.
        let staleSides = hosts.keys.filter { !seenSides.contains($0) }
        for side in staleSides {
            hosts[side]?.teardown()
            hosts.removeValue(forKey: side)
        }
        laneHosts[displayID] = hosts

        window.orderFrontRegardless()
    }

    /// Removes every band window (teardown, or disabled).
    public func hideAll() {
        for (_, window) in windows { window.orderOut(nil) }
        laneHosts.values.forEach { hosts in hosts.values.forEach { $0.teardown() } }
        windows.removeAll()
        views.removeAll()
        laneHosts.removeAll()
    }

    // MARK: - Watchdog & lifecycle

    /// Starts the 5s watchdog and screen/space/appearance observers.
    public func startLifecycle() {
        stopLifecycle()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reassert() }
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleEnvironmentChange),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(handleEnvironmentChange),
                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(handleEnvironmentChange),
                           name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    public func stopLifecycle() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleEnvironmentChange() {
        guard let presentation = lastPresentation else { return }
        apply(presentation)
    }

    /// Re-asserts band windows if the window server dropped any. Does nothing
    /// when counts match, so it never causes flicker.
    public func reassert() {
        let managed = windows.values.filter { $0.isVisible }.count
        guard BandWatchdog.needsReassert(managedBands: managed, onScreenBands: BandWatchdog.onScreenBandCount()) else {
            return
        }
        for window in windows.values { window.orderFrontRegardless() }
    }

    /// Number of band windows currently managed. Surfaced in diagnostics.
    public var managedBandCount: Int { windows.count }

    /// The persistent lane host for a display/side, for diagnostics and tests.
    public func laneHost(displayID: String, side: GaugeSide) -> GlassLayerHost? {
        laneHosts[displayID]?[side]
    }

    // MARK: - Static band (P0 debug helper, retained for diagnostics)

    public func showStaticBand() {
        let window = QuotaWindow(id: "w", label: "W", kind: .weekly, durationSeconds: 604800,
                                 remainingFraction: 0.6, resetAt: nil,
                                 expectedRemainingFraction: nil, updatedAt: nil,
                                 availability: .valid)
        let presentation = OverlayPresentation(
            config: DisplayConfiguration(displayID: "debug", layout: .single,
                                         singleDirection: .leadingToTrailing),
            left: LaneContent(
                providerId: "codex",
                windows: [window],
                palette: .codex,
                glass: .default(providerId: "codex")
            ),
            right: nil
        )
        apply(presentation)
    }

    // MARK: - Geometry helpers

    public static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        let primaryMaxY = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY
            ?? screen.frame.maxY
        let quartz = MenuBarGeometry.quartzFrame(for: screen.frame, primaryMaxY: primaryMaxY)
        return MenuBarGeometry.menuBarHeight(
            forQuartzFrame: quartz,
            menuBarWindowBounds: MenuBarGeometry.onScreenMenuBarBounds()
        ) ?? NSStatusBar.system.thickness
    }

    public static func displayID(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return "\(screen.frame.origin.x),\(screen.frame.origin.y)"
    }
}
