import AppKit

/// The one attention language: a thin always-on top line, a translucent bottom
/// light ribbon with a soft upward glow, a faint full-height wash, and a
/// single-sided sweep that plays once when the state changes and then loops at
/// the kind's own tempo.
///
/// Error, Waiting and Unread are the *same structure* with different colours
/// and sweep durations — never three bespoke styles. The colour comes from the
/// resolved signal lights — the *saturated* half of each pair, because the
/// menu bar material is what the pale half cannot survive — and the priority
/// that chose the kind is a code constant.
@MainActor
public enum AttentionLightRenderer {
    /// Alpha of the two translucent alert layers.
    ///
    /// V5's lab stops are `.24` (wash) and `.38` (glow), tuned against its own
    /// flat wallpaper. A lane is not drawn on a wallpaper here: it is
    /// composited *through* the system menu bar's material, which measured
    /// ~0.70 of the requested value on the real bar (waiting top line live
    /// `180,154,94` against `#FFE1A0`), and the prediction is the same for the
    /// layers under it. Both alphas therefore carry a small, explicit
    /// compensation; the stored colours are untouched.
    static let washAlpha: Double = 0.30
    static let glowAlpha: Double = 0.46
    /// V5 paints the ribbon's bottom edge at its group opacity `.95`; the cap
    /// stays just under that so the bottom pixel never becomes a solid slab.
    static let ribbonAlpha: Double = 0.92

    /// A fresh layer tree (tests, offline preview).
    public static func render(_ spec: LaneRenderSpec, attention: AttentionKind, restartSweep: Bool) -> CALayer {
        let lane = CALayer()
        lane.name = "lane"
        lane.frame = spec.geometry.trackRect
        lane.masksToBounds = true
        update(into: lane, spec: spec, attention: attention, restartSweep: restartSweep)
        LayerSlot.reconcileLane(lane)
        return lane
    }

    public static func update(into lane: CALayer, spec: LaneRenderSpec, attention: AttentionKind, restartSweep: Bool) {
        let root = LayerSlot.named("attention", in: lane)
        // The attention band belongs to one provider: it hugs that provider's
        // own fill area. Drawing it across the full track would light up the
        // neighbour's half of a dual layout for a state it does not have.
        let region = spec.geometry.localFillBounds
        let size = region.size
        root.frame = region
        root.masksToBounds = true

        guard attention != .none else {
            root.isHidden = true
            stopAnimations(root)
            return
        }
        root.isHidden = false

        // V5 names two colours per alert: the pale `--alert` (top line, ribbon)
        // and its saturated `--tint` partner (wash, glow, ribbon glow). A lane
        // here is composited *through* the menu bar material, which measured
        // 0.70× on pale colours but leaves saturated ones untouched — `#FFE1A0`
        // arrived as `192,164,104` (tan) while `#FFC25B` arrived as
        // `201,146,34` (amber). The whole stack is therefore drawn in the tint
        // so the alert still reads as light on hardware; the alert colour
        // stays the semantic signal colour and the source of the tint.
        let color = spec.glass.signalLights.light(for: attention)
        let tint = spec.glass.signalLights.tint(for: attention)
        let geometry = spec.glass.attention
        let height = size.height
        let topHeight = min(max(CGFloat(geometry.topLineHeight), 0), height / 6)
        let ribbonHeight = min(max(CGFloat(geometry.bottomRibbonHeight), 0), height / 3)
        let glowHeight = min(height * 0.45, ribbonHeight * 3)
        let sweepSeconds = geometry.sweepSeconds(for: attention)
        let animated = !spec.reduceMotion

        // Full-lane wash, bottom-up: the breathing room of the alert.
        // V5's `.hint` is `linear-gradient(to top, rgba(var(--tint),.24),
        // transparent 95%)` — the *tint* sits on the bottom edge, so the wash
        // never reads as a pale veil over the quota. Gradient y = 1 is the top
        // of the layer.
        let wash = LayerSlot.named("wash", in: root, as: CAGradientLayer.self)
        wash.frame = CGRect(origin: .zero, size: size)
        wash.type = .axial
        wash.startPoint = CGPoint(x: 0.5, y: 0)
        wash.endPoint = CGPoint(x: 0.5, y: 0.95)
        wash.colors = [tint.withAlpha(Self.washAlpha).cgColor, tint.withAlpha(0).cgColor]

        // Glow rising out of the ribbon: the V5 band casts a shadow *upward*
        // (`0 -4px 12px rgba(var(--tint), .38)`), so it is brightest where it
        // meets the ribbon and fades with height instead of starting at its
        // own top edge — and it is cast in the tint, not in the alert colour.
        let glow = LayerSlot.named("glow", in: root, as: CAGradientLayer.self)
        glow.frame = CGRect(x: 0, y: 0, width: size.width, height: glowHeight)
        glow.type = .axial
        glow.startPoint = CGPoint(x: 0.5, y: 0)
        glow.endPoint = CGPoint(x: 0.5, y: 1)
        glow.colors = [tint.withAlpha(Self.glowAlpha).cgColor, tint.withAlpha(0).cgColor]

        // The ribbon: translucent so the quota fill stays readable through it,
        // and bright on the bottom edge — V5 draws
        // `linear-gradient(180deg, transparent, alert)`, i.e. the alert hugs
        // the bottom of the bar rather than capping the band from above.
        let ribbon = LayerSlot.named("ribbon", in: root, as: CAGradientLayer.self)
        ribbon.frame = CGRect(x: 0, y: 0, width: size.width, height: ribbonHeight)
        ribbon.type = .axial
        ribbon.startPoint = CGPoint(x: 0.5, y: 1)
        ribbon.endPoint = CGPoint(x: 0.5, y: 0)
        ribbon.colors = [
            tint.withAlpha(0.05).cgColor,
            tint.withAlpha(min(tint.alpha, Self.ribbonAlpha)).cgColor,
        ]
        ribbon.masksToBounds = true

        // The top line: 2pt of solid alert that survives Reduce Motion, with
        // V5's own halo (`box-shadow: 0 0 9px var(--alert)` at group opacity
        // `.95`; CSS blur 9px ≈ a 4.5pt Core Animation shadow radius). The
        // halo is what keeps the line reading as a light source after the
        // material has taken its ~30%.
        let topLine = LayerSlot.named("topLine", in: root)
        topLine.frame = CGRect(x: 0, y: height - topHeight, width: size.width, height: topHeight)
        topLine.backgroundColor = tint.cgColor
        topLine.shadowColor = tint.cgColor
        topLine.shadowOpacity = 0.95
        topLine.shadowRadius = 4.5
        topLine.shadowOffset = .zero

        // The sweep is optional: the static alert (top line, ribbon, glow)
        // carries the state on its own, and some users read the moving band as
        // a flash rather than a signal.
        _ = updateGlint(
            ribbon, color: color,
            animated: animated && spec.showsAttentionSweep,
            restart: restartSweep, sweepSeconds: sweepSeconds
        )

        LayerSlot.reconcile(root, keeping: ["wash", "glow", "ribbon", "topLine"])
        LayerSlot.reconcile(ribbon, keeping: ["glint"])
    }

    /// Stops the sweep. Called when attention clears, Reduce Motion turns on,
    /// or the overlay shuts down, so nothing keeps ticking off-screen.
    public static func stopAnimations(_ lane: CALayer) {
        guard let root = LayerSlot.root(named: "attention", in: lane) else { return }
        root.sublayers?.forEach { $0.removeAnimation(forKey: "attentionSweep") }
        root.sublayers?.forEach { layer in
            layer.sublayers?.forEach { $0.removeAnimation(forKey: "attentionSweep") }
        }
    }

    private static func updateGlint(
        _ ribbon: CAGradientLayer,
        color: RGBAColor,
        animated: Bool,
        restart: Bool,
        sweepSeconds: Double
    ) -> CALayer {
        let glint = LayerSlot.named("glint", in: ribbon, as: CAGradientLayer.self)

        guard animated else {
            glint.isHidden = true
            glint.removeAnimation(forKey: "attentionSweep")
            return glint
        }
        glint.isHidden = false

        // V5: the sweep crosses a 26%-wide band once, then waits, on a loop.
        let width = max(24, ribbon.bounds.width * 0.26)
        glint.frame = CGRect(x: -width, y: 0, width: width, height: ribbon.bounds.height)
        glint.type = .axial
        glint.startPoint = CGPoint(x: 0, y: 0.5)
        glint.endPoint = CGPoint(x: 1, y: 0.5)
        let highlight = color.luminance > 0.72
            ? CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
            : color.withAlpha(0.95).cgColor
        glint.colors = [
            color.withAlpha(0).cgColor,
            highlight,
            color.withAlpha(0).cgColor,
        ]
        glint.locations = [0, 0.5, 1]

        let existing = glint.animation(forKey: "attentionSweep") as? CAKeyframeAnimation
        if !restart, existing?.duration == sweepSeconds { return glint }

        let start = NSNumber(value: -Double(width) / 2)
        let finish = NSNumber(value: Double(ribbon.bounds.width) + Double(width) / 2)
        let travel = CAKeyframeAnimation(keyPath: "position.x")
        travel.values = [start, start, finish, finish]
        travel.keyTimes = [0, 0.14, 0.66, 1]
        travel.duration = sweepSeconds
        travel.repeatCount = .infinity
        travel.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glint.add(travel, forKey: "attentionSweep")
        return glint
    }
}
