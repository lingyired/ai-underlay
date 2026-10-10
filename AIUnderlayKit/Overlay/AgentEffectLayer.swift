import AppKit

/// Visual treatment for an agent state. Kept as data so it is testable without
/// rendering: which state shows what, and how strongly.
public struct AgentEffectStyle: Equatable, Sendable {
    public var color: RGBAColor
    public var pulse: Bool
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
            return AgentEffectStyle(color: RGBAColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.9), pulse: false, sweep: true)
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

/// Draws a small endpoint indicator at the fill's anchor end. It never changes
/// the quota fill's length or color — it is a separate visual channel.
public enum AgentEffectLayer {
    public static let dotSize: CGFloat = 8

    public static func make(
        state: AgentState,
        geometry: GaugeGeometry,
        reduceMotion: Bool
    ) -> CALayer? {
        guard let style = AgentEffectStyle.style(for: state) else { return nil }

        let container = CALayer()
        container.frame = geometry.trackRect

        let dot = CALayer()
        let x = geometry.growsTowardRight
            ? geometry.fillBounds.minX
            : geometry.fillBounds.maxX - dotSize
        dot.frame = CGRect(x: x, y: (geometry.trackRect.height - dotSize) / 2,
                           width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = style.color.cgColor
        container.addSublayer(dot)

        if style.pulse && !reduceMotion {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.3
            animation.toValue = 1.0
            animation.duration = 0.9
            animation.autoreverses = true
            animation.repeatCount = .infinity
            dot.add(animation, forKey: "pulse")
        }
        return container
    }
}
