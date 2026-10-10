import AppKit

/// What to draw for one provider on one side.
public struct GaugePresentation: Sendable {
    public var windows: [QuotaWindow]
    public var palette: ProviderPalette
    public var baseline: BaselineSpec?

    public init(windows: [QuotaWindow], palette: ProviderPalette, baseline: BaselineSpec? = nil) {
        self.windows = windows
        self.palette = palette
        self.baseline = baseline
    }
}

/// A full description of what the overlay should show right now.
public struct OverlayPresentation: Sendable {
    public var config: DisplayConfiguration
    public var left: GaugePresentation?
    public var right: GaugePresentation?

    public init(config: DisplayConfiguration, left: GaugePresentation?, right: GaugePresentation?) {
        self.config = config
        self.left = left
        self.right = right
    }
}

/// Owns one band window per display and renders the gauges into them.
///
/// The controller is the only place that touches `NSScreen` and window
/// geometry; all placement math is delegated to the pure `GaugeLayout`.
@MainActor
public final class MenuBarOverlayController {
    private var windows: [String: MenuBarBandWindow] = [:]
    private var hosts: [String: NSView] = [:]
    private var watchdogTimer: Timer?
    private let renderer: GaugeRendering
    private var lastPresentation: OverlayPresentation?

    public init(renderer: GaugeRendering = GaugeLayerRenderer()) {
        self.renderer = renderer
    }

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
            hosts.removeValue(forKey: id)
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

        let host = hosts[displayID] ?? {
            let view = NSView(frame: .zero)
            view.wantsLayer = true
            window.contentView = view
            hosts[displayID] = view
            return view
        }()
        host.frame = NSRect(origin: .zero, size: frame.size)

        let root = host.layer ?? CALayer()
        root.frame = CGRect(origin: .zero, size: frame.size)
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        let notch = MenuBarGeometry.notchEdges(for: screen)
        let placed = GaugeLayout.layout(
            mode: presentation.config.layout,
            anchor: presentation.config.anchor,
            singleDirection: presentation.config.singleDirection,
            screenFrame: CGRect(origin: .zero, size: frame.size),
            menuBarHeight: menuBarHeight,
            notchEdges: notch
        )

        for gauge in placed {
            let presentationSide: GaugePresentation?
            switch (presentation.config.layout, gauge.side) {
            case (.single, _): presentationSide = presentation.left
            case (.dual, .left): presentationSide = presentation.left
            case (.dual, .right): presentationSide = presentation.right
            }
            // Always draw the track so an empty/offline side shows the neutral
            // groove rather than nothing at all.
            let side = presentationSide ?? GaugePresentation(windows: [], palette: .neutral)
            let layer = renderer.render(
                windows: side.windows,
                geometry: gauge.geometry,
                palette: side.palette,
                baseline: side.baseline
            )
            root.addSublayer(layer)
        }

        host.layer = root
        window.orderFrontRegardless()
    }

    /// Removes every band window (teardown, or disabled).
    public func hideAll() {
        for (_, window) in windows { window.orderOut(nil) }
        windows.removeAll()
        hosts.removeAll()
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

    // MARK: - Static band (P0 debug helper, retained for diagnostics)

    public func showStaticBand() {
        let presentation = OverlayPresentation(
            config: DisplayConfiguration(displayID: "debug", layout: .single,
                                         singleDirection: .leadingToTrailing),
            left: GaugePresentation(
                windows: [QuotaWindow(id: "w", label: "W", kind: .weekly, durationSeconds: 604800,
                                      remainingFraction: 0.6, resetAt: nil,
                                      expectedRemainingFraction: nil, updatedAt: nil,
                                      availability: .valid)],
                palette: .codex
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
