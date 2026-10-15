import Foundation

/// One ray's shape at one instant: how tall it stands, how visible it is and
/// how much of the travelling crest is sitting on top of it.
public struct SpectrumWaveSample: Equatable, Sendable {
    /// Fraction of the lane height, measured from the bottom edge.
    public var heightFraction: Double
    /// The ray's own visibility, 0…1. The bright crest raises it locally.
    public var alpha: Double
    /// Local crest influence, 0…1. Peaks sit where this is highest.
    public var crestInfluence: Double
}

/// One ray of the curtain: where it stands and which deterministic phase
/// offsets its wave carries.
public struct SpectrumRay: Equatable, Sendable {
    public var index: Int
    /// 0…1 across the lane.
    public var normalizedX: Double
}

/// The pure per-ray wave behind the Glass Spectrum.
///
/// The V5 lab animates a canvas: two sine waves with per-ray phase offsets, a
/// local `focused` kernel around the travelling cursor, and a shape whose
/// height *and* brightness follow the wave. This is the same math as plain
/// values, so offline phase frames and the live texture sequence can never
/// disagree, and a frozen frame can be asserted in a unit test.
///
/// Everything here is periodic over one phase turn (`phase` in turns), which
/// is what lets the live renderer loop a finite frame sequence seamlessly.
public enum SpectrumWaveModel {
    // MARK: - Shape constants (tuned against the V5 lab, not invented)

    /// The local crest kernel: `radius = 0.28 × lane`, `sigma = radius × 0.56`
    /// in V5's terms.
    public static let focusRadiusFraction: Double = 0.28
    public static let focusSigmaFraction: Double = focusRadiusFraction * 0.56

    /// The two waves travel in opposite directions and at different spatial
    /// frequencies, so neighbouring rays never move as one block.
    public static let waveASpatialCycles: Double = 2.05
    public static let waveBSpatialCycles: Double = 1.20
    /// Wave B runs twice per turn, wave A once; both are integers so the frame
    /// sequence closes without a seam.
    public static let waveATurnsPerLoop: Double = 1
    public static let waveBTurnsPerLoop: Double = 2
    public static let waveAMix: Double = 0.61
    public static let waveBMix: Double = 0.39
    /// Deterministic per-ray phase offsets — the reason a whole group is never
    /// in lockstep.
    public static let rayPhaseA: Double = 0.072
    public static let rayPhaseB: Double = 0.27

    /// Height budget: every ray keeps a visible base, the wave adds the rest.
    public static let baseHeightFraction: Double = 0.20
    public static let crestHeight: Double = 0.46
    public static let focusHeight: Double = 0.30
    public static let shortestHeightFraction: Double = 0.10
    public static let tallestHeightFraction: Double = 0.96

    /// Visibility budget: a dark ray stays readable but never becomes a fence.
    public static let baseAlpha: Double = 0.14
    public static let crestAlpha: Double = 0.28
    public static let focusAlpha: Double = 0.45
    public static let alphaCeiling: Double = 0.88

    /// How far past each edge the travelling crest runs before it re-enters,
    /// as a fraction of the lane. Wide enough that the light is fully off-lane
    /// at the loop seam.
    public static let travelLeadFraction: Double = 0.25
    /// V5's secondary reflection is weaker and narrower than the main crest.
    public static let secondaryWeight: Double = 0.29
    public static let secondaryRadiusFraction: Double = focusRadiusFraction * 0.66

    // MARK: - Rays

    /// The ray count for a lane: the V5 density model. Density is a texture
    /// property — never a layer count.
    public static func rayCount(width: Double, density: Double) -> Int {
        let clamped = min(max(density, 0), 1)
        let densityBoost = 0.55 + clamped * 1.25
        return max(24, Int((width / 8.5 * densityBoost).rounded()))
    }

    /// Every ray of the curtain, evenly spaced with half-step margins.
    public static func rays(width: Double, density: Double) -> [SpectrumRay] {
        guard width > 0 else { return [] }
        let count = rayCount(width: width, density: density)
        return (0..<count).map { index in
            SpectrumRay(index: index, normalizedX: (Double(index) + 0.5) / Double(count))
        }
    }

    // MARK: - Crest position

    /// Where the main crest sits at `phase` (in turns, 0…1 per loop).
    ///
    /// With the travelling light on, the crest crosses the whole lane and runs
    /// off both edges, so the loop closes with no jump; with it off, the crest
    /// parks at the lane centre while the waves keep propagating.
    public static func primaryCrestCenter(
        at phase: Double,
        travels: Bool,
        travelsTowardRight: Bool
    ) -> Double {
        guard travels else { return 0.5 }
        let lead = travelLeadFraction
        let span = 1 + 2 * lead
        let progress = wrappedPhase(phase)
        return travelsTowardRight
            ? -lead + span * progress
            : 1 + lead - span * progress
    }

    /// The weak secondary reflection: same lap, opposite direction.
    public static func secondaryCrestCenter(
        at phase: Double,
        travels: Bool,
        travelsTowardRight: Bool
    ) -> Double {
        guard travels else { return 0.5 }
        let lead = travelLeadFraction
        let span = 1 + 2 * lead
        let progress = wrappedPhase(phase)
        return travelsTowardRight
            ? 1 + lead - span * progress
            : -lead + span * progress
    }

    // MARK: - Sampling

    /// One ray's shape at one instant.
    ///
    /// `intensity` scales only the *modulation* (crest + focus): the base
    /// height and base visibility are fixed, so turning the strength up makes
    /// the wave more pronounced instead of washing the curtain to white.
    public static func sample(
        normalizedX: Double,
        rayIndex: Int,
        phase: Double,
        primaryCenter: Double,
        intensity: Double
    ) -> SpectrumWaveSample {
        let wave = waveValue(normalizedX: normalizedX, rayIndex: rayIndex, phase: phase)
        let focus = focus(normalizedX: normalizedX, crestCenter: primaryCenter)
        let scale = SpectrumRhythm.waveAmplitudeScale(intensity)

        let height = baseHeightFraction + scale * (crestHeight * wave + focusHeight * focus)
        let alpha = baseAlpha + scale * (crestAlpha * wave + focusAlpha * focus)
        return SpectrumWaveSample(
            heightFraction: min(max(height, shortestHeightFraction), tallestHeightFraction),
            alpha: min(max(alpha, baseAlpha), alphaCeiling),
            crestInfluence: focus
        )
    }

    /// The mixed travelling wave, 0…1. `phase` is in turns; the two spatial
    /// terms make the pattern run *across* the lane instead of pulsing in
    /// place, and the per-ray offsets keep neighbours out of lockstep.
    public static func waveValue(normalizedX: Double, rayIndex: Int, phase: Double) -> Double {
        let index = Double(rayIndex)
        let turn = wrappedPhase(phase)
        let a = 0.5 + 0.5 * sin(
            2 * .pi * (waveATurnsPerLoop * turn - waveASpatialCycles * normalizedX) + index * rayPhaseA
        )
        let b = 0.5 + 0.5 * sin(
            2 * .pi * (waveBTurnsPerLoop * turn + waveBSpatialCycles * normalizedX) + index * rayPhaseB
        )
        return waveAMix * a + waveBMix * b
    }

    /// The local crest kernel, 0…1. Distances wrap around the lane so the
    /// light re-entering one edge matches the light leaving the other.
    public static func focus(normalizedX: Double, crestCenter: Double) -> Double {
        let distance = abs(normalizedX - crestCenter)
        let wrapped = min(distance, 1 - distance)
        let sigma = focusSigmaFraction
        guard sigma > 0 else { return 0 }
        return exp(-pow(wrapped / sigma, 2))
    }

    /// Phase of frame `index` of `count`.
    ///
    /// Sampled half a step in, so the discrete frame sequence straddles the
    /// motion instead of lagging it by up to one whole step.
    public static func framePhase(index: Int, count: Int) -> Double {
        guard count > 0 else { return 0 }
        return (Double(index) + 0.5) / Double(count)
    }

    /// Positive fractional part: a phase may arrive from a wrapping animation.
    public static func wrappedPhase(_ phase: Double) -> Double {
        guard phase.isFinite else { return 0 }
        let wrapped = phase.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }
}
