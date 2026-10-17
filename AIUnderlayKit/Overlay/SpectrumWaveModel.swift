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
    /// V5 caps the crest radius in *points*: `radius = min(w * 0.28, 205)`.
    /// Without the cap a 960 pt lane spreads its light over 269 pt, so the
    /// "local" crest stopped being local — and it dimmed as the lane grew,
    /// because the same energy was spread further. The cap restores the lab's
    /// picture: on wide lanes the crest keeps a constant physical width.
    public static let maximumFocusRadius: Double = 205

    /// The crest radius a lane actually uses, in points.
    public static func focusRadius(forWidth width: Double) -> Double {
        min(width * focusRadiusFraction, maximumFocusRadius)
    }

    /// The same radius as a fraction of the lane, for the normalised kernel.
    public static func focusSigmaFraction(forWidth width: Double) -> Double {
        guard width > 0 else { return focusSigmaFraction }
        return (focusRadius(forWidth: width) / width) * 0.56
    }

    /// The two waves travel in opposite directions and at different spatial
    /// frequencies, so neighbouring rays never move as one block.
    public static let waveASpatialCycles: Double = 2.05
    public static let waveBSpatialCycles: Double = 1.20
    /// Turns per loop. Both are integers so the frame sequence closes without
    /// a seam.
    ///
    /// The V5 lab runs wave A at `1.25` and wave B at `0.82` turns per cycle,
    /// which is *not* integer — its two waves drift across the lane at 0.61
    /// and 0.68 lane-widths per cycle (one right, one left). The earlier
    /// integer choice here (`1` and `2`) sent wave B at 1.67 lane-widths per
    /// cycle: 2.4× the lab, and the reason the curtain read as "too fast /
    /// flickering" rather than as a slow travelling wave. `1` and `1` with the
    /// lab's spatial frequencies gives drifts of 0.49 and 0.83 — a total
    /// relative drift of 1.32 against the lab's 1.29, the closest a
    /// single-loop-closing integer pair can get. Drift, not the raw turn
    /// count, is what the eye reads as wave speed.
    public static let waveATurnsPerLoop: Double = 1
    public static let waveBTurnsPerLoop: Double = 1
    public static let waveAMix: Double = 0.61
    public static let waveBMix: Double = 0.39
    /// Deterministic per-ray phase offsets — the reason a whole group is never
    /// in lockstep.
    public static let rayPhaseA: Double = 0.072
    public static let rayPhaseB: Double = 0.27

    /// Height budget: every ray keeps a visible base, the wave adds the rest.
    /// V5's Aurora numbers are `0.22 + 0.52·crest + 0.28·focused`.
    public static let baseHeightFraction: Double = 0.22
    public static let crestHeight: Double = 0.52
    public static let focusHeight: Double = 0.28
    public static let shortestHeightFraction: Double = 0.10
    public static let tallestHeightFraction: Double = 0.96

    /// Visibility budget: a dark ray stays readable but never becomes a fence.
    ///
    /// V5's Aurora base is `0.22`, and the curtain now carries it whole. An
    /// earlier revision held it at `0.17` (−0.05) to answer a "发光栅栏"
    /// reading, but the fence came from composite faults that no longer
    /// exist — the curtain then replaced the fill source-over (a grey veil
    /// instead of the lab's `screen`), the fill ramped down to a dark bottom
    /// stop, and the groove drew a black rim over the fill. Each of those is
    /// fixed, and the trimmed base only left every stripe dimmer than the
    /// lab: measured live it read as translucent grey over the menu-bar
    /// material. `0.22` restores the lab's stripe body while the ceiling
    /// below still keeps even full strength off pure white.
    public static let baseAlpha: Double = 0.22
    public static let crestAlpha: Double = 0.28
    public static let focusAlpha: Double = 0.42
    public static let alphaCeiling: Double = 0.94

    /// How far past each edge the travelling crest runs before it re-enters,
    /// as a fraction of the lane.
    ///
    /// Zero: the crest advances exactly **one lap per cycle** and re-enters
    /// through the same edge it left, because `focus` measures distance around
    /// the lane rather than across it — the light field is periodic in cursor
    /// position, so passing the edge is continuous, not a jump.
    ///
    /// V5 moves its cursor 0.78 lane-widths per cycle, ours now moves 1.00.
    /// The old value (`0.25`, i.e. 1.5 laps per cycle) was 1.9× the lab *and*
    /// it left the lane entirely at both ends: measured on the 24-frame
    /// sequence, the last step changed the picture 2.25× more than a normal
    /// step — a visible hitch once per cycle. A one-lap span removes that
    /// spike, halves the per-frame travel (0.042 vs 0.063 lane), and is the
    /// closest a loop-closing span can get to the lab's 0.78. Matching 0.78
    /// exactly would need a 4-cycle supercycle (4.4–5.8 fps at the frame
    /// budget), which reads as stepping rather than flowing.
    public static let travelLeadFraction: Double = 0
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
        intensity: Double,
        width: Double = 0
    ) -> SpectrumWaveSample {
        let wave = waveValue(normalizedX: normalizedX, rayIndex: rayIndex, phase: phase)
        let focus = focus(normalizedX: normalizedX, crestCenter: primaryCenter, width: width)
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
    ///
    /// `width` is the lane width in points and enables V5's `min(w·0.28, 205)`
    /// radius cap. Passing `0` keeps the un-capped fraction, which is what the
    /// pure-math tests use.
    public static func focus(normalizedX: Double, crestCenter: Double, width: Double = 0) -> Double {
        let distance = abs(normalizedX - crestCenter)
        let wrapped = min(distance, 1 - distance)
        let sigma = width > 0 ? focusSigmaFraction(forWidth: width) : focusSigmaFraction
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
