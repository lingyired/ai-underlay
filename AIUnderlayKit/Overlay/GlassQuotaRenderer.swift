import AppKit

/// Draws the glass quota lane: the used-up black bed, the nested remaining
/// fills in their tier brightness ladder, the agent-glass tint clipped to the
/// real outer fill, the progress end caps and the pace baseline.
///
/// This is the ONLY quota renderer. It consumes `LaneRenderSpec` only — no
/// data sources, no effect enums — and every length comes from
/// `NestedGauge.nestedLengths`, so the glass can never inflate a value.
@MainActor
public enum GlassQuotaRenderer {
    /// Below this many points a fill is visually invisible; we still draw the
    /// true (tiny) fill and add a separate end-cap so a non-zero window is not
    /// mistaken for zero, without inflating the fill's real length.
    public static let minimumVisibleLength: CGFloat = 1
    /// End-cap width, in points.
    public static let capWidth: CGFloat = 2

    /// A fresh layer tree. Used by tests and the offline preview.
    public static func render(_ spec: LaneRenderSpec) -> CALayer {
        let container = CALayer()
        container.name = "lane"
        container.frame = spec.geometry.trackRect
        container.masksToBounds = true
        update(into: container, spec: spec)
        LayerSlot.reconcileLane(container)
        return container
    }

    /// Stops the optional ambient drift so a disabled overlay holds no
    /// animation. The quota fills themselves are static, so this is the only
    /// animation this renderer owns.
    public static func stopAnimations(_ lane: CALayer) {
        guard let glass = LayerSlot.root(named: "quotaGlass", in: lane) else { return }
        func walk(_ layer: CALayer) {
            layer.removeAnimation(forKey: "ambientDrift")
            layer.sublayers?.forEach(walk)
        }
        walk(glass)
    }

    /// Idempotent in-place update of a stable tree.
    public static func update(into lane: CALayer, spec: LaneRenderSpec) {
        let geometry = spec.geometry
        lane.frame = geometry.trackRect
        lane.masksToBounds = true

        let state = QuotaDisplayState.resolve(windows: spec.windows)
        let scale = backingScale(for: lane)

        // The quota group carries the user's quota-opacity; the baseline marker
        // stays outside it so it never dims below legibility.
        let glass = LayerSlot.named("quotaGlass", in: lane)
        glass.frame = CGRect(origin: .zero, size: geometry.trackRect.size)
        glass.masksToBounds = true
        glass.opacity = Float(spec.glass.material.quotaOpacity)

        updateBed(glass, spec: spec, state: state)
        let lengths = updateFills(glass, spec: spec, state: state)
        updateTint(glass, spec: spec, state: state, outerLength: lengths.first)
        updateCaps(glass, spec: spec, state: state, lengths: lengths, scale: scale)
        LayerSlot.reconcile(glass, keeping: ["bed", "fills", "tint", "caps", "envTop", "envBottom"])

        updateBaseline(lane, spec: spec)
    }

    // MARK: - Bed (the used-up / neutral groove)

    private static func updateBed(_ parent: CALayer, spec: LaneRenderSpec, state: QuotaDisplayState) {
        let bed = LayerSlot.named("bed", in: parent, as: CAGradientLayer.self)
        // The groove is one continuous strip, but each lane paints only its own
        // slice of it: a lane that knows nothing about a provider must not dim
        // the neighbour's fill with its own neutral (or exhausted) bed.
        let groove = spec.geometry.localTrackBounds
        bed.frame = groove
        bed.type = .axial
        bed.startPoint = CGPoint(x: 0.5, y: 1)
        bed.endPoint = CGPoint(x: 0.5, y: 0)
        bed.locations = [0, 0.62, 1]

        let base: RGBAColor
        let alphaScale: Double
        switch state {
        case .valid:
            base = spec.glass.exhaustedTrack
            alphaScale = 1
        case .stale:
            base = spec.glass.exhaustedTrack
            alphaScale = 0.58
        case .unknown:
            base = spec.glass.neutralTrack
            alphaScale = 1
        }

        // The V5 quota bed, mirrored from its CSS gradient: lighter at the top
        // edge (0.78) easing to the deepest black at the bottom (0.98). Layer
        // coordinates are unflipped, so startPoint y=1 is the top edge.
        bed.colors = [
            base.withAlpha(base.alpha * alphaScale * 0.78).cgColor,
            base.withAlpha(base.alpha * alphaScale * 0.94).cgColor,
            base.withAlpha(base.alpha * alphaScale * 0.98).cgColor,
        ]

        // Fine machined edges: a 1pt top highlight and a dark bottom rim, like
        // an inset slot. They stay inside the bed so nothing leaks at 2x/3x.
        let top = LayerSlot.named("envTop", in: parent)
        top.frame = CGRect(x: groove.minX, y: groove.maxY - 1,
                           width: groove.width, height: 1)
        top.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: state == .unknown ? 0.04 : 0.06)

        let bottom = LayerSlot.named("envBottom", in: parent)
        bottom.frame = CGRect(x: groove.minX, y: groove.minY, width: groove.width, height: 1)
        bottom.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: state == .unknown ? 0.35 : 0.7)
    }

    // MARK: - Nested fills

    /// Returns the nested lengths (outermost first), already chain-broken.
    @discardableResult
    private static func updateFills(_ parent: CALayer, spec: LaneRenderSpec, state: QuotaDisplayState) -> [CGFloat] {
        let fills = LayerSlot.named("fills", in: parent)
        fills.frame = CGRect(origin: .zero, size: spec.geometry.trackRect.size)
        fills.masksToBounds = true

        let fractions = spec.windows.map { $0.remainingFraction }
        let lengths = NestedGauge.nestedLengths(trackWidth: spec.geometry.fillBounds.width, remaining: fractions)
        let knownCount = spec.windows.enumerated().filter { !lengths[$0.offset].isNaN }.count
        let tierColors = spec.palette.tierColors(forWindowCount: knownCount)

        var slots: [String] = []
        var colorIndex = 0
        for (index, length) in lengths.enumerated() {
            guard !length.isNaN else { continue }   // broken chain: draw nothing
            let name = "fill\(index)"
            slots.append(name)
            let isInnermost = colorIndex == knownCount - 1
            let color = tierColors[min(colorIndex, tierColors.count - 1)]
            colorIndex += 1

            let fill = LayerSlot.named(name, in: fills, as: CAGradientLayer.self)
            let rect = spec.geometry.fillRect(forLength: length)
            fill.frame = rect
            fill.opacity = state == .stale ? 0.62 : 1
            applyFillGradient(fill, color: color, rank: knownCount <= 1 ? 1 : Double(colorIndex - 1) / Double(knownCount - 1),
                              isInnermost: isInnermost)
        }
        LayerSlot.reconcile(fills, keeping: slots)
        return lengths
    }

    /// The V5 fill language: a bright top bevel, a saturated middle band, a
    /// darker base. The innermost tier adds a white top edge so a glance can
    /// tell the two layers apart.
    static func applyFillGradient(_ layer: CAGradientLayer, color: RGBAColor, rank: Double, isInnermost: Bool) {
        layer.type = .axial
        layer.startPoint = CGPoint(x: 0.5, y: 1)
        layer.endPoint = CGPoint(x: 0.5, y: 0)
        layer.locations = [0, 0.18, 0.55, 1]
        let topWhite = 0.06 + 0.20 * rank
        let midAlpha = 0.52 + 0.34 * rank
        let lowAlpha = 0.40 + 0.45 * rank
        let bottomAlpha = 0.30 + 0.18 * rank
        layer.colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: min(topWhite, 0.32)),
            color.withAlpha(midAlpha).cgColor,
            color.withAlpha(lowAlpha).cgColor,
            color.scaled(by: 0.55).withAlpha(bottomAlpha).cgColor,
        ]
        layer.cornerRadius = isInnermost ? 1.5 : 0
    }

    // MARK: - Agent glass tint

    /// The agent theme colour, clipped to the real outer fill length: the
    /// used-up region stays black, and a zero-quota lane is not tinted.
    private static func updateTint(
        _ parent: CALayer,
        spec: LaneRenderSpec,
        state: QuotaDisplayState,
        outerLength: CGFloat?
    ) {
        let tint = LayerSlot.named("tint", in: parent)
        let bounds = spec.geometry.fillBounds
        tint.frame = bounds
        tint.masksToBounds = true

        let color = spec.glass.agentThemeColor
        let material = spec.glass.material
        let hasTint = state != .unknown && (outerLength ?? 0) > 0
        tint.isHidden = !hasTint
        guard hasTint else { return }

        // Clip to the outer fill's length from the anchor. The clip is a child
        // container whose content keeps full-lane coordinates, so the gradient
        // geometry matches the reference while the tint can never cover the
        // used-up (black) part of the lane.
        let fillLength = min(outerLength ?? 0, bounds.width)
        let clipRect = spec.geometry.growsTowardRight
            ? CGRect(x: 0, y: 0, width: fillLength, height: tint.bounds.height)
            : CGRect(x: tint.bounds.width - fillLength, y: 0, width: fillLength, height: tint.bounds.height)
        let clip = LayerSlot.named("tintClip", in: tint)
        clip.frame = clipRect
        clip.masksToBounds = true
        let contentFrame = CGRect(x: -clipRect.minX, y: 0, width: tint.bounds.width, height: tint.bounds.height)

        // Radial glass bloom, V5 `glass-tint`. Near-white tints are attenuated
        // so menu bar text and icons stay readable.
        let bloom = LayerSlot.named("tintBloom", in: clip, as: CAGradientLayer.self)
        bloom.type = .radial
        bloom.frame = contentFrame
        bloom.startPoint = CGPoint(x: 0.5, y: 0.42)
        bloom.endPoint = CGPoint(x: 0.5, y: 1.0)
        bloom.locations = [0, 0.38, 0.83, 1]
        let ceiling = legibilityCeiling(for: color)
        bloom.colors = [
            color.withAlpha(0.95).cgColor,
            color.withAlpha(0.72).cgColor,
            color.withAlpha(0.18).cgColor,
            color.withAlpha(0).cgColor,
        ]
        bloom.opacity = Float(min(1, material.agentThemeStrength * 0.35 * ceiling))

        // A white top bevel + soft tint falloff, V5's linear second layer.
        let linear = LayerSlot.named("tintLinear", in: clip, as: CAGradientLayer.self)
        linear.frame = contentFrame
        linear.type = .axial
        linear.startPoint = CGPoint(x: 0.5, y: 0)
        linear.endPoint = CGPoint(x: 0.5, y: 1)
        linear.locations = [0, 0.27, 1]
        linear.colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.08),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
            color.withAlpha(0.22).cgColor,
        ]
        linear.opacity = Float(min(1, material.agentThemeStrength * 0.5 * ceiling))

        // Ambient glow: the extra diffusion the user set to 0 in V5. Zero here
        // must NOT hide the tint above — that is the V4 bug this guards.
        let ambient = LayerSlot.named("tintAmbient", in: clip, as: CAGradientLayer.self)
        ambient.type = .radial
        ambient.frame = contentFrame
        ambient.startPoint = CGPoint(x: 0.44, y: 0.78)
        ambient.endPoint = CGPoint(x: 0.44, y: 1.45)
        ambient.locations = [0, 0.57, 1]
        ambient.colors = [
            color.withAlpha(0.84).cgColor,
            color.withAlpha(0.23).cgColor,
            color.withAlpha(0).cgColor,
        ]
        ambient.opacity = Float(min(1, material.ambientGlow * material.agentThemeStrength * 0.7))
        ambient.isHidden = material.ambientGlow <= 0.001

        if !ambient.isHidden, !spec.reduceMotion, spec.signal?.isRunning == true {
            if ambient.animation(forKey: "ambientDrift") == nil {
                let drift = CABasicAnimation(keyPath: "position.x")
                drift.fromValue = ambient.position.x - ambient.bounds.width * 0.03
                drift.toValue = ambient.position.x + ambient.bounds.width * 0.03
                drift.duration = 5.5
                drift.autoreverses = true
                drift.repeatCount = .infinity
                drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ambient.add(drift, forKey: "ambientDrift")
            }
        } else {
            ambient.removeAnimation(forKey: "ambientDrift")
        }

        LayerSlot.reconcile(tint, keeping: ["tintClip"])
        LayerSlot.reconcile(clip, keeping: ["tintBloom", "tintLinear", "tintAmbient"])
    }

    /// A near-white tint (Claude's `#FFFFFF`) is attenuated toward the ceiling
    /// so it cannot wash out the system's own white menu bar text. The stored
    /// colour is never modified — only the rendered opacity.
    static func legibilityCeiling(for color: RGBAColor) -> Double {
        let lum = color.luminance
        guard lum > 0.75 else { return 1 }
        return 1 - 0.45 * ((lum - 0.75) / 0.25)
    }

    // MARK: - End caps

    private static func updateCaps(
        _ parent: CALayer,
        spec: LaneRenderSpec,
        state: QuotaDisplayState,
        lengths: [CGFloat],
        scale: CGFloat
    ) {
        let caps = LayerSlot.named("caps", in: parent)
        caps.frame = CGRect(origin: .zero, size: spec.geometry.trackRect.size)
        caps.masksToBounds = true
        guard state != .unknown else {
            LayerSlot.reconcile(caps, keeping: [])
            return
        }

        let knownLengths = lengths.filter { !$0.isNaN }
        var slots: [String] = []
        for (index, length) in knownLengths.enumerated() {
            let name = "cap\(index)"
            slots.append(name)
            let cap = LayerSlot.named(name, in: caps)
            let fills = spec.palette.tierColors(forWindowCount: knownLengths.count)
            let color = fills[min(index, fills.count - 1)]
            let isInnermost = index == knownLengths.count - 1

            let rect = spec.geometry.fillRect(forLength: length)
            let width = capWidth
            let x = spec.geometry.growsTowardRight ? rect.maxX - width : rect.minX
            cap.frame = CGRect(x: x, y: rect.minY, width: width, height: rect.height)
            cap.backgroundColor = isInnermost
                ? CGColor(red: 1, green: 1, blue: 1, alpha: state == .stale ? 0.45 : 0.8)
                : color.withAlpha(state == .stale ? 0.4 : 0.66).cgColor
            if isInnermost, state == .valid {
                cap.shadowColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.5)
                cap.shadowOpacity = 0.6
                cap.shadowRadius = 2
                cap.shadowOffset = .zero
            } else {
                cap.shadowOpacity = 0
            }
            // Keep the seam crisp on Retina.
            cap.contentsScale = scale
        }
        LayerSlot.reconcile(caps, keeping: slots)
    }

    // MARK: - Baseline

    private static func updateBaseline(_ lane: CALayer, spec: LaneRenderSpec) {
        let marker = LayerSlot.named("baseline", in: lane)
        guard spec.glass.showsBaseline,
              let baseline = spec.baseline,
              baseline.selectedWindowIndex >= 0,
              baseline.selectedWindowIndex < spec.windows.count
        else {
            marker.isHidden = true
            return
        }
        let outer = Array(spec.windows[0..<baseline.selectedWindowIndex]).map { $0.remainingFraction }
        guard let length = QuotaPace.markerLength(
            trackWidth: spec.geometry.fillBounds.width,
            outerRemaining: outer,
            selectedExpectedRemaining: baseline.expectedRemainingFraction
        ) else {
            marker.isHidden = true
            return
        }
        marker.isHidden = false
        let width: CGFloat = 2
        let x = spec.geometry.growsTowardRight
            ? spec.geometry.fillBounds.minX + length - width / 2
            : spec.geometry.fillBounds.maxX - length - width / 2
        marker.frame = CGRect(x: x, y: spec.geometry.fillBounds.minY, width: width, height: spec.geometry.fillBounds.height)
        marker.backgroundColor = spec.palette.baseline.cgColor
    }

    private static func backingScale(for layer: CALayer) -> CGFloat {
        layer.contentsScale > 0 ? layer.contentsScale : (NSScreen.main?.backingScaleFactor ?? 2)
    }
}
