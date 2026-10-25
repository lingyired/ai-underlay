import Foundation

/// Pure derivations for the Agent settings page, kept out of the view so the
/// ownership rules stay testable.
public enum AgentSettingsLogic {
    /// Status for a provider whose hooks this app manages.
    ///
    /// Proven ownership decides between "not installed" and "needs update": a
    /// settings file that exists with only other tools' hooks (or unrelated
    /// configuration) must not read as if this app ever installed something
    /// there. `isInstalled` already implies ownership, so it wins first.
    public static func hookStatus(
        isInstalled: Bool,
        hasManagedEntries: Bool
    ) -> HookSettingsStatus {
        if isInstalled { return .installed }
        return hasManagedEntries ? .updateRequired : .notInstalled
    }
}
