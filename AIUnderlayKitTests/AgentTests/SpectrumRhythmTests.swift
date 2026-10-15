import XCTest
@testable import AIUnderlayKit

/// The Glass Spectrum tempo is pure math, so it is pinned here rather than
/// eyeballed in the menu bar. Speed changes rhythm only — never colour, never
/// brightness — and no measurement still means motion.
final class SpectrumRhythmTests: XCTestCase {

    func test_frequency_unknownSpeedUsesTheFloor() {
        // "No measurement" must still animate: an active agent keeps moving.
        XCTAssertEqual(SpectrumRhythm.frequencyHz(outputTPS: nil), SpectrumRhythm.floorFrequencyHz)
        XCTAssertEqual(SpectrumRhythm.frequencyHz(outputTPS: 0), SpectrumRhythm.floorFrequencyHz)
        XCTAssertEqual(SpectrumRhythm.frequencyHz(outputTPS: -5), SpectrumRhythm.floorFrequencyHz)
    }

    func test_frequency_saturatesAtTheReferenceSpeed() {
        XCTAssertEqual(SpectrumRhythm.frequencyHz(outputTPS: 160), SpectrumRhythm.ceilingFrequencyHz,
                       accuracy: 0.0001)
        XCTAssertEqual(SpectrumRhythm.frequencyHz(outputTPS: 10_000), SpectrumRhythm.ceilingFrequencyHz,
                       accuracy: 0.0001)
    }

    func test_frequency_isNonLinearAndMonotonic() {
        let slow = SpectrumRhythm.frequencyHz(outputTPS: 10)
        let mid = SpectrumRhythm.frequencyHz(outputTPS: 80)
        let fast = SpectrumRhythm.frequencyHz(outputTPS: 140)
        XCTAssertLessThan(slow, mid)
        XCTAssertLessThan(mid, fast)
        // A non-linear curve: the first 10→80 step must beat the 80→140 step.
        XCTAssertGreaterThan(mid - slow, fast - mid)
        // Never "50 tokens/s = 50 beats a second".
        XCTAssertLessThan(SpectrumRhythm.frequencyHz(outputTPS: 50), 1)
    }

    func test_cycleDuration_isTheInverseOfFrequency() {
        XCTAssertEqual(SpectrumRhythm.cycleDuration(outputTPS: nil),
                       1 / SpectrumRhythm.floorFrequencyHz, accuracy: 0.0001)
        XCTAssertEqual(SpectrumRhythm.cycleDuration(outputTPS: 160),
                       1 / SpectrumRhythm.ceilingFrequencyHz, accuracy: 0.0001)
    }

    func test_tempo_isNotSluggish() {
        // Speed is usually unmeasured, so the floor *is* the tempo on screen.
        // A first glance has to be able to tell Running from idle: the old
        // 0.34 Hz (2.9 s) read as "almost static".
        XCTAssertEqual(SpectrumRhythm.floorFrequencyHz, 0.70, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(SpectrumRhythm.cycleDuration(outputTPS: nil), 1.5)
        XCTAssertGreaterThanOrEqual(SpectrumRhythm.ceilingFrequencyHz, 1.0)
        // Still a rhythm, not a strobe.
        XCTAssertLessThanOrEqual(SpectrumRhythm.ceilingFrequencyHz, 1.5)
    }

    func test_tempoPresets_areOrderedAndInsideTheSliderRange() {
        XCTAssertEqual(SpectrumRhythm.tempoPresets, [0.50, 0.70, 0.90, 1.10])
        for hz in SpectrumRhythm.tempoPresets {
            XCTAssertGreaterThanOrEqual(hz, SpectrumRhythm.minimumFloorFrequencyHz)
            XCTAssertLessThanOrEqual(hz, SpectrumRhythm.ceilingFrequencyHz)
        }
        XCTAssertEqual(SpectrumRhythm.tempoPresets, SpectrumRhythm.tempoPresets.sorted())
    }

    func test_intensity_isClampedAndKeepsTheDefaultMeaning() {
        XCTAssertEqual(SpectrumRhythm.clampedIntensity(nil), SpectrumRhythm.motionIntensityDefault)
        XCTAssertEqual(SpectrumRhythm.clampedIntensity(.nan), SpectrumRhythm.motionIntensityDefault)
        XCTAssertEqual(SpectrumRhythm.clampedIntensity(0), SpectrumRhythm.minimumMotionIntensity)
        XCTAssertEqual(SpectrumRhythm.clampedIntensity(9), SpectrumRhythm.maximumMotionIntensity)
        XCTAssertEqual(SpectrumRhythm.clampedIntensity(0.5), 0.5, accuracy: 0.0001)
        // The default is the reference amplitude: 1.0 means "exactly V5".
        XCTAssertEqual(SpectrumRhythm.waveAmplitudeScale(SpectrumRhythm.motionIntensityDefault),
                       1.0, accuracy: 0.0001)
        XCTAssertLessThan(SpectrumRhythm.waveAmplitudeScale(0.30), 1)
        XCTAssertGreaterThan(SpectrumRhythm.waveAmplitudeScale(1.0), 1)
    }

    func test_userFloor_isTheBaselineTempo() {
        // Unmeasured speed must follow the user's baseline, which is the only
        // tempo the menu bar ever shows today.
        XCTAssertEqual(SpectrumRhythm.frequencyHz(outputTPS: nil, floorHz: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SpectrumRhythm.cycleDuration(outputTPS: nil, floorHz: 0.5), 2.0, accuracy: 0.0001)
        XCTAssertEqual(SpectrumRhythm.cycleDuration(outputTPS: nil, floorHz: 0.7), 1 / 0.7, accuracy: 0.0001)
    }

    func test_userFloor_staysTheFloorOfTheCurve() {
        // Raising the baseline must not push the ceiling past its own bound,
        // and a measured speed still has to read faster than the floor.
        XCTAssertEqual(SpectrumRhythm.frequencyHz(outputTPS: 160, floorHz: 0.5),
                       SpectrumRhythm.ceilingFrequencyHz, accuracy: 0.0001)
        XCTAssertGreaterThan(SpectrumRhythm.frequencyHz(outputTPS: 40, floorHz: 0.5), 0.5)
        XCTAssertLessThanOrEqual(SpectrumRhythm.frequencyHz(outputTPS: 40, floorHz: 1.1),
                                 SpectrumRhythm.ceilingFrequencyHz)
    }

    func test_userFloor_isClampedInsteadOfTrusted() {
        // A hand-edited settings file must not produce a strobe or a freeze.
        XCTAssertEqual(SpectrumRhythm.clampedFloor(nil), SpectrumRhythm.floorFrequencyHz)
        XCTAssertEqual(SpectrumRhythm.clampedFloor(.nan), SpectrumRhythm.floorFrequencyHz)
        XCTAssertEqual(SpectrumRhythm.clampedFloor(0), SpectrumRhythm.minimumFloorFrequencyHz)
        XCTAssertEqual(SpectrumRhythm.clampedFloor(-3), SpectrumRhythm.minimumFloorFrequencyHz)
        XCTAssertEqual(SpectrumRhythm.clampedFloor(99), SpectrumRhythm.ceilingFrequencyHz)
    }

    func test_waveValue_isDeterministicAndBounded() {
        for index in 0..<32 {
            for phase in [0.0, 0.23, 0.5, 0.87, 1.0] {
                let wave = SpectrumWaveModel.waveValue(
                    normalizedX: Double(index) / 32, rayIndex: index, phase: phase
                )
                XCTAssertGreaterThanOrEqual(wave, 0)
                XCTAssertLessThanOrEqual(wave, 1)
            }
            XCTAssertEqual(
                SpectrumWaveModel.waveValue(normalizedX: 0.5, rayIndex: index, phase: 0.31),
                SpectrumWaveModel.waveValue(normalizedX: 0.5, rayIndex: index, phase: 0.31)
            )
        }
    }

    func test_waveValue_differsBetweenNeighbouringRays_andPropagates() {
        let neighbours = (0..<8).map {
            SpectrumWaveModel.waveValue(normalizedX: Double($0) / 40, rayIndex: $0, phase: 0.3)
        }
        XCTAssertEqual(Set(neighbours.map { Int($0 * 1000) }).count, neighbours.count,
                       "no two neighbouring rays share the same wave sample")
        XCTAssertNotEqual(
            SpectrumWaveModel.waveValue(normalizedX: 0.5, rayIndex: 0, phase: 0.0),
            SpectrumWaveModel.waveValue(normalizedX: 0.5, rayIndex: 0, phase: 0.25),
            "phase must move the wave in time"
        )
    }
}
