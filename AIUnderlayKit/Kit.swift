import Foundation

/// Central identity and version constants for the AI Underlay kit.
public enum AIUnderlayKit {
    /// Marketing version of the kit, surfaced in diagnostics.
    public static let version = "0.1.0"

    /// Bundle identifier used for app-managed directories (engines, sockets, configs).
    public static let bundleIdentifier = "com.lingsmbp.aiunderlay"

    /// Marker embedded into hook commands so the installer can identify
    /// exactly the entries it owns and remove only those on uninstall.
    public static let hookMarker = "--managed-by=\(bundleIdentifier)"

    /// The only providers this app supports for now. Codex and Claude Code have
    /// first-party lifecycle hooks and a shared CodexBar usage source, so their
    /// quota and agent state are both trustworthy. Everything else CodexBar
    /// knows about is deliberately out of scope until this pair is solid.
    public static let supportedProviders: [String] = ["codex", "claude"]

    /// Whether a provider id is one this app supports.
    public static func isSupported(provider: String) -> Bool {
        supportedProviders.contains(provider.lowercased())
    }

    /// Default stats endpoint for the landing-page download monitor: lingai.net's
    /// API service aggregates netdisk button clicks with GitHub release counts.
    public static let downloadMonitorDefaultURL = "https://lingai.net/api/dl/statustrio"

    /// The project key the download monitor polls with (the endpoint's path
    /// segment), used as the scheduler's single "provider" id.
    public static let downloadMonitorProject = "statustrio"

    /// Steady interval for the download monitor, in seconds. Counts move slowly
    /// (hours between clicks), so this is deliberately slower than the quota
    /// cadence and kind to the stats endpoint.
    public static let downloadMonitorInterval: TimeInterval = 300
}
