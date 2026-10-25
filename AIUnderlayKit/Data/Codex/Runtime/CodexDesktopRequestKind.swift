import Foundation

/// Pending Desktop IPC requests the adapter surfaces. The full Pacer attention
/// domain is intentionally not ported: the parent maps these two cases onto its
/// own state, and only IDs, kinds and timing metadata leave this layer.
enum CodexDesktopRequestKind: String, Sendable {
    case input
    case approval
}
