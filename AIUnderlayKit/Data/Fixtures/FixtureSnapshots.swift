import Foundation

/// Named mock snapshots for offline preview. These drive the real renderer —
/// there is no separate preview drawing path.
public enum FixtureSnapshots {
    public static let allKeys = [
        "full", "weekLow", "sessionLow", "allZero", "missing",
        "stale", "reset", "agentRunning", "agentWaiting", "agentError",
        "agentRunningWaiting", "agentRunningError", "notchless",
    ]

    /// Windows for a named fixture, longest-first.
    public static func windows(for key: String) -> [QuotaWindow] {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func window(
            _ id: String, _ label: String, _ kind: QuotaWindowKind, _ seconds: TimeInterval,
            _ remaining: Double?, expected: Double? = nil,
            resetIn: TimeInterval? = nil, availability: DataAvailability = .valid
        ) -> QuotaWindow {
            QuotaWindow(
                id: id, label: label, kind: kind, durationSeconds: seconds,
                remainingFraction: remaining,
                resetAt: resetIn.map { now.addingTimeInterval($0) },
                expectedRemainingFraction: expected,
                updatedAt: now, availability: availability
            )
        }

        switch key {
        case "full":
            return [window("w", "Weekly", .weekly, 604800, 1.0, expected: 0.6, resetIn: 604800),
                    window("s", "5h", .session, 18000, 1.0, expected: 0.4, resetIn: 18000)]
        case "weekLow":
            return [window("w", "Weekly", .weekly, 604800, 0.2, expected: 0.6, resetIn: 604800),
                    window("s", "5h", .session, 18000, 0.9, expected: 0.4, resetIn: 18000)]
        case "sessionLow":
            return [window("w", "Weekly", .weekly, 604800, 0.8, expected: 0.6, resetIn: 604800),
                    window("s", "5h", .session, 18000, 0.1, expected: 0.4, resetIn: 18000)]
        case "allZero":
            return [window("w", "Weekly", .weekly, 604800, 0.0, expected: 0.6, resetIn: 604800),
                    window("s", "5h", .session, 18000, 0.0, expected: 0.4, resetIn: 18000)]
        case "missing":
            // Outer unknown must break the chain, not assume full.
            return [window("w", "Weekly", .weekly, 604800, nil, availability: .unavailable),
                    window("s", "5h", .session, 18000, 0.5, expected: 0.4, resetIn: 18000)]
        case "stale":
            return [window("w", "Weekly", .weekly, 604800, 0.7, expected: 0.6, resetIn: 604800, availability: .stale),
                    window("s", "5h", .session, 18000, 0.5, expected: 0.4, resetIn: 18000, availability: .stale)]
        case "reset":
            return [window("w", "Weekly", .weekly, 604800, 0.99, expected: 0.2, resetIn: 604800),
                    window("s", "5h", .session, 18000, 0.95, expected: 0.2, resetIn: 18000)]
        case "agentRunning", "agentWaiting", "agentError", "agentRunningWaiting", "agentRunningError":
            return [window("w", "Weekly", .weekly, 604800, 0.6, expected: 0.5, resetIn: 604800),
                    window("s", "5h", .session, 18000, 0.6, expected: 0.4, resetIn: 18000)]
        case "notchless":
            return [window("w", "Weekly", .weekly, 604800, 0.5, expected: 0.5, resetIn: 604800),
                    window("s", "5h", .session, 18000, 0.5, expected: 0.4, resetIn: 18000)]
        default:
            return []
        }
    }

    /// A three-tier fixture including a real monthly layer, for the
    /// month → week → 5h nesting demo.
    public static func threeTier() -> [QuotaWindow] {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func w(_ id: String, _ label: String, _ kind: QuotaWindowKind, _ s: TimeInterval, _ r: Double) -> QuotaWindow {
            QuotaWindow(id: id, label: label, kind: kind, durationSeconds: s,
                        remainingFraction: r, resetAt: now.addingTimeInterval(s),
                        expectedRemainingFraction: 0.5, updatedAt: now, availability: .valid)
        }
        return [w("m", "Monthly", .monthly, 2_592_000, 0.8),
                w("w", "Weekly", .weekly, 604800, 0.6),
                w("s", "5h", .session, 18000, 0.25)]
    }
}
