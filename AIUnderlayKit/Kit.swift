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
}
