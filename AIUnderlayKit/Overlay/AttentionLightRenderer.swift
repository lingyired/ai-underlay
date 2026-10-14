import AppKit

/// The one attention language: a thin always-on top line, a translucent bottom
/// light ribbon with a soft upward glow, a faint full-height wash, and a
/// single-sided sweep that plays once when the state changes and then loops at
/// the kind's own tempo.
///
/// Error, Waiting and Unread are the *same structure* with different colours
/// and sweep durations — never three bespoke styles. The colour comes from the
/// resolved signal lights; the priority that chose the kind is a code constant.
@MainActor
public enum AttentionLightRenderer {
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
        let size = spec.geometry.trackRect.size
        root.frame = CGRect(origin: .zero, size: size)
        root.masksToBounds = true

        guard attention != .none else {
            root.isHidden = true
            stopAnimations(root)
            return
        }
        root.isHidden = false

        let color = spec.glass.signalLights.light(for: attention)
        let geometry = spec.glass.attention
        let height = size.height
        let topHeight = min(max(CGFloat(geometry.topLineHeight), 0), height / 6)
        let ribbonHeight = min(max(CGFloat(geometry.bottomRibbonHeight), 0), height / 3)
        let glowHeight = min(height * 0.45, ribbonHeight * 3)
        let sweepSeconds = geometry.sweepSeconds(for: attention)
        let animated = !spec.reduceMotion

        // Full-lane wash, bottom-up: the breathing room of the alert.
        let wash = LayerSlot.named("wash", in: root, as: CAGradientLayer.self)
        wash.frame = CGRect(origin: .zero, size: size)
        wash.type = .axial
        wash.startPoint = CGPoint(x: 0.5, y: 1)
        wash.endPoint = CGPoint(x: 0.5, y: 0.05)
        wash.colors = [color.withAlpha(0.24).cgColor, color.withAlpha(0).cgColor]

        // Glow rising out of the ribbon.
        let glow = LayerSlot.named("glow", in: root, as: CAGradientLayer.self)
        glow.frame = CGRect(x: 0, y: 0, width: size.width, height: glowHeight)
        glow.type = .axial
        glow.startPoint = CGPoint(x: 0.5, y: 0)
        glow.endPoint = CGPoint(x: 0.5, y: 1)
        glow.colors = [color.withAlpha(0).cgColor, color.withAlpha(0.38).cgColor]

        // The ribbon: translucent so the quota fill stays readable through it.
        let ribbon = LayerSlot.named("ribbon", in: root, as: CAGradientLayer.self)
        ribbon.frame = CGRect(x: 0, y: 0, width: size.width, height: ribbonHeight)
        ribbon.type = .axial
        ribbon.startPoint = CGPoint(x: 0.5, y: 1)
        ribbon.endPoint = CGPoint(x: 0.5, y: 0)
        ribbon.colors = [color.withAlpha(min(color.alpha, 0.85)).cgColor, color.withAlpha(0.05).cgColor]
        ribbon.masksToBounds = true

        // The top line: 2pt of solid alert that survives Reduce Motion.
        let topLine = LayerSlot.named("topLine", in: root)
        topLine.frame = CGRect(x: 0, y: height - topHeight, width: size.width, height: topHeight)
        topLine.backgroundColor = color.cgColor
        topLine.shadowColor = color.cgColor
        topLine.shadowOpacity = 0.75
        topLine.shadowRadius = 3
        topLine.shadowOffset = .zero

        _ = updateGlint(ribbon, color: color, animated: animated, restart: restartSweep, sweepSeconds: sweepSeconds)

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
