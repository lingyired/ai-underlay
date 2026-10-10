import AppKit

/// Top-level orchestrator. Owns the overlay controller, engine manager,
/// agent receiver, and the status item entry point. Fleshed out across
/// P0–P3; P0 only needs it to exist and start cleanly.
@MainActor
public final class AppCoordinator {
    private let overlay = MenuBarOverlayController()

    public init() {}

    /// Called once from the app delegate on launch.
    public func start() {
        // P0: prove the band window renders behind the menu bar.
        overlay.showStaticBand()
        // Engine and agent wiring arrive in P2/P3.
    }

    /// Called on termination to tear down windows and background work.
    public func stop() {
        overlay.hideAll()
    }
}
