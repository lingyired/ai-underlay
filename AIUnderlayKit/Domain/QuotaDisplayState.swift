import Foundation

/// How a lane's quota data should be *drawn*. Pure, so the distinction between
/// "used up" and "unknown" is unit-tested without rendering.
///
/// `validZero` and `unknown` are deliberately different states: a known 0%
/// draws the opaque black used-up bed, while unknown draws the neutral glass
/// groove and never fakes an exhaustion.
public enum QuotaDisplayState: String, Sendable, Equatable {
    /// The outermost window has a usable, current value.
    case valid
    /// Values exist but are old; the lane renders dimmed.
    case stale
    /// No usable value: nil fraction, or an availability that means "we do not
    /// know" (unavailable/unauthenticated/unsupported/unknown).
    case unknown

    public var drawsExhaustedBed: Bool { self != .unknown }
    public var drawsFills: Bool { self != .unknown }

    /// Derived from the longest-first window list.
    ///
    /// Only the outermost *usable* window decides: if it is unknown, the whole
    /// nested chain is unknown (matching `NestedGauge`'s chain-break rule).
    public static func resolve(windows: [QuotaWindow]) -> QuotaDisplayState {
        guard let head = windows.first else { return .unknown }
        let usableAvailability: Set<DataAvailability> = [.valid, .stale]
        guard let fraction = head.remainingFraction, fraction.isFinite,
              usableAvailability.contains(head.availability)
        else { return .unknown }
        if windows.contains(where: { $0.availability == .stale }) { return .stale }
        return .valid
    }
}
