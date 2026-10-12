import XCTest
@testable import AIUnderlayKit

/// The spectrum's rhythm and bar shapes are pure math, so they are pinned here
/// rather than eyeballed in the menu bar.
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

    func test_barOffsets_spacingIsEvenAndInsideTheFill() {
        let width: CGFloat = 200
        let offsets = SpectrumRhythm.barOffsets(width: width, growsTowardRight: true)
        XCTAssertGreaterThan(offsets.count, 10)
        let period = SpectrumRhythm.barWidth + SpectrumRhythm.barGap
        for (previous, next) in zip(offsets, offsets.dropFirst()) {
            XCTAssertEqual(next - previous, period, accuracy: 0.0001)
        }
        XCTAssertGreaterThanOrEqual(offsets.first!, SpectrumRhythm.barWidth / 2)
        XCTAssertLessThanOrEqual(offsets.last!, width - SpectrumRhythm.barWidth / 2)
    }

    func test_barOffsets_mirrorWhenTheBarGrowsTowardTheLeft() {
        let width: CGFloat = 200
        let right = SpectrumRhythm.barOffsets(width: width, growsTowardRight: true)
        let left = SpectrumRhythm.barOffsets(width: width, growsTowardRight: false)
        XCTAssertEqual(left.count, right.count)
        for (mirrored, forward) in zip(left, right) {
            XCTAssertEqual(mirrored, width - forward, accuracy: 0.0001)
        }
    }

    func test_barOffsets_tooNarrowForABarDrawNothing() {
        XCTAssertTrue(SpectrumRhythm.barOffsets(width: 0.5, growsTowardRight: true).isEmpty)
    }

    func test_keyframeValues_areBoundedCountedAndDeterministic() {
        let values = SpectrumRhythm.keyframeValues(index: 3, steps: 8)
        XCTAssertEqual(values.count, 8)
        for value in values {
            XCTAssertGreaterThanOrEqual(value, SpectrumRhythm.minimumHeightFactor)
            XCTAssertLessThanOrEqual(value, 1)
        }
        XCTAssertEqual(values, SpectrumRhythm.keyframeValues(index: 3, steps: 8))
    }

    func test_keyframeValues_differBetweenNeighbouringBars() {
        XCTAssertNotEqual(SpectrumRhythm.keyframeValues(index: 0),
                          SpectrumRhythm.keyframeValues(index: 1))
    }

    func test_wave_speedsAreWholeCyclesSoTheLoopIsSeamless() {
        for index in 0..<32 {
            let wave = SpectrumRhythm.wave(index: index)
            XCTAssertTrue(wave.speed >= 1 && wave.speed <= 2)
            XCTAssertGreaterThan(wave.amplitude, 0)
            XCTAssertLessThanOrEqual(wave.amplitude, 1)
        }
    }
}
