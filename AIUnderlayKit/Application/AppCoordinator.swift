import AppKit

/// Top-level orchestrator. Owns the overlay controller, engine manager,
/// agent receiver, and the status item entry point. Fleshed out across
/// P0–P3; P0 only needs it to exist and start cleanly.
@MainActor
public final class AppCoordinator {
    public init() {}

    /// Called once from the app delegate on launch.
    public func start() {
        // Wired up in later tasks (overlay, engine, agent).
    }

    /// Called on termination to tear down windows and background work.
    public func stop() {
        // Wired up in later tasks.
    }
}
