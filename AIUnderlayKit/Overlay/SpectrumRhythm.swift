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
    ///
    /// 0.70 Hz ≈ 1.4 s per cycle. The V5 lab's own cadence is roughly 1.4 s,
    /// and the previous 0.34 Hz (2.9 s) read as "almost static" in the menu
    /// bar: a first glance could not tell a running agent from an idle one.
    public static let floorFrequencyHz: Double = 0.70
    /// Fastest rhythm, reached at `referenceTPS` and above.
    public static let ceilingFrequencyHz: Double = 1.10
    /// Output speed that saturates the curve, in tokens/s.
    public static let referenceTPS: Double = 160
    /// The slowest rhythm the settings slider may pick. Below this the curtain
    /// stops reading as motion, so the floor is clamped rather than trusted.
    public static let minimumFloorFrequencyHz: Double = 0.15

    /// How much shape the ray curtain is allowed to carry. This is a *visual*
    /// setting: output speed changes the rhythm only, never the wave
    /// amplitude, so a fast model cannot blow the curtain out to white.
    public static let motionIntensityDefault: Double = 0.75
    public static let minimumMotionIntensity: Double = 0.30
    public static let maximumMotionIntensity: Double = 1.00

    /// The presets the settings page offers, slowest first. They are plain
    /// tempo values — there is still exactly one visual engine.
    public static let tempoPresets: [Double] = [0.50, floorFrequencyHz, 0.90, ceilingFrequencyHz]

    /// Clamps a user-picked floor; `nil`/non-finite means "use the built-in
    /// floor". Slower than `minimumFloorFrequencyHz` or faster than the ceiling
    /// is clamped, never rejected — a bad settings file must still animate.
    public static func clampedFloor(_ hz: Double?) -> Double {
        guard let hz, hz.isFinite else { return floorFrequencyHz }
        return min(max(hz, minimumFloorFrequencyHz), ceilingFrequencyHz)
    }

    /// Clamps a user-picked wave intensity. `nil`/non-finite means "use the
    /// built-in default"; anything outside the range is clamped, never
    /// rejected, so a bad settings file still animates.
    public static func clampedIntensity(_ intensity: Double?) -> Double {
        guard let intensity, intensity.isFinite else { return motionIntensityDefault }
        return min(max(intensity, minimumMotionIntensity), maximumMotionIntensity)
    }

    /// Multiplier applied to the wave's modulation terms, normalised so the
    /// default intensity reproduces the V5 lab's amplitude exactly.
    public static func waveAmplitudeScale(_ intensity: Double) -> Double {
        clampedIntensity(intensity) / motionIntensityDefault
    }

    /// Cycles per second for a measured output speed.
    ///
    /// `floorHz` is the user's baseline tempo. It stays the floor of the curve,
    /// so picking a faster baseline speeds up every speed reading at once —
    /// including the unmeasured case, which is the one actually on screen.
    public static func frequencyHz(
        outputTPS: Double?,
        floorHz: Double = SpectrumRhythm.floorFrequencyHz
    ) -> Double {
        let floor = clampedFloor(floorHz)
        let capped = min(max(outputTPS ?? 0, 0), referenceTPS)
        return floor + (ceilingFrequencyHz - floor) * (capped / referenceTPS).squareRoot()
    }

    /// Seconds for one full cycle.
    public static func cycleDuration(
        outputTPS: Double?,
        floorHz: Double = SpectrumRhythm.floorFrequencyHz
    ) -> Double {
        1 / frequencyHz(outputTPS: outputTPS, floorHz: floorHz)
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
