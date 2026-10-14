import Foundation

/// The attention channels of a provider lane.
///
/// The priority is a code constant, never a theme field: `error > waiting >
/// unread > none`. Running is *not* part of this enum — a provider can be
/// working and waiting at the same time, so it is a separate boolean
/// dimension (see `ProviderVisualSignal`).
public enum AttentionKind: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case unread
    case waiting
    case error

    /// Higher wins. Fixed here so no theme or settings file can reorder it.
    public var priority: Int {
        switch self {
        case .none: return 0
        case .unread: return 1
        case .waiting: return 2
        case .error: return 3
        }
    }

    /// The highest-priority kind in a collection.
    public static func highest(_ kinds: some Sequence<AttentionKind>) -> AttentionKind {
        kinds.max { $0.priority < $1.priority } ?? .none
    }
}

/// What one provider is doing right now, reduced to exactly what the visual
/// engine needs. Running and attention are independent dimensions: a lane can
/// move *and* show an attention ribbon at the same time.
public struct ProviderVisualSignal: Codable, Sendable, Equatable {
    /// Something is running. The light field moves while this is true, even
    /// when no output speed has been measured.
    public var isRunning: Bool
    /// The highest-priority attention channel, already resolved.
    public var attention: AttentionKind
    /// Measured response output in tokens/s. `nil` means "not measured" and
    /// must fall back to the slowest steady rhythm — never a demo value.
    public var observedOutputTPS: Double?

    public init(isRunning: Bool = false, attention: AttentionKind = .none, observedOutputTPS: Double? = nil) {
        self.isRunning = isRunning
        self.attention = attention
        self.observedOutputTPS = observedOutputTPS
    }

    /// True when this signal asks for any visual at all.
    public var isIdle: Bool { !isRunning && attention == .none }
}
