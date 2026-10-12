import CoreGraphics

/// Pure math behind the running spectrum: how fast the wave cycles, and what
/// shape each bar takes. Deliberately free of AppKit so the look is testable
/// without rendering anything.
///
/// The frequency curve is the one agreed in the product consensus (spec §6.2):
/// speed changes the *rhythm*, never the height, and an active agent keeps
/// moving even when no speed has been measured. A missing measurement is not
/// "0 tokens/s", so `nil` uses the floor.
public enum SpectrumRhythm {
    /// Slowest rhythm. An active agent always moves, even with no speed data.
    public static let floorFrequencyHz: Double = 0.18
    /// Fastest rhythm, reached at `referenceTPS` and above.
    public static let ceilingFrequencyHz: Double = 0.62
    /// Output speed that saturates the curve, in tokens/s.
    public static let referenceTPS: Double = 160

    /// Bar geometry. Bars are drawn short and wide enough to read on a ~30pt
    /// menu bar strip at 2x.
    public static let barWidth: CGFloat = 4
    public static let barGap: CGFloat = 3

    /// Lowest a bar ever gets, as a fraction of the full strip height, so the
    /// spectrum always reads as a continuous row rather than flickering dots.
    public static let minimumHeightFactor: Double = 0.12

    /// Cycles per second for a measured output speed.
    public static func frequencyHz(outputTPS: Double?) -> Double {
        let capped = min(max(outputTPS ?? 0, 0), referenceTPS)
        return floorFrequencyHz
            + (ceilingFrequencyHz - floorFrequencyHz) * (capped / referenceTPS).squareRoot()
    }

    /// Seconds for one full up/down cycle.
    public static func cycleDuration(outputTPS: Double?) -> Double {
        1 / frequencyHz(outputTPS: outputTPS)
    }

    /// X offsets for each bar center, measured from the fill's leading edge and
    /// already mirrored when the fill grows toward the left. The run is centered
    /// inside `width` so the first and last bars are never half-cut.
    public static func barOffsets(width: CGFloat, growsTowardRight: Bool) -> [CGFloat] {
        guard width >= 1 else { return [] }
        let period = barWidth + barGap
        let count = max(1, Int(((width + barGap) / period).rounded(.down)))
        let runWidth = CGFloat(count) * period - barGap
        let leading = max(0, (width - runWidth) / 2)
        return (0..<count).map { index in
            let offset = leading + CGFloat(index) * period + barWidth / 2
            return growsTowardRight ? offset : width - offset
        }
    }

    /// One bar's wave: a phase that makes neighbouring bars travel, an integer
    /// speed so the loop is seamless, and an amplitude so peaks differ.
    public struct Wave: Equatable, Sendable {
        public var phase: Double
        public var speed: Int
        public var amplitude: Double
    }

    /// Deterministic per-bar parameters. The same index always yields the same
    /// shape, so the animation is reproducible (and reviewable) rather than
    /// random.
    public static func wave(index: Int) -> Wave {
        Wave(
            phase: 2 * .pi * 0.19 * Double(index),
            speed: hash01(index, salt: 1) < 0.5 ? 1 : 2,
            amplitude: 0.45 + 0.55 * hash01(index, salt: 2)
        )
    }

    /// Height factors (0…1) sampled over one full cycle.
    ///
    /// `steps` keyframes are handed to Core Animation; it interpolates between
    /// them, so eight samples per cycle read as a smooth, continuous wave.
    public static func keyframeValues(index: Int, steps: Int = 8) -> [Double] {
        guard steps > 0 else { return [] }
        let wave = wave(index: index)
        return (0..<steps).map { step in
            let t = Double(step) / Double(steps)
            let oscillation = 0.5 + 0.5 * sin(2 * .pi * Double(wave.speed) * t + wave.phase)
            return minimumHeightFactor
                + (1 - minimumHeightFactor) * wave.amplitude * pow(oscillation, 1.6)
        }
    }

    /// Stable 0…<1 hash used only to vary bar shapes. Not cryptographic.
    private static func hash01(_ value: Int, salt: UInt64) -> Double {
        var x = UInt64(truncatingIfNeeded: value) &+ salt &* 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 1_000_000) / 1_000_000
    }
}
