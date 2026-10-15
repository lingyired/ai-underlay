import XCTest
import AppKit
@testable import AIUnderlayKit

/// Offline visual QA for the Glass Spectrum engine.
///
/// The always-on tests rasterise a real lane and sample **pixels** — structure
/// tests alone cannot see a lane that renders black-on-black. The PNG dump
/// writes the fixture matrix to `docs/preview/glass-spectrum/` when
/// `GLASS_PREVIEW_DUMP=1`, so a reviewer can look at exactly what the renderer
/// draws without launching the app.
@MainActor
final class GlassPreviewTests: XCTestCase {
    private let laneWidth: CGFloat = 320

    // MARK: - Composition

    private func lane(_ content: LaneContent, height: CGFloat) -> CALayer {
        let geometry = GaugeGeometry(
            trackRect: CGRect(x: 0, y: 0, width: laneWidth, height: height),
            fillBounds: CGRect(x: 0, y: 0, width: laneWidth, height: height),
            growsTowardRight: true
        )
        let spec = content.spec(geometry: geometry)
        let lane = CALayer()
        lane.frame = spec.geometry.trackRect
        lane.masksToBounds = true

        GlassQuotaRenderer.update(into: lane, spec: spec)
        let running = spec.signal?.isRunning == true
        GlassSpectrumRenderer.update(
            into: lane, spec: spec, running: running,
            cycle: SpectrumRhythm.cycleDuration(outputTPS: spec.signal?.observedOutputTPS),
            restart: true
        )
        AttentionLightRenderer.update(
            into: lane, spec: spec,
            attention: spec.signal?.attention ?? .none,
            restartSweep: true
        )
        LayerSlot.reconcileLane(lane)
        return lane
    }

    private func content(
        _ key: String,
        provider: String = "codex",
        signal: AgentSignals? = nil,
        reduceMotion: Bool = false,
        showsTravelingLight: Bool = true,
        showsAttentionSweep: Bool = true
    ) -> LaneContent {
        LaneContent(
            providerId: provider,
            windows: FixtureSnapshots.windows(for: key, providerId: provider),
            palette: ProviderPalette.for(providerId: provider),
            glass: .default(providerId: provider),
            signal: signal?.visualSignal,
            reduceMotion: reduceMotion,
            showsTravelingLight: showsTravelingLight,
            showsAttentionSweep: showsAttentionSweep
        )
    }

    // MARK: - Rasterisation

    private func rasterise(_ layer: CALayer, scale: CGFloat = 2) throws -> NSBitmapImageRep {
        let width = Int((layer.bounds.width * scale).rounded())
        let height = Int((layer.bounds.height * scale).rounded())
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = NSSize(width: layer.bounds.width, height: layer.bounds.height)

        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        layer.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Sample at a relative x and the vertical middle (where the bed gradient
    /// is a stable 0.94), far away from the 1pt machined edges.
    private func colour(_ rep: NSBitmapImageRep, atRelativeX x: Double) -> NSColor {
        let px = min(rep.pixelsWide - 1, max(0, Int(Double(rep.pixelsWide) * x)))
        let py = rep.pixelsHigh / 2
        return (rep.colorAt(x: px, y: py) ?? .clear).usingColorSpace(.deviceRGB) ?? .clear
    }

    private func distance(_ a: NSColor, _ b: NSColor) -> Double {
        let dr = Double(a.redComponent - b.redComponent)
        let dg = Double(a.greenComponent - b.greenComponent)
        let db = Double(a.blueComponent - b.blueComponent)
        let da = Double(a.alphaComponent - b.alphaComponent)
        return (dr * dr + dg * dg + db * db + da * da).squareRoot()
    }

    // MARK: - The pixels a structure test cannot see

    func test_exhaustedBedRasterisesBlack_andTheTintStopsAtTheOuterFill() throws {
        let running = AgentSignals(activeCount: 1)
        let teal = try rasterise(lane(content("glassV5", signal: running), height: 30))

        // The control lane is the same design with the glass tint switched
        // off, so every pixel difference *is* the tint.
        var untinted = content("glassV5", signal: running)
        untinted.glass.material.agentThemeStrength = 0
        let withoutTint = try rasterise(lane(untinted, height: 30))

        // 82% outer fill: x=0.95 is used-up quota. It must be the deep black
        // bed, not a tinted or coloured region.
        let usedUp = colour(teal, atRelativeX: 0.95)
        XCTAssertLessThan(Double(usedUp.redComponent), 0.06, "used-up quota must stay black")
        XCTAssertLessThan(Double(usedUp.greenComponent), 0.06)
        XCTAssertLessThan(Double(usedUp.blueComponent), 0.06)
        XCTAssertGreaterThan(Double(usedUp.alphaComponent), 0.85, "the bed must be genuinely opaque")

        // The glass tint is clipped to the fill: identical beyond it...
        let usedUpUntinted = colour(withoutTint, atRelativeX: 0.95)
        XCTAssertLessThan(distance(usedUp, usedUpUntinted), 0.01,
                          "the agent tint must never cover the used-up region")

        // ...and visible inside the outer fill: x=0.50 is inside 82% but
        // outside the inner 45.1% length, at the bloom's centre.
        let outerOnly = colour(teal, atRelativeX: 0.50)
        let outerOnlyUntinted = colour(withoutTint, atRelativeX: 0.50)
        XCTAssertGreaterThan(distance(outerOnly, outerOnlyUntinted), 0.02,
                             "the glass tint must be visible where it is allowed")

        // And a filled pixel reads brighter than the exhausted bed.
        let filled = colour(teal, atRelativeX: 0.30)
        XCTAssertGreaterThan(Double(filled.greenComponent), Double(usedUp.greenComponent) + 0.1)
    }

    func test_menuBarHeights30to34_allRasteriseTheSameLanguage() throws {
        for height: CGFloat in [30, 32, 34] {
            let rep = try rasterise(lane(content("glassV5", signal: AgentSignals(activeCount: 1)), height: height))
            XCTAssertEqual(rep.pixelsHigh, Int(height * 2))
            let usedUp = colour(rep, atRelativeX: 0.95)
            XCTAssertLessThan(Double(usedUp.redComponent), 0.06, "\(height)pt keeps the black bed")
            let filled = colour(rep, atRelativeX: 0.30)
            XCTAssertGreaterThan(Double(filled.blueComponent), 0.2, "\(height)pt keeps a visible fill")
        }
    }

    func test_unknownLaneRasterisesAsANeutralGroove_notBlackExhaustion() throws {
        let rep = try rasterise(lane(content("missing"), height: 30))
        let middle = colour(rep, atRelativeX: 0.5)
        XCTAssertLessThan(Double(middle.alphaComponent), 0.8,
                          "unknown data must not read as an opaque used-up bar")
    }

    // MARK: - PNG dump for human review

    func test_dumpPreviewPNGsWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["GLASS_PREVIEW_DUMP"] == "1" else {
            throw XCTSkip("set GLASS_PREVIEW_DUMP=1 to write docs/preview/glass-spectrum PNGs")
        }

        let cases: [(name: String, content: LaneContent)] = [
            ("codex-82-55-running", content("glassV5", signal: AgentSignals(activeCount: 1))),
            ("codex-82-55-idle", content("glassV5")),
            ("claude-67-36-running", content("glassV5", provider: "claude", signal: AgentSignals(activeCount: 1))),
            ("all-zero-exhausted", content("allZero")),
            ("unknown-missing", content("missing")),
            ("stale", content("stale")),
            ("running-waiting", content("glassV5", signal: AgentSignals(activeCount: 1, waitingApprovalCount: 1))),
            ("running-error", content("glassV5", signal: AgentSignals(activeCount: 1, errorCount: 1))),
            ("running-unread", content("glassV5", signal: AgentSignals(activeCount: 2, unreadCount: 1))),
            ("waiting-only", content("glassV5", signal: AgentSignals(waitingApprovalCount: 1))),
            ("error-only", content("glassV5", signal: AgentSignals(errorCount: 1))),
            ("unread-only", content("glassV5", signal: AgentSignals(unreadCount: 1))),
            ("reduce-motion-running-error",
             content("glassV5", signal: AgentSignals(activeCount: 1, errorCount: 1), reduceMotion: true)),
            ("running-no-traveling-light",
             content("glassV5", signal: AgentSignals(activeCount: 1), showsTravelingLight: false)),
            ("running-error-no-attention-sweep",
             content("glassV5", signal: AgentSignals(activeCount: 1, errorCount: 1), showsAttentionSweep: false)),
        ]

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OverlayTests
            .deletingLastPathComponent()   // AIUnderlayKitTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("docs/preview/glass-spectrum", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for item in cases {
            let rep = try rasterise(lane(item.content, height: 30))
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent("\(item.name).png"))
        }
        XCTAssertEqual(cases.count, 15)
    }
}
