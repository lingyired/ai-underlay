import AppKit

/// Visual treatment for an agent state. Kept as data so it is testable without
/// rendering: which state shows what, and how strongly.
public struct AgentEffectStyle: Equatable, Sendable {
    public var color: RGBAColor
    public var pulse: Bool
    /// A soft highlight sweeping along the fill direction (used while running).
    public var sweep: Bool
    /// The whole fill gently brightens and dims.
    public var breathe: Bool

    public init(color: RGBAColor, pulse: Bool, sweep: Bool, breathe: Bool = false) {
        self.color = color
        self.pulse = pulse
        self.sweep = sweep
        self.breathe = breathe
    }

    /// The default color for a state. Color is the primary way a glance tells
    /// states apart, so each state gets its own:
    /// green = working, amber = waiting on you, red = error, teal = done.
    public static func defaultColor(for state: AgentState) -> RGBAColor {
        switch state {
        case .running: return RGBAColor(red: 0.30, green: 1.00, blue: 0.45, alpha: 0.95)      // green
        case .waitingInput: return RGBAColor(red: 1.00, green: 0.85, blue: 0.30, alpha: 0.95) // amber
        case .waitingApproval: return RGBAColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 0.95) // orange
        case .completed: return RGBAColor(red: 0.35, green: 0.90, blue: 0.80, alpha: 0.95)    // teal
        case .error: return RGBAColor(red: 1.00, green: 0.35, blue: 0.30, alpha: 0.95)        // red
        case .idle, .unknown, .reconnecting: return RGBAColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.9)
        }
    }

    /// Style for a state. `nil` (no agent activity) returns nil — nothing drawn.
    /// `runningColor` overrides the running color only; other states keep their
    /// state colors so color always encodes state.
    public static func style(for state: AgentState?, runningColor: RGBAColor? = nil) -> AgentEffectStyle? {
        switch state {
        case .none, .idle:
            return nil
        case .running:
            return AgentEffectStyle(color: runningColor ?? defaultColor(for: .running), pulse: false, sweep: true, breathe: true)
        case .waitingInput:
            return AgentEffectStyle(color: defaultColor(for: .waitingInput), pulse: true, sweep: false)
        case .waitingApproval:
            return AgentEffectStyle(color: defaultColor(for: .waitingApproval), pulse: true, sweep: false)
        case .completed:
            return AgentEffectStyle(color: defaultColor(for: .completed), pulse: false, sweep: true)
        case .error:
            return AgentEffectStyle(color: defaultColor(for: .error), pulse: true, sweep: false)
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
    public static let sweepDuration: CFTimeInterval = 2.2

    public static func make(
        state: AgentState,
        geometry: GaugeGeometry,
        reduceMotion: Bool,
        runningEffect: RunningEffect = .breathing,
        runningColor: RGBAColor? = nil
    ) -> CALayer? {
        guard let style = AgentEffectStyle.style(for: state, runningColor: runningColor) else { return nil }

        let container = CALayer()
        container.frame = geometry.trackRect

        // The running state honors the user's chosen effect; other states keep
        // their fixed treatment (waiting/error pulse, completed sweep).
        if state == .running {
            switch runningEffect {
            case .breathing:
                container.addSublayer(makeBreathing(geometry: geometry, color: style.color, reduceMotion: reduceMotion))
            case .sweep:
                container.addSublayer(makeShimmer(geometry: geometry, style: style, reduceMotion: reduceMotion))
            case .dot:
                container.addSublayer(makeDot(geometry: geometry, style: style, reduceMotion: reduceMotion))
            case .none:
                return nil
            }
            return container
        }

        if style.sweep {
            container.addSublayer(makeShimmer(geometry: geometry, style: style, reduceMotion: reduceMotion))
        }
        if style.pulse {
            // The "needs you" states show as a full-width breathing wash in the
            // state color — as loud as the running breathe, and with no marker
            // crowding the menu bar's left edge.
            container.addSublayer(makeBreathing(geometry: geometry, color: style.color, reduceMotion: reduceMotion))
        }
        return container
    }

    /// A full-width soft light that gently brightens and dims over the fill —
    /// the "breathing" look. One layer, animated by opacity only.
    private static func makeBreathing(geometry: GaugeGeometry, color: RGBAColor, reduceMotion: Bool) -> CALayer {
        // A solid, saturated layer that fades in and out — at the peak the whole
        // fill clearly shows the state color, so a glance reads it instantly.
        let glow = CALayer()
        glow.backgroundColor = color.cgColor(alpha: 0.9)
        glow.frame = geometry.fillBounds

        let clip = CALayer()
        clip.frame = geometry.trackRect
        clip.masksToBounds = true
        clip.addSublayer(glow)

        if !reduceMotion {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0.05
            anim.toValue = 1.0
            anim.duration = 1.3
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(anim, forKey: "breathe")
        } else {
            glow.opacity = 0.6
        }
        return clip
    }

    /// A soft gradient highlight that travels from the anchor to the far end of
    /// the fill, then repeats. Cheap: one Core Animation layer, no per-frame work.
    private static func makeShimmer(
        geometry: GaugeGeometry,
        style: AgentEffectStyle,
        reduceMotion: Bool
    ) -> CALayer {
        let fill = geometry.fillBounds
        // A solid bright band with soft shoulders — crisp enough to read as a
        // passing light, not a broad wash.
        let bandWidth = max(70, fill.width * 0.22)
        let band = CAGradientLayer()
        let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)
        band.colors = [
            white.cgColor(alpha: 0),
            white.cgColor(alpha: 0.9),
            white.cgColor(alpha: 0.9),
            white.cgColor(alpha: 0),
        ]
        band.locations = [0, 0.3, 0.7, 1]
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
    ///
    /// The full-width breathing wash already carries the "needs you" signal, so
    /// the dot is a modest accent marker at the anchor — a status light, not a
    /// badge. It pulses between bright and brighter so it never fades into a
    /// smudge, and a thin dark ring keeps it legible on a light menu bar.
    private static func makeDot(
        geometry: GaugeGeometry,
        style: AgentEffectStyle,
        reduceMotion: Bool
    ) -> CALayer {
        // A fixed, modest size: big enough to read, small enough not to dominate
        // the menu bar or collide with the Apple menu.
        let diameter = min(dotSize, geometry.trackRect.height - 12)
        let x = geometry.growsTowardRight ? geometry.fillBounds.minX : geometry.fillBounds.maxX - diameter
        let rect = CGRect(x: x, y: (geometry.trackRect.height - diameter) / 2,
                          width: diameter, height: diameter)

        let container = CALayer()
        container.frame = geometry.trackRect

        let dot = CALayer()
        dot.frame = rect
        dot.cornerRadius = diameter / 2
        dot.backgroundColor = style.color.cgColor
        // A thin dark ring for contrast; not a large halo.
        dot.borderWidth = 1.5
        dot.borderColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        container.addSublayer(dot)

        if !reduceMotion {
            // Pulse between bright and brighter — the minimum stays high so the
            // light never disappears mid-pulse.
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.7
            animation.toValue = 1.0
            animation.duration = 0.9
            animation.autoreverses = true
            animation.repeatCount = .infinity
            dot.add(animation, forKey: "pulse")
        }
        return container
    }
}

private extension RGBAColor {
    func cgColor(alpha: Double) -> CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}