import CoreGraphics

/// Pure math behind the Glass Spectrum tempo. Deliberately free of AppKit so
/// the rhythm is testable without rendering anything.
///
/// The frequency curve changes the *rhythm* only: never the colour, never the
/// brightness. An active agent always moves, so a missing speed measurement
/// (`nil`) uses the floor — there is no "0 tokens/s" guess and the V5 demo's
/// `simulatedSpeedPercent` is never consulted here.
public enum SpectrumRhythm {
    /// Slowest rhythm. An active agent always moves, even with no speed data —
    /// and since speed is usually unmeasured, this floor is the tempo the
    /// spectrum actually shows.
    public static let floorFrequencyHz: Double = 0.34
    /// Fastest rhythm, reached at `referenceTPS` and above.
    public static let ceilingFrequencyHz: Double = 1.10
    /// Output speed that saturates the curve, in tokens/s.
    public static let referenceTPS: Double = 160

    /// Cycles per second for a measured output speed.
    public static func frequencyHz(outputTPS: Double?) -> Double {
        let capped = min(max(outputTPS ?? 0, 0), referenceTPS)
        return floorFrequencyHz
            + (ceilingFrequencyHz - floorFrequencyHz) * (capped / referenceTPS).squareRoot()
    }

    /// Seconds for one full cycle.
    public static func cycleDuration(outputTPS: Double?) -> Double {
        1 / frequencyHz(outputTPS: outputTPS)
    }

    /// One ray group's wave parameters: a phase so neighbouring rays travel,
    /// an integer speed so the loop is seamless, and an amplitude so peaks
    /// differ.
    public struct Wave: Equatable, Sendable {
        public var phase: Double
        public var speed: Int
        public var amplitude: Double
    }

    /// Deterministic per-ray parameters. The same index always yields the same
    /// shape, so the texture is reproducible (and reviewable) rather than
    /// random.
    public static func wave(index: Int) -> Wave {
        Wave(
            phase: 2 * .pi * 0.19 * Double(index),
            speed: hash01(index, salt: 1) < 0.5 ? 1 : 2,
            amplitude: 0.45 + 0.55 * hash01(index, salt: 2)
        )
    }

    /// Stable 0…<1 hash used only to vary ray shapes. Not cryptographic.
    static func hash01(_ value: Int, salt: UInt64) -> Double {
        var x = UInt64(truncatingIfNeeded: value) &+ salt &* 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 1_000_000) / 1_000_000
    }
}
