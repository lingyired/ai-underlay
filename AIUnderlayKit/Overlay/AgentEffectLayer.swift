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
    /// Top and bottom edge highlight — yellow for "needs you", red for a
    /// confirmed failure (spec §5.3). `nil` draws no border.
    public var borderColor: RGBAColor?
    /// Border thickness in points.
    public var borderWidth: CGFloat

    public init(
        color: RGBAColor,
        pulse: Bool,
        sweep: Bool,
        breathe: Bool = false,
        borderColor: RGBAColor? = nil,
        borderWidth: CGFloat = 2
    ) {
        self.color = color
        self.pulse = pulse
        self.sweep = sweep
        self.breathe = breathe
        self.borderColor = borderColor
        self.borderWidth = borderWidth
    }

    /// Yellow edge used by the "needs you" states. Distinct from the amber fill
    /// so the warning survives even when the provider's own color is orange.
    public static let attentionBorder = RGBAColor(red: 1.00, green: 0.93, blue: 0.35, alpha: 0.95)
    /// Red edge used by a confirmed failure.
    public static let failureBorder = RGBAColor(red: 1.00, green: 0.32, blue: 0.42, alpha: 0.95)

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
    /// Style for a state. `runningColor` is an explicit user choice and wins over
    /// the theme; `theme` only fills in what the user did not pick. The
    /// Error > Waiting > Normal priority is fixed here, never in a theme file.
    public static func style(
        for state: AgentState?,
        runningColor: RGBAColor? = nil,
        theme: AgentEffectTheme? = nil
    ) -> AgentEffectStyle? {
        switch state {
        case .none, .idle:
            return nil
        case .running:
            let color = runningColor ?? theme?.runningColor ?? defaultColor(for: .running)
            return AgentEffectStyle(color: color, pulse: false, sweep: true, breathe: true)
        case .waitingInput:
            return AgentEffectStyle(color: theme?.waitingOverlay ?? defaultColor(for: .waitingInput),
                                    pulse: true, sweep: false,
                                    borderColor: theme?.waitingBorder ?? attentionBorder,
                                    borderWidth: theme?.waitingBorderWidth ?? 2)
        case .waitingApproval:
            return AgentEffectStyle(color: theme?.waitingOverlay ?? defaultColor(for: .waitingApproval),
                                    pulse: true, sweep: false,
                                    borderColor: theme?.waitingBorder ?? attentionBorder,
                                    borderWidth: theme?.waitingBorderWidth ?? 2)
        case .completed:
            return AgentEffectStyle(color: defaultColor(for: .completed), pulse: false, sweep: true)
        case .error:
            return AgentEffectStyle(color: theme?.errorOverlay ?? defaultColor(for: .error),
                                    pulse: true, sweep: false,
                                    borderColor: theme?.errorBorder ?? failureBorder,
                                    borderWidth: theme?.errorBorderWidth ?? 2)
        case .unknown, .reconnecting:
            return nil  // never animate a state we cannot observe
        }
    }
}

/// What the bar should do right now, derived from a provider's signals.
///
/// This is where the combination matrix from the product consensus (§5.2) is
/// decided, as plain data so it is testable without rendering: a provider can
/// be waiting *and* working, and then both are drawn — the moving spectrum in
/// the alert color plus the warning edges.
public struct AgentEffectPlan: Equatable, Sendable {
    /// Something is running: the chosen running effect plays.
    public var moves: Bool
    /// Color of the moving effect.
    public var motionColor: RGBAColor?
    /// Full-width wash for a "needs you" or failed state.
    public var alertOverlay: RGBAColor?
    public var borderColor: RGBAColor?
    public var borderWidth: CGFloat
    /// Nothing else is happening and a session just finished: one short sweep.
    public var acknowledgeCompletion: Bool

    public init(
        moves: Bool = false,
        motionColor: RGBAColor? = nil,
        alertOverlay: RGBAColor? = nil,
        borderColor: RGBAColor? = nil,
        borderWidth: CGFloat = 2,
        acknowledgeCompletion: Bool = false
    ) {
        self.moves = moves
        self.motionColor = motionColor
        self.alertOverlay = alertOverlay
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.acknowledgeCompletion = acknowledgeCompletion
    }

    /// `nil` means "draw nothing at all".
    ///
    /// Error still outranks Waiting, and neither one stops an active session
    /// from showing — a failure in one session must not hide that another one
    /// is still working (§5.2).
    public static func make(
        signals: AgentSignals,
        runningColor: RGBAColor? = nil,
        theme: AgentEffectTheme? = nil
    ) -> AgentEffectPlan? {
        if !signals.hasError && !signals.hasWaiting && !signals.hasActive && signals.completedCount == 0 {
            return nil
        }

        var plan = AgentEffectPlan(moves: signals.hasActive)
        if signals.hasError {
            let overlay = theme?.errorOverlay ?? AgentEffectStyle.defaultColor(for: .error)
            plan.alertOverlay = overlay
            plan.motionColor = theme?.errorSpectrum ?? overlay
            plan.borderColor = theme?.errorBorder ?? AgentEffectStyle.failureBorder
            plan.borderWidth = theme?.errorBorderWidth ?? 2
        } else if signals.hasWaiting {
            // Approval (orange) is the more urgent flavor, so a provider waiting
            // on both keeps the color a single-session approval would have had.
            let base = signals.waitingApprovalCount > 0
                ? AgentEffectStyle.defaultColor(for: .waitingApproval)
                : AgentEffectStyle.defaultColor(for: .waitingInput)
            let overlay = theme?.waitingOverlay ?? base
            plan.alertOverlay = overlay
            plan.motionColor = theme?.waitingSpectrum ?? overlay
            plan.borderColor = theme?.waitingBorder ?? AgentEffectStyle.attentionBorder
            plan.borderWidth = theme?.waitingBorderWidth ?? 2
        } else if signals.hasActive {
            plan.motionColor = runningColor ?? theme?.runningColor ?? AgentEffectStyle.defaultColor(for: .running)
        } else {
            plan.acknowledgeCompletion = true
            plan.motionColor = AgentEffectStyle.defaultColor(for: .completed)
        }
        return plan
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
        runningColor: RGBAColor? = nil,
        outputTPS: Double? = nil,
        theme: AgentEffectTheme? = nil
    ) -> CALayer? {
        make(signals: AgentSignals(state: state), geometry: geometry, reduceMotion: reduceMotion,
             runningEffect: runningEffect, runningColor: runningColor, outputTPS: outputTPS, theme: theme)
    }

    /// Draws everything the signals call for. A provider that is both waiting
    /// and working gets both: the moving effect *and* the alert edges.
    public static func make(
        signals: AgentSignals,
        geometry: GaugeGeometry,
        reduceMotion: Bool,
        runningEffect: RunningEffect = .breathing,
        runningColor: RGBAColor? = nil,
        outputTPS: Double? = nil,
        theme: AgentEffectTheme? = nil
    ) -> CALayer? {
        guard let plan = AgentEffectPlan.make(signals: signals, runningColor: runningColor, theme: theme) else {
            return nil
        }

        let container = CALayer()
        container.frame = geometry.trackRect

        // A "needs you" or failed state always shows its wash and its edges,
        // whether or not other sessions are still working.
        let refinedLight = runningEffect == .spectrumGlow
        if let overlay = plan.alertOverlay {
            // The premium mode keeps the quota visible through a translucent
            // light field. Classic modes preserve their familiar wash.
            if refinedLight {
                // Active spectrum glow already carries the warning hue.
                if !plan.moves {
                    container.addSublayer(makeAmbientField(geometry: geometry, color: overlay,
                                                           reduceMotion: reduceMotion))
                }
            } else {
                container.addSublayer(makeBreathing(geometry: geometry, color: overlay, reduceMotion: reduceMotion))
            }
        }

        if plan.moves, let color = plan.motionColor {
            let style = AgentEffectStyle(color: color, pulse: false, sweep: true)
            switch runningEffect {
            case .breathing:
                container.addSublayer(makeBreathing(geometry: geometry, color: color, reduceMotion: reduceMotion))
            case .sweep:
                container.addSublayer(makeShimmer(geometry: geometry, style: style, reduceMotion: reduceMotion,
                                                  repeatForever: true))
            case .dot:
                container.addSublayer(makeDot(geometry: geometry, style: style, reduceMotion: reduceMotion))
            case .spectrum:
                container.addSublayer(makeSpectrum(geometry: geometry, style: style,
                                                   reduceMotion: reduceMotion, outputTPS: outputTPS))
            case .spectrumGlow:
                container.addSublayer(makeSpectrumGlow(geometry: geometry, color: color,
                                                       reduceMotion: reduceMotion, outputTPS: outputTPS))
            case .none:
                break
            }
        }

        if plan.acknowledgeCompletion {
            let style = AgentEffectStyle(color: plan.motionColor ?? AgentEffectStyle.defaultColor(for: .completed),
                                         pulse: false, sweep: true)
            container.addSublayer(makeShimmer(geometry: geometry, style: style, reduceMotion: reduceMotion,
                                              repeatForever: false))
        }

        if let borderColor = plan.borderColor {
            if refinedLight {
                container.addSublayer(makeAttentionRibbon(geometry: geometry, color: borderColor,
                                                          width: plan.borderWidth, reduceMotion: reduceMotion,
                                                          isError: signals.hasError))
            } else {
                container.addSublayer(makeEdgeBorders(geometry: geometry, color: borderColor, width: plan.borderWidth))
            }
        }

        return container.sublayers?.isEmpty == false ? container : nil
    }

    /// A full-width soft light that gently brightens and dims over the fill —
    /// the "breathing" look. One layer, animated by opacity only.
    private static func makeBreathing(geometry: GaugeGeometry, color: RGBAColor, reduceMotion: Bool) -> CALayer {
        // A solid, saturated layer that fades in and out — at the peak the whole
        // fill clearly shows the state color, so a glance reads it instantly.
        let glow = CALayer()
        // Preserve alpha authored in theme JSON (previously overwritten by 0.9).
        glow.backgroundColor = color.cgColor
        glow.frame = geometry.fillBounds

        let clip = CALayer()
        clip.frame = geometry.trackRect
        clip.masksToBounds = true
        clip.addSublayer(glow)

        if !reduceMotion {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0.05
            anim.toValue = 0.48
            anim.duration = 1.8
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(anim, forKey: "breathe")
        } else {
            glow.opacity = 0.32
        }
        return clip
    }

    /// A soft gradient highlight that travels from the anchor to the far end of
    /// the fill, then repeats. Cheap: one Core Animation layer, no per-frame work.
    private static func makeShimmer(
        geometry: GaugeGeometry,
        style: AgentEffectStyle,
        reduceMotion: Bool,
        repeatForever: Bool
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
            anim.repeatCount = repeatForever ? .infinity : 1
            if !repeatForever {
                anim.fillMode = .forwards
                anim.isRemovedOnCompletion = false

                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [1, 1, 0]
                fade.keyTimes = [0, 0.65, 1]
                fade.duration = sweepDuration
                fade.fillMode = .forwards
                fade.isRemovedOnCompletion = false
                band.add(fade, forKey: "shimmerFade")
            }
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            band.add(anim, forKey: "shimmer")
        }
        return clip
    }

    /// Equalizer bars rising from the menu bar's lower edge. One `CALayer` per
    /// bar, driven by a keyframe animation on `bounds.size.height`, so the whole
    /// wave runs in Core Animation with no per-frame CPU work.
    ///
    /// Active is the on/off switch and speed only changes the rhythm (spec
    /// §6.2); a missing speed measurement falls back to the slowest rhythm
    /// rather than stopping. Bar count is a texture, never a session count.
    private static func makeSpectrum(
        geometry: GaugeGeometry,
        style: AgentEffectStyle,
        reduceMotion: Bool,
        outputTPS: Double?
    ) -> CALayer {
        let fill = geometry.fillBounds
        let container = CALayer()
        container.frame = geometry.trackRect
        container.masksToBounds = true

        let barHeight = fill.height
        let offsets = SpectrumRhythm.barOffsets(width: fill.width,
                                                growsTowardRight: geometry.growsTowardRight)
        let cycle = SpectrumRhythm.cycleDuration(outputTPS: outputTPS)
        let now = CACurrentMediaTime()

        for (index, offset) in offsets.enumerated() {
            let bar = CALayer()
            bar.backgroundColor = style.color.cgColor
            bar.cornerRadius = min(SpectrumRhythm.barWidth, barHeight) / 2
            // Anchored at the lower edge, so growing the bounds grows the bar up.
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.bounds = CGRect(x: 0, y: 0, width: SpectrumRhythm.barWidth, height: barHeight)
            bar.position = CGPoint(x: fill.minX + offset, y: fill.minY)

            let factors = SpectrumRhythm.keyframeValues(index: index)
            let heights = factors.map { CGFloat($0) * barHeight }

            guard !reduceMotion, heights.count > 1 else {
                bar.bounds.size.height = heights.first ?? barHeight
                container.addSublayer(bar)
                continue
            }

            let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
            animation.values = heights
            animation.keyTimes = heights.indices.map { NSNumber(value: Double($0) / Double(heights.count)) }
            animation.duration = cycle
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            // Start each bar earlier than the last so the row reads as a wave
            // travelling along the bar instead of one block flashing together.
            let phase = Double(index % heights.count) / Double(heights.count)
            animation.beginTime = now - cycle * phase
            bar.add(animation, forKey: "spectrum")
            container.addSublayer(bar)
        }
        return container
    }


    /// A low-cost ambient light field, not an opaque status-color wash.
    /// The broad hue and its soft moving caustic are composited over quota
    /// without erasing the nested fill boundaries or menu bar text.
    private static func makeAmbientField(
        geometry: GaugeGeometry,
        color: RGBAColor,
        reduceMotion: Bool
    ) -> CALayer {
        let fill = geometry.fillBounds
        let clip = CALayer()
        clip.frame = geometry.trackRect
        clip.masksToBounds = true
        guard fill.width > 0 && fill.height > 0 else { return clip }

        let strength = min(max(color.alpha, 0), 0.65)
        let bed = CAGradientLayer()
        bed.frame = fill
        bed.startPoint = CGPoint(x: 0.5, y: 1)
        bed.endPoint = CGPoint(x: 0.5, y: 0)
        bed.colors = [
            color.cgColor(alpha: strength * 0.03),
            color.cgColor(alpha: strength * 0.15),
            color.cgColor(alpha: strength * 0.32)
        ]
        bed.locations = [0, 0.55, 1]
        clip.addSublayer(bed)

        let beamWidth = min(fill.width, max(80, fill.width * 0.42))
        let beam = CAGradientLayer()
        beam.frame = CGRect(x: fill.minX, y: fill.minY, width: beamWidth, height: fill.height)
        beam.startPoint = CGPoint(x: 0, y: 0.5)
        beam.endPoint = CGPoint(x: 1, y: 0.5)
        beam.colors = [
            color.cgColor(alpha: 0),
            color.cgColor(alpha: strength * 0.10),
            CGColor(red: 1, green: 1, blue: 1, alpha: strength * 0.08),
            color.cgColor(alpha: 0)
        ]
        beam.locations = [0, 0.30, 0.65, 1]
        clip.addSublayer(beam)

        if !reduceMotion {
            let motion = CABasicAnimation(keyPath: "position.x")
            motion.fromValue = fill.minX - beamWidth / 2
            motion.toValue = fill.maxX + beamWidth / 2
            motion.duration = 11
            motion.repeatCount = .infinity
            motion.autoreverses = true
            motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            beam.add(motion, forKey: "ambientDrift")
        } else {
            beam.position.x = fill.midX
        }
        return clip
    }

    /// A light curtain made of three interleaved groups of sub-pixel rays.
    /// Each group owns one path and one CA animation: a long menu bar does not
    /// create hundreds of independent animated layers as the classic spectrum
    /// does. The shapes remain deterministic and their tempo alone follows TPS.
    private static func makeSpectrumGlow(
        geometry: GaugeGeometry,
        color: RGBAColor,
        reduceMotion: Bool,
        outputTPS: Double?
    ) -> CALayer {
        let fill = geometry.fillBounds
        let container = CALayer()
        container.frame = geometry.trackRect
        container.masksToBounds = true
        guard fill.width > 0 && fill.height > 0 else { return container }

        container.addSublayer(makeAmbientField(geometry: geometry, color: color, reduceMotion: reduceMotion))
        let rayCount = min(210, max(1, Int(fill.width / 3.2)))
        let gap = fill.width / CGFloat(rayCount)
        let cycle = SpectrumRhythm.cycleDuration(outputTPS: outputTPS)
        let now = CACurrentMediaTime()

        for group in 0..<3 {
            let path = CGMutablePath()
            for index in stride(from: group, to: rayCount, by: 3) {
                let x = (CGFloat(index) + 0.5) * gap
                let wave = SpectrumRhythm.wave(index: index)
                let peak = 0.26 + 0.65 * wave.amplitude
                let variation = 0.45 + 0.55 * abs(sin(Double(index) * 0.47 + Double(group)))
                let height = fill.height * CGFloat(peak * variation)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
            }

            // Broad translucent rays provide bloom without rasterizing each
            // line separately or using a continuously evaluated shader.
            let bloom = CAShapeLayer()
            bloom.frame = CGRect(origin: .zero, size: fill.size)
            bloom.path = path
            bloom.strokeColor = color.cgColor(alpha: min(color.alpha, 0.20))
            bloom.lineWidth = 4
            bloom.lineCap = .round
            bloom.shadowColor = color.cgColor
            bloom.shadowOpacity = 0.4
            bloom.shadowRadius = 3
            bloom.shadowOffset = .zero
            bloom.shouldRasterize = true
            bloom.rasterizationScale = 2

            let light = CAShapeLayer()
            light.frame = CGRect(origin: .zero, size: fill.size)
            light.path = path
            light.strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: min(color.alpha, 0.73))
            light.lineWidth = 0.9
            light.lineCap = .round

            let moving = CALayer()
            moving.bounds = CGRect(origin: .zero, size: fill.size)
            moving.anchorPoint = CGPoint(x: 0.5, y: 0)
            moving.position = CGPoint(x: fill.midX, y: fill.minY)
            moving.addSublayer(bloom)
            moving.addSublayer(light)
            container.addSublayer(moving)

            if !reduceMotion {
                let pulse = CAKeyframeAnimation(keyPath: "transform.scale.y")
                pulse.values = [0.67, 1.0, 0.78, 0.67]
                pulse.keyTimes = [0, 0.32, 0.76, 1]
                pulse.duration = cycle
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                pulse.beginTime = now - cycle * Double(group) / 3
                moving.add(pulse, forKey: "spectralBreath")
            } else {
                moving.transform = CATransform3DMakeScale(1, 0.82, 1)
            }
        }
        return container
    }

    /// The same high-visibility attention language for all severity levels:
    /// a narrow top line, soft bottom light ribbon, and a periodic glint.
    /// Completion-unread can reuse this as soon as durable receipts are wired.
    private static func makeAttentionRibbon(
        geometry: GaugeGeometry,
        color: RGBAColor,
        width: CGFloat,
        reduceMotion: Bool,
        isError: Bool
    ) -> CALayer {
        let fill = geometry.fillBounds
        let clip = CALayer()
        clip.frame = geometry.trackRect
        clip.masksToBounds = true
        guard fill.width > 0 && fill.height > 0 else { return clip }

        let upper = min(max(width, 1), fill.height / 4)
        let lower = min(max(4, width * 2.5), fill.height / 3)

        let top = CALayer()
        top.frame = CGRect(x: fill.minX, y: fill.maxY - upper, width: fill.width, height: upper)
        top.backgroundColor = color.cgColor
        clip.addSublayer(top)

        let lowerHalo = CAGradientLayer()
        lowerHalo.frame = CGRect(x: fill.minX, y: fill.minY, width: fill.width, height: min(15, fill.height / 2))
        lowerHalo.startPoint = CGPoint(x: 0.5, y: 0)
        lowerHalo.endPoint = CGPoint(x: 0.5, y: 1)
        lowerHalo.colors = [color.cgColor(alpha: 0.32), color.cgColor(alpha: 0)]
        clip.addSublayer(lowerHalo)

        let band = CALayer()
        band.frame = CGRect(x: fill.minX, y: fill.minY, width: fill.width, height: lower)
        band.backgroundColor = color.cgColor
        band.masksToBounds = true
        clip.addSublayer(band)

        if !reduceMotion {
            let beamWidth = min(85, max(20, fill.width * 0.17))
            let glint = CAGradientLayer()
            glint.frame = CGRect(x: -beamWidth, y: 0, width: beamWidth, height: lower)
            glint.colors = [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.94),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0)
            ]
            glint.locations = [0, 0.5, 1]
            glint.startPoint = CGPoint(x: 0, y: 0.5)
            glint.endPoint = CGPoint(x: 1, y: 0.5)
            band.addSublayer(glint)

            let glide = CAKeyframeAnimation(keyPath: "position.x")
            let start = -beamWidth / 2
            let finish = fill.width + beamWidth / 2
            glide.values = [start, start, finish, finish].map { NSNumber(value: Double($0)) }
            glide.keyTimes = [0, 0.12, 0.68, 1]
            glide.duration = isError ? 4 : 5
            glide.repeatCount = .infinity
            glide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glint.add(glide, forKey: "attentionGlint")
        }
        return clip
    }

    /// Top and bottom edge highlights. Thin, high-contrast lines that stay
    /// legible on both light and dark menu bars, and are the only signal left
    /// when Reduce Motion turns the wash off.
    private static func makeEdgeBorders(
        geometry: GaugeGeometry,
        color: RGBAColor,
        width: CGFloat
    ) -> CALayer {
        let fill = geometry.fillBounds
        let thickness = max(1, min(width, fill.height / 2))

        let container = CALayer()
        container.frame = geometry.trackRect
        container.masksToBounds = true

        let bottom = CALayer()
        bottom.frame = CGRect(x: fill.minX, y: fill.minY, width: fill.width, height: thickness)
        bottom.backgroundColor = color.cgColor
        container.addSublayer(bottom)

        let top = CALayer()
        top.frame = CGRect(x: fill.minX, y: fill.maxY - thickness, width: fill.width, height: thickness)
        top.backgroundColor = color.cgColor
        container.addSublayer(top)

        return container
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
