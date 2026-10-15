import XCTest
import AppKit
@testable import AIUnderlayKit

/// Error / Waiting / Unread are one structure: top line, bottom ribbon, wash,
/// and a single-sided sweep whose tempo and colour differ per kind.
@MainActor
final class AttentionLightRendererTests: XCTestCase {
    private let geometry = GaugeGeometry(
        trackRect: CGRect(x: 0, y: 0, width: 1000, height: 30),
        fillBounds: CGRect(x: 0, y: 0, width: 1000, height: 30),
        growsTowardRight: true
    )

    private func spec(
        glass: ResolvedGlassTheme = .default(providerId: "codex"),
        reduceMotion: Bool = false
    ) -> LaneRenderSpec {
        LaneRenderSpec(
            providerId: "codex", geometry: geometry, windows: [], palette: .codex,
            glass: glass, signal: nil, reduceMotion: reduceMotion
        )
    }

    private func root(of lane: CALayer) -> CALayer? {
        lane.sublayers?.first { $0.name == "attention" }
    }

    // MARK: - One structure for every kind

    func test_allThreeKindsUseTheSameStructure() throws {
        for kind in [AttentionKind.error, .waiting, .unread] {
            let lane = AttentionLightRenderer.render(spec(), attention: kind, restartSweep: true)
            let attention = try XCTUnwrap(root(of: lane))
            let names = (attention.sublayers ?? []).compactMap(\.name)
            XCTAssertEqual(names, ["wash", "glow", "ribbon", "topLine"], "\(kind)")
            let ribbon = try XCTUnwrap(attention.sublayers?.first { $0.name == "ribbon" })
            XCTAssertEqual(ribbon.sublayers?.compactMap(\.name), ["glint"], "\(kind)")
        }
    }

    func test_topLineIsAboutTwoPointsAndRibbonAboutFive() throws {
        let lane = AttentionLightRenderer.render(spec(), attention: .waiting, restartSweep: true)
        let attention = try XCTUnwrap(root(of: lane))
        let top = try XCTUnwrap(attention.sublayers?.first { $0.name == "topLine" })
        let ribbon = try XCTUnwrap(attention.sublayers?.first { $0.name == "ribbon" })
        XCTAssertEqual(top.frame.height, 2, accuracy: 0.001)
        XCTAssertEqual(top.frame.maxY, 30, accuracy: 0.001, "the line hugs the top of the band")
        XCTAssertEqual(ribbon.frame.height, 5, accuracy: 0.001)
        XCTAssertEqual(ribbon.frame.minY, 0, accuracy: 0.001)
    }

    /// The ribbon hugs the bottom edge: transparent at its own top, alert
    /// colour on the bottom of the bar (V5: `linearGradient(180deg,
    /// transparent, alert)`). A bright *top* edge would read as a heavy slab
    /// floating above the bottom edge.
    func test_ribbonHugsTheBottomEdge_andStaysTranslucent() throws {
        let lane = AttentionLightRenderer.render(spec(), attention: .error, restartSweep: true)
        let attention = try XCTUnwrap(root(of: lane))
        let ribbon = try XCTUnwrap(attention.sublayers?.first { $0.name == "ribbon" } as? CAGradientLayer)
        let colors = try XCTUnwrap(ribbon.colors as? [CGColor])
        XCTAssertEqual(ribbon.endPoint.y, 0, accuracy: 0.0001, "the bright end is the bottom edge")
        XCTAssertLessThan(colors[0].alpha, 0.1, "no hard bright edge at the top of the band")
        XCTAssertLessThanOrEqual(colors[1].alpha, 0.85, "still translucent over the quota")
        XCTAssertGreaterThan(colors[1].alpha, 0.2)
    }

    /// The wash and the glow are bottom-heavy: the V5 wash fades upward from
    /// the bottom edge and the ribbon's glow is brightest where it meets the
    /// ribbon. Both used to be flipped, which stacked a bright slab in the
    /// lower half of the bar.
    func test_washAndGlow_fadeAwayFromTheBottomEdge() throws {
        let lane = AttentionLightRenderer.render(spec(), attention: .waiting, restartSweep: true)
        let attention = try XCTUnwrap(root(of: lane))
        let wash = try XCTUnwrap(attention.sublayers?.first { $0.name == "wash" } as? CAGradientLayer)
        let glow = try XCTUnwrap(attention.sublayers?.first { $0.name == "glow" } as? CAGradientLayer)

        XCTAssertEqual(wash.startPoint.y, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(try XCTUnwrap(wash.colors as? [CGColor])[0].alpha,
                             try XCTUnwrap(wash.colors as? [CGColor])[1].alpha)
        XCTAssertEqual(glow.startPoint.y, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(try XCTUnwrap(glow.colors as? [CGColor])[0].alpha,
                             try XCTUnwrap(glow.colors as? [CGColor])[1].alpha)
    }

    // MARK: - Colour per kind

    func test_eachKindWearsItsOwnSignalColour() throws {
        let expectations: [(AttentionKind, RGBAColor)] = [
            (.error, GlassDefaults.signalLights.error),
            (.waiting, GlassDefaults.signalLights.waiting),
            (.unread, GlassDefaults.signalLights.unread),
        ]
        for (kind, color) in expectations {
            let lane = AttentionLightRenderer.render(spec(), attention: kind, restartSweep: true)
            let attention = try XCTUnwrap(root(of: lane))
            let top = try XCTUnwrap(attention.sublayers?.first { $0.name == "topLine" })
            let components = try XCTUnwrap(top.backgroundColor?.components)
            XCTAssertEqual(Double(components[0]), color.red, accuracy: 0.01, "\(kind)")
        }
    }

    func test_userSignalOverride_reachesTheRibbon() throws {
        var glass = ResolvedGlassTheme.default(providerId: "codex")
        let custom = RGBAColor(red: 0.1, green: 0.9, blue: 0.4)
        glass.signalLights.waiting = custom
        let lane = AttentionLightRenderer.render(spec(glass: glass), attention: .waiting, restartSweep: true)
        let attention = try XCTUnwrap(root(of: lane))
        let top = try XCTUnwrap(attention.sublayers?.first { $0.name == "topLine" })
        let components = try XCTUnwrap(top.backgroundColor?.components)
        XCTAssertEqual(Double(components[1]), 0.9, accuracy: 0.01)
    }

    // MARK: - Sweep tempo and restarts

    func test_sweepDurations_matchTheKinds() throws {
        let expectations: [(AttentionKind, Double)] = [(.error, 4), (.waiting, 5), (.unread, 7)]
        for (kind, seconds) in expectations {
            let lane = AttentionLightRenderer.render(spec(), attention: kind, restartSweep: true)
            let attention = try XCTUnwrap(root(of: lane))
            let glint = try XCTUnwrap(attention.sublayers?.first { $0.name == "ribbon" }?
                .sublayers?.first { $0.name == "glint" })
            let sweep = try XCTUnwrap(glint.animation(forKey: "attentionSweep") as? CAKeyframeAnimation)
            XCTAssertEqual(sweep.duration, seconds, "\(kind)")
            XCTAssertEqual(sweep.repeatCount, .infinity)
        }
    }

    func test_sameKindKeepsTheRunningSweepWithoutRestarting() throws {
        let lane = CALayer()
        lane.frame = geometry.trackRect
        AttentionLightRenderer.update(into: lane, spec: spec(), attention: .waiting, restartSweep: true)
        let attention = try XCTUnwrap(root(of: lane))
        let glint = try XCTUnwrap(attention.sublayers?.first { $0.name == "ribbon" }?
            .sublayers?.first { $0.name == "glint" })
        let first = try XCTUnwrap(glint.animation(forKey: "attentionSweep"))

        // A quota refresh / re-render with the same state must not re-add it.
        AttentionLightRenderer.update(into: lane, spec: spec(), attention: .waiting, restartSweep: false)
        let second = try XCTUnwrap(glint.animation(forKey: "attentionSweep"))
        XCTAssertTrue(first === second, "the sweep must survive ordinary re-renders")
    }

    func test_changedKindRestartsTheFirstSweep() throws {
        let lane = CALayer()
        lane.frame = geometry.trackRect
        AttentionLightRenderer.update(into: lane, spec: spec(), attention: .waiting, restartSweep: true)
        let attention = try XCTUnwrap(root(of: lane))
        let glint = try XCTUnwrap(attention.sublayers?.first { $0.name == "ribbon" }?
            .sublayers?.first { $0.name == "glint" })
        let first = try XCTUnwrap(glint.animation(forKey: "attentionSweep"))
        AttentionLightRenderer.update(into: lane, spec: spec(), attention: .error, restartSweep: true)
        let second = try XCTUnwrap(glint.animation(forKey: "attentionSweep"))
        XCTAssertFalse(first === second, "a new state must replay its first sweep")
        XCTAssertEqual((second as? CAKeyframeAnimation)?.duration, 4)
    }

    // MARK: - None / Reduce Motion

    func test_noneHidesEverythingAndStopsTheSweep() throws {
        let lane = AttentionLightRenderer.render(spec(), attention: .waiting, restartSweep: true)
        AttentionLightRenderer.update(into: lane, spec: spec(), attention: .none, restartSweep: true)
        let attention = try XCTUnwrap(root(of: lane))
        XCTAssertTrue(attention.isHidden)
        for layer in attention.sublayers ?? [] {
            XCTAssertNil(layer.animation(forKey: "attentionSweep"))
        }
    }

    func test_reduceMotion_keepsStaticCuesAndDropsTheSweep() throws {
        let lane = AttentionLightRenderer.render(spec(reduceMotion: true), attention: .error, restartSweep: true)
        let attention = try XCTUnwrap(root(of: lane))
        XCTAssertFalse(attention.isHidden)
        let top = try XCTUnwrap(attention.sublayers?.first { $0.name == "topLine" })
        XCTAssertEqual(top.frame.height, 2, accuracy: 0.001)
        let glint = try XCTUnwrap(attention.sublayers?.first { $0.name == "ribbon" }?
            .sublayers?.first { $0.name == "glint" })
        XCTAssertTrue(glint.isHidden)
        XCTAssertNil(glint.animation(forKey: "attentionSweep"))
    }

    func test_themeCanResizeTheRibbon() throws {
        var glass = ResolvedGlassTheme.default(providerId: "codex")
        glass.attention.bottomRibbonHeight = 8
        glass.attention.topLineHeight = 3
        let lane = AttentionLightRenderer.render(spec(glass: glass), attention: .unread, restartSweep: true)
        let attention = try XCTUnwrap(root(of: lane))
        XCTAssertEqual(attention.sublayers?.first { $0.name == "ribbon" }?.frame.height ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(attention.sublayers?.first { $0.name == "topLine" }?.frame.height ?? 0, 3, accuracy: 0.001)
    }
}
