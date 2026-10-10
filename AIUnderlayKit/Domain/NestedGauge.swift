import Foundation

/// The recursive nested-length model: each window's visible length is the
/// previous (longer) window's visible length multiplied by its own remaining
/// fraction. A missing/unknown outer fraction breaks the chain — inner windows
/// after it are unknown rather than assumed full.
public enum NestedGauge {
    /// Computes visible lengths for windows ordered longest → shortest.
    ///
    /// - `remaining[i]` is the remaining fraction (0...1) of window i, or nil
    ///   when unknown.
    /// - A non-finite value (NaN, ±infinity) is treated as unknown.
    /// - Once a link is unknown, every shorter window is unknown (`nan`) too,
    ///   because its length depends on the broken outer length.
    /// - `trackWidth <= 0` yields all-zero lengths.
    public static func nestedLengths(trackWidth: CGFloat, remaining: [Double?]) -> [CGFloat] {
        guard trackWidth > 0 else { return remaining.map { _ in 0 } }

        var lengths: [CGFloat] = []
        lengths.reserveCapacity(remaining.count)
        var current = trackWidth
        var broken = false

        for fraction in remaining {
            if broken {
                lengths.append(.nan)
                continue
            }
            guard let fraction, fraction.isFinite else {
                broken = true
                lengths.append(.nan)
                continue
            }
            current *= CGFloat(fraction)
            lengths.append(current)
        }
        return lengths
    }
}
