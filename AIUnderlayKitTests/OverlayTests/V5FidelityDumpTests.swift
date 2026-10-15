import XCTest
import AppKit
@testable import AIUnderlayKit

/// Opt-in dump of the **curtain alone** (no quota bed, no glass tint, no
/// attention band) at the four canonical phases.
///
/// The V5 menubar-fidelity pass compares the native ray curtain against the
/// V5 lab's canvas `repaint()` output. Comparing full lanes would hide the
/// ray differences under the quota and tint layers, so this dump isolates the
/// layer that the phase-B work changes.
///
/// xcodebuild forwards environment to the test host only through the
/// `TEST_RUNNER_` prefix, so the dump command is:
///
///     TEST_RUNNER_V5_FIDELITY_DUMP=1 \
///     TEST_RUNNER_V5_FIDELITY_OUTPUT="$PWD/build/v5-menubar-fidelity/curtain" \
///     ./Scripts/test.sh -derivedDataPath build/DerivedData \
///         -only-testing:AIUnderlayKitTests/V5FidelityDumpTests
@MainActor
final class V5FidelityDumpTests: XCTestCase {
    func test_dumpCurtainFramesWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["V5_FIDELITY_DUMP"] == "1" else {
            throw XCTSkip("set V5_FIDELITY_DUMP=1 to write the curtain-only reference frames")
        }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["V5_FIDELITY_OUTPUT"]
            ?? "build/v5-menubar-fidelity/curtain", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        // Same fixture as the V5 lab defaults: an Aurora Glass lane, Codex
        // Running, the selected signal light, selected density.
        let tint = RGBAColor(hex: "#d9eeff") ?? RGBAColor(red: 0.85, green: 0.93, blue: 1)
        for height: CGFloat in [30, 34] {
            for scale: CGFloat in [1, 2] {
                for phase in [0.0, 0.25, 0.5, 0.75] {
                    for travels in [true, false] {
                        let image = try XCTUnwrap(SpectrumFrameRasteriser.frame(
                            width: 480, height: height, scale: scale, color: tint,
                            density: 1.0, intensity: SpectrumRhythm.motionIntensityDefault,
                            travels: travels, growsTowardRight: true, phase: phase
                        ))
                        let rep = NSBitmapImageRep(cgImage: image)
                        let name = String(format: "curtain-%dpt-%dx-p%02d%@.png",
                                          Int(height), Int(scale), Int(phase * 100),
                                          travels ? "" : "-parked")
                        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                            .write(to: output.appendingPathComponent(name))
                    }
                }
            }
        }
    }
}
