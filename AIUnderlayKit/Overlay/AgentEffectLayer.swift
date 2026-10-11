import AppKit

/// Visual treatment for an agent state. Kept as data so it is testable without
/// rendering: which state shows what, and how strongly.
public struct AgentEffectStyle: Equatable, Sendable {
    public var color: RGBAColor
    public var pulse: Bool
    /// A soft highlight sweeping along the fill direction (used while running).
    public var sweep: Bool

    public init(color: RGBAColor, pulse: Bool, sweep: Bool) {
        self.color = color
        self.pulse = pulse
        self.sweep = sweep
    }

    /// Style for a state. `nil` (no agent activity) returns nil — nothing drawn.
    public static func style(for state: AgentState?) -> AgentEffectStyle? {
        switch state {
        case .none, .idle:
            return nil
        case .running:
            // A moving shimmer across the bar: "the agent is working".
            return AgentEffectStyle(color: RGBAColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 0.55), pulse: false, sweep: true)
        case .waitingInput:
            return AgentEffectStyle(color: RGBAColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.95), pulse: true, sweep: false)
        case .waitingApproval:
            return AgentEffectStyle(color: RGBAColor(red: 1.0, green: 0.55, blue: 0.2, alpha: 0.95), pulse: true, sweep: false)
        case .completed:
            return AgentEffectStyle(color: RGBAColor(red: 0.4, green: 0.9, blue: 0.5, alpha: 0.95), pulse: false, sweep: true)
        case .error:
            return AgentEffectStyle(color: RGBAColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 0.95), pulse: true, sweep: false)
        case .unknown, .reconnecting:
            return nil  // never animate a state we cannot observe
        }
    }
}

/// Draws agent activity on the menu bar band. Never changes the quota fill's
/// length or color — it is a separate visual channel layered on top.
public enum AgentEffectLayer {
    public static let dotSize: CGFloat = 8
    /// How long one shimmer sweep takes.
    public static let sweepDuration: CFTimeInterval = 2.4

    public static func make(
        state: AgentState,
        geometry: GaugeGeometry,
        reduceMotion: Bool
    ) -> CALayer? {
        guard let style = AgentEffectStyle.style(for: state) else { return nil }

        let container = CALayer()
        container.frame = geometry.trackRect

        if style.sweep {
            container.addSublayer(makeShimmer(geometry: geometry, style: style, reduceMotion: reduceMotion))
        }
        if style.pulse {
            container.addSublayer(makeDot(geometry: geometry, style: style, reduceMotion: reduceMotion))
        }
        return container
    }

    /// A soft gradient highlight that travels from the anchor to the far end of
    /// the fill, then repeats. Cheap: one Core Animation layer, no per-frame work.
    private static func makeShimmer(
        geometry: GaugeGeometry,
        style: AgentEffectStyle,
        reduceMotion: Bool
    ) -> CALayer {
        let fill = geometry.fillBounds
        let bandWidth = max(60, fill.width * 0.35)
        let band = CAGradientLayer()
        band.colors = [
            style.color.cgColor(alpha: 0),
            style.color.cgColor,
            style.color.cgColor(alpha: 0),
        ]
        band.locations = [0, 0.5, 1]
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)

        let fromX = geometry.growsTowardRight ? fill.minX - bandWidth : fill.maxX
        let toX = geometry.growsTowardRight ? fill.maxX : fill.minX - bandWidth
        band.frame = CGRect(x: fromX, y: fill.minY, width: bandWidth, height: fill.height)

        // Clip so the sweep never leaves this provider's fill area.
        let clip = CALayer()
        clip.frame = geometry.trackRect
        clip.masksToBounds = true
        clip.addSublayer(band)

        if !reduceMotion {
            let anim = CABasicAnimation(keyPath: "position.x")
            anim.fromValue = fromX + bandWidth / 2
            anim.toValue = toX + bandWidth / 2
            anim.duration = sweepDuration
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            band.add(anim, forKey: "shimmer")
        }
        return clip
    }

    /// A pulsing endpoint dot at the anchor, for the "needs you" states.
    private static func makeDot(
        geometry: GaugeGeometry,
        style: AgentEffectStyle,
        reduceMotion: Bool
    ) -> CALayer {
        let dot = CALayer()
        let x = geometry.growsTowardRight ? geometry.fillBounds.minX : geometry.fillBounds.maxX - dotSize
        dot.frame = CGRect(x: x, y: (geometry.trackRect.height - dotSize) / 2,
                           width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = style.color.cgColor

        if !reduceMotion {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.3
            animation.toValue = 1.0
            animation.duration = 0.9
            animation.autoreverses = true
            animation.repeatCount = .infinity
            dot.add(animation, forKey: "pulse")
        }
        return dot
    }
}

private extension RGBAColor {
    func cgColor(alpha: Double) -> CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}