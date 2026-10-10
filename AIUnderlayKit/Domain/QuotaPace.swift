import Foundation

/// Computes the pace baseline — where the remaining quota *should* be if it were
/// being consumed at a constant rate. Used to draw the baseline marker.
public enum QuotaPace {
    /// The baseline remaining fraction for a window, or nil when it cannot be
    /// trusted (no pace from upstream and no credible period to derive one).
    ///
    /// Prefers an upstream `expectedUsedPercent`; otherwise derives from
    /// `resetAt` and `durationSeconds`. A window without a credible period
    /// returns nil — the marker is then hidden rather than guessed.
    public static func expectedRemaining(
        window: QuotaWindow,
        now: Date = Date()
    ) -> Double? {
        if let upstream = window.expectedRemainingFraction, upstream.isFinite {
            return clamp(upstream)
        }
        guard let resetAt = window.resetAt,
              let duration = window.durationSeconds,
              duration > 0
        else { return nil }

        let periodStart = resetAt.addingTimeInterval(-duration)
        let elapsed = now.timeIntervalSince(periodStart)
        let elapsedRatio = clamp(elapsed / duration)
        return 1 - elapsedRatio
    }

    /// Position of the baseline marker measured from the anchor, in points.
    ///
    /// The marker for the i-th window is projected through the same nested
    /// space as the fills: the product of every longer window's *actual*
    /// remaining fraction, times the selected window's expected remaining.
    /// `outerRemaining` is the actual remaining of every longer window
    /// (longest first); pass an empty array when the selected window is
    /// outermost. Returns nil when any factor is unknown.
    public static func markerLength(
        trackWidth: CGFloat,
        outerRemaining: [Double?],
        selectedExpectedRemaining: Double?
    ) -> CGFloat? {
        var product: Double = 1
        for fraction in outerRemaining {
            guard let fraction, fraction.isFinite else { return nil }
            product *= fraction
        }
        guard let expected = selectedExpectedRemaining, expected.isFinite else { return nil }
        product *= expected
        return trackWidth * CGFloat(product)
    }

    private static func clamp(_ value: Double) -> Double {
        Swift.max(0, Swift.min(1, value))
    }
}
