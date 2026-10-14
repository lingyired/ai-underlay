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
        XCTAssertLessThanOrEqual(SpectrumRhythm.cycleDuration(outputTPS: nil), 3.0)
        XCTAssertGreaterThanOrEqual(SpectrumRhythm.ceilingFrequencyHz, 1.0)
        // Still a rhythm, not a strobe.
        XCTAssertLessThanOrEqual(SpectrumRhythm.ceilingFrequencyHz, 1.5)
    }

    func test_wave_isDeterministicAndBounded() {
        for index in 0..<32 {
            let wave = SpectrumRhythm.wave(index: index)
            XCTAssertTrue(wave.speed >= 1 && wave.speed <= 2)
            XCTAssertGreaterThan(wave.amplitude, 0)
            XCTAssertLessThanOrEqual(wave.amplitude, 1)
            XCTAssertEqual(wave, SpectrumRhythm.wave(index: index))
        }
    }

    func test_wave_differsBetweenNeighbouringRays() {
        XCTAssertNotEqual(SpectrumRhythm.wave(index: 0), SpectrumRhythm.wave(index: 1))
    }
}
