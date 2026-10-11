import AppKit
import SwiftUI

/// A borderless, non-activating panel that can still become key.
///
/// `NSPopover` does not work reliably for an accessory (`LSUIElement`) app: its
/// window is only key while the app is active, and activating an accessory app
/// is asynchronous, so the popover appears but keystrokes are lost. A
/// `.nonactivatingPanel` whose `canBecomeKey` is true becomes key the instant it
/// is ordered front, without activating the app.
public final class MenuBarPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

/// Owns the dashboard panel and its positioning. Shows/hides below the status
/// item button and dismisses on outside click.
@MainActor
public final class DashboardPanelController {
    public static let panelWidth: CGFloat = 320

    private let panel: MenuBarPanel
    private let hosting: NSHostingController<AnyView>
    private var outsideMonitor: Any?
    private let anchor: () -> NSRect?

    /// - Parameter anchor: returns the status button's rect in screen
    ///   coordinates, or nil if unavailable.
    public init(anchor: @escaping () -> NSRect?, content: AnyView) {
        self.anchor = anchor
        self.hosting = NSHostingController(rootView: content)
        self.panel = MenuBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 320),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = hosting.view
        host.wantsLayer = true
        host.layer?.cornerRadius = 13
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        panel.contentView = host
    }

    public var isVisible: Bool { panel.isVisible }

    public func toggle() {
        isVisible ? hide() : show()
    }

    public func show() {
        guard let buttonRect = anchor() else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(buttonRect) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame

        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize.height
        let topLeft = PanelGeometry.clampedTopLeft(below: buttonRect, width: Self.panelWidth, visibleFrame: visibleFrame)
        let maxHeight = visibleFrame.map { PanelGeometry.maximumHeight(topLeft: topLeft, visibleFrame: $0) } ?? 600
        let height = PanelGeometry.clampedHeight(fitting, maximum: maxHeight)
        panel.setFrame(PanelGeometry.frame(topLeft: topLeft, width: Self.panelWidth, height: height), display: true)

        panel.makeKeyAndOrderFront(nil)
        startOutsideMonitor()
    }

    public func hide() {
        stopOutsideMonitor()
        panel.orderOut(nil)
    }

    private func startOutsideMonitor() {
        stopOutsideMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func stopOutsideMonitor() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
    }
}