import Foundation

/// Whether a value can be trusted. Kept separate from the value itself so a
/// missing or failed read is never mistaken for a real 0%.
public enum DataAvailability: String, Codable, Sendable, Equatable {
    case valid
    case stale
    case unavailable
    case unauthenticated
    case unsupported
    case unknown
}

/// The kind of a quota window. This is derived from the *duration* the source
/// reports, never from field position, so `primary` is not assumed to be monthly.
public enum QuotaWindowKind: String, Codable, Sendable, Equatable {
    case session
    case weekly
    case monthly
    case custom
}

/// A single quota window (e.g. the 5-hour session window, or the weekly window).
public struct QuotaWindow: Identifiable, Codable, Sendable, Equatable {
    /// Provider-specific stable identifier.
    public let id: String
    public let label: String
    public let kind: QuotaWindowKind
    public let durationSeconds: TimeInterval?
    /// 0...1, or nil when unknown. **nil is never treated as 0.**
    public let remainingFraction: Double?
    public let resetAt: Date?
    /// Pace baseline (may be absent).
    public let expectedRemainingFraction: Double?
    public let updatedAt: Date?
    public let availability: DataAvailability

    public init(
        id: String,
        label: String,
        kind: QuotaWindowKind,
        durationSeconds: TimeInterval?,
        remainingFraction: Double?,
        resetAt: Date?,
        expectedRemainingFraction: Double?,
        updatedAt: Date?,
        availability: DataAvailability
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.remainingFraction = remainingFraction
        self.resetAt = resetAt
        self.expectedRemainingFraction = expectedRemainingFraction
        self.updatedAt = updatedAt
        self.availability = availability
    }

    /// Maps a window duration in minutes to a kind. 300 = 5h session,
    /// 10080 = 7d weekly. Unknown durations become `custom`.
    public static func kind(forWindowMinutes minutes: Int?) -> QuotaWindowKind {
        switch minutes {
        case 300: return .session
        case 10080: return .weekly
        case let m? where m >= 40000: return .monthly  // ~28+ days
        default: return .custom
        }
    }
}
