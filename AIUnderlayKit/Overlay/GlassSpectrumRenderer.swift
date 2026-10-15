import AppKit

/// The one and only running effect: a dense fine-ray light curtain with a
/// traveling light field and a soft specular crest, in the signal light colour.
/// Like the V5 lab, the rays stand on the strip's bottom edge — the bases form
/// one baseline and only the tips wave.
///
/// Everything is Core Animation over **pre-rendered textures**: the ray curtain
/// is rasterised once per (size, colour, density) and cached, and motion is a
/// handful of transform/position animations on a few layers. There is no
/// per-frame CPU work, no shader, and no one-layer-per-ray. Ray density is a
/// texture property, never a layer count.
@MainActor
public enum GlassSpectrumRenderer {
    /// Ray groups per spectrum. Each group needs two layers: the weak static
    /// bed and its bright, mask-windowed copy that shares the same cached
    /// texture. Density is a texture property — never a layer count.
    public static let rayGroupCount = 3
    /// Continuous per-lane animation budget for the phase-B design: three
    /// bright peak copies, the three window masks and the two wide fields.
    /// The static bed deliberately does not animate.
    public static let maxAnimatedLayers = 8

    /// First-round calibration of the weak static bed. The bed keeps the ray
    /// structure readable without the always-on comb look; brightness now comes
    /// from the travelling peak window.
    public static let bedOpacity: Float = 0.16
    /// Bright peak copies reuse the same texture at a higher opacity. The local
    /// mask decides where it shows, so off-peak rays fade toward the bed.
    public static let peakOpacity: Float = 0.78
    /// A fresh layer tree (tests, offline preview).
    public static func render(_ spec: LaneRenderSpec, running: Bool, cycle: Double, restart: Bool) -> CALayer {
        let lane = CALayer()
        lane.name = "lane"
        lane.frame = spec.geometry.trackRect
        lane.masksToBounds = true
        update(into: lane, spec: spec, running: running, cycle: cycle, restart: restart)
        LayerSlot.reconcileLane(lane)
        return lane
    }

    public static func update(into lane: CALayer, spec: LaneRenderSpec, running: Bool, cycle: Double, restart: Bool) {
        let root = LayerSlot.named("spectrum", in: lane)
        // The curtain covers this provider's own fill area, never the other
        // side of a dual layout: one provider's light must not wash over the
        // neighbour's quota. In single layout the fill is the whole track, so
        // this is the full-band look.
        let region = spec.geometry.localFillBounds
        root.frame = region
        root.masksToBounds = true

        // A mask must not also be a sublayer, so it is created detached and
        // reused through `root.mask` across unknown ↔ valid changes.
        let clip: CALayer
        if let existing = root.mask {
            clip = existing
        } else {
            clip = CALayer()
            clip.name = "quotaClip"
            clip.backgroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        if QuotaDisplayState.resolve(windows: spec.windows) == .unknown {
            // Full coverage preserves unknown's neutral track and mask identity.
            clip.frame = root.bounds
        } else {
            // The Lane region is not the quota's remaining length. A full-height
            // peak or halo must never relight the known-exhausted black area, so
            // the whole spectrum subtree is clipped to the real outermost length
            // from NestedGauge. Static, lane-local, mirroring `fillRect`.
            let fractions = spec.windows.map(\.remainingFraction)
            let outerRemaining = NestedGauge.nestedLengths(
                trackWidth: spec.geometry.fillBounds.width, remaining: fractions
            ).first ?? 0
            // Clip in *spectrum root* coordinates. `fillRect` returns global
            // screen coordinates (trackRect carries the screen origin, e.g.
            // y=1122), while the spectrum root is the lane-local fillBounds.
            // Subtracting fillBounds' origin maps global → root exactly.
            clip.frame = spec.geometry.fillRect(forLength: outerRemaining)
                .offsetBy(dx: -spec.geometry.fillBounds.minX, dy: -spec.geometry.fillBounds.minY)
        }
        root.mask = clip

        guard running else {
            root.isHidden = true
            stopAnimations(root)
            return
        }
        root.isHidden = false

        let color = spec.glass.signalLights.light(for: spec.signal?.attention ?? .none)
        let density = spec.glass.material.rayDensity
        let grain = spec.glass.material.grain
        let size = region.size
        let scale = lane.contentsScale > 0 ? lane.contentsScale : (NSScreen.main?.backingScaleFactor ?? 2)
        let animated = !spec.reduceMotion

        // The curtain needs something dark to stand on. The band window sits
        // *below* the system menu bar, so everything we draw is seen through
        // the bar's own material and loses roughly 40% of its contrast; white
        // rays over a light quota fill then read as a faint texture. This bed
        // is the V5 dark base and it is static — Reduce Motion keeps it.
        let scrim = LayerSlot.named("scrim", in: root, as: CAGradientLayer.self)
        scrim.frame = CGRect(origin: .zero, size: size)
        scrim.type = .axial
        scrim.startPoint = CGPoint(x: 0.5, y: 0)
        scrim.endPoint = CGPoint(x: 0.5, y: 1)
        scrim.colors = [
            CGColor(red: 0, green: 0, blue: 0, alpha: 0),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.45),
        ]
        scrim.locations = [0.18, 1]

        var slots: [String] = ["scrim", "quotaClip"]
        let texture = { (group: Int) -> CGImage? in
            RayTextureCache.image(
                width: size.width, height: size.height, scale: scale,
                group: group, groupCount: rayGroupCount,
                color: color, density: density, grain: grain
            )
        }

        // Three weak static bed groups. They never animate: the whole point of
        // phase B is that the eye follows the moving local peak, not a
        // permanently bright curtain.
        for group in 0..<rayGroupCount {
            let name = "rays\(group)"
            slots.append(name)
            let rays = LayerSlot.named(name, in: root)
            rays.frame = CGRect(origin: .zero, size: size)
            rays.contentsScale = scale
            rays.contents = texture(group)
            rays.opacity = bedOpacity
            rays.removeAnimation(forKey: "rayBreath")
        }

        let fields = LightFieldGeometry.racetrack(size: size, growsTowardRight: spec.geometry.growsTowardRight)
        let model = SpectrumPhaseGeometry(
            size: size, fields: fields, cycle: cycle, growsTowardRight: spec.geometry.growsTowardRight
        )
        let travels = spec.showsTravelingLight && animated
        let origin = CACurrentMediaTime()

        for (index, field) in fields.enumerated() {
            let name = "field\(index)"
            slots.append(name)
            let layer = LayerSlot.named(name, in: root, as: CAGradientLayer.self)

            // The wide sheen and the local peak share one geometry, one
            // direction and one time origin. Turning the traveller off hides
            // the full-width sheen entirely; the fixed local energy window
            // survives only in the bright-ray mask, so no broad sheen remains.
            guard spec.showsTravelingLight else {
                layer.isHidden = true
                layer.removeAnimation(forKey: "fieldTravel")
                continue
            }
            layer.isHidden = false

            layer.frame = field.frame
            layer.type = .axial
            layer.startPoint = CGPoint(x: 0, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 0.5)
            let stops = field.stops.map { pattern -> CGColor in
                switch pattern {
                case .clear: return color.withAlpha(0).cgColor
                case .tint(let alpha): return color.withAlpha(alpha).cgColor
                case .white(let alpha): return CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
                }
            }
            layer.colors = stops
            layer.locations = field.locations.map { NSNumber(value: $0) }
            layer.opacity = Float(field.opacity)
            if animated {
                ensureFieldAnimation(layer, field: field, cycle: cycle, restart: restart, origin: origin)
            } else {
                layer.removeAnimation(forKey: "fieldTravel")
                layer.position.x = size.width / 2
            }
        }

        // Three bright copies of the same textures, each clipped by a real
        // moving `mask` (not an overlay) so off-window rays fade to the weak
        // bed. The mask spans the whole lane and is translated, so its centre
        // always coincides with its light-field centre.
        for group in 0..<rayGroupCount {
            let name = "peak\(group)"
            slots.append(name)
            let peaks = LayerSlot.named(name, in: root)
            peaks.frame = CGRect(origin: .zero, size: size)
            peaks.contentsScale = scale
            peaks.contents = texture(group)
            peaks.opacity = peakOpacity
            anchorToBottom(peaks)
            if animated {
                ensurePeakBreath(peaks, cycle: cycle, group: group, origin: origin)
            } else {
                peaks.removeAnimation(forKey: "peakBreath")
                peaks.transform = CATransform3DMakeScale(1, 0.97, 1)
            }

            let mask = attachPeakMask(on: peaks, named: peakMaskKey(group: group))
            mask.contentsScale = scale
            mask.type = .axial
            mask.startPoint = CGPoint(x: 0, y: 0.5)
            mask.endPoint = CGPoint(x: 1, y: 0.5)
            applyPeakMask(mask, window: model.primary.window, laneWidth: size.width, height: size.height)
            if travels {
                ensurePeakTravel(mask, journey: model.primary, cycle: cycle, restart: restart, origin: origin)
            } else {
                mask.removeAnimation(forKey: "peakTravel")
                _ = applyMaskPhase(mask, journey: model.parkedJourneys[0], phase: 0)
            }
        }

        LayerSlot.reconcile(root, keeping: slots)
    }

    /// Stops every animation this renderer owns, so a disabled overlay or a
    /// Reduce Motion switch leaves nothing ticking.
    public static func stopAnimations(_ lane: CALayer) {
        guard let root = LayerSlot.root(named: "spectrum", in: lane) else { return }
        stopSpectrumAnimations(root)
    }

    /// Recursively clears every animation key this renderer enables, including
    /// the peak masks (which are `mask` children, not `sublayers`).
    static func stopSpectrumAnimations(_ root: CALayer) {
        var stack = [root]
        while let layer = stack.popLast() {
            layer.removeAnimation(forKey: "rayBreath")
            layer.removeAnimation(forKey: "peakBreath")
            layer.removeAnimation(forKey: "peakTravel")
            layer.removeAnimation(forKey: "fieldTravel")
            if let mask = layer.mask {
                stack.append(mask)
            }
            stack.append(contentsOf: layer.sublayers ?? [])
        }
    }

    static func peakMaskKey(group: Int) -> String { "peakmask\(group)" }

    /// Find-or-create the `mask` child of a bright peak layer. `LayerSlot.named`
    /// keeps identity across updates, but adding a fresh mask through it puts
    /// the layer in `sublayers`; assigning `mask` afterwards detaches it again,
    /// so the mask never shows up as a normal child or in diagnostics sublayers.
    /// Returns a mask layer that is already attached via `peaks.mask`. Any
    /// previous mask is detached so the tree never accumulates orphans.
    private static func attachPeakMask(on peaks: CALayer, named name: String) -> CAGradientLayer {
        if let existing = peaks.mask as? CAGradientLayer, existing.name == name {
            return existing
        }
        peaks.mask?.removeFromSuperlayer()
        peaks.mask = nil
        let mask = CAGradientLayer()
        mask.name = name
        peaks.mask = mask
        return mask
    }

    // MARK: - Motion

    /// The bright peak copies keep the bottom anchor and only breathe in
    /// height. The horizontal window does the travelling, so this never turns
    /// back into the old all-over compression of a fully bright curtain.
    private static func ensurePeakBreath(_ layer: CALayer, cycle: Double, group: Int, origin: CFTimeInterval) {
        anchorToBottom(layer)
        let existing = layer.animation(forKey: "peakBreath") as? CAKeyframeAnimation
        guard existing?.duration != cycle else { return }
        let localOrigin = layer.convertTime(origin, from: nil)
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        animation.values = [0.94, 1.0, 0.97, 0.94]
        animation.keyTimes = [0, 0.34, 0.72, 1]
        animation.duration = cycle
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.beginTime = localOrigin
        animation.timeOffset = cycle * (existing.map {
            phaseCarry(from: $0, now: localOrigin)
        } ?? (Double(group) / Double(rayGroupCount) * 0.5))
        layer.add(animation, forKey: "peakBreath")
    }

    private static func anchorToBottom(_ layer: CALayer) {
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        let size = layer.bounds.size
        layer.position = CGPoint(x: size.width / 2, y: 0)
        layer.bounds = CGRect(origin: .zero, size: size)
    }

    /// A local energy window centered at zero, translated to the field centre.
    static func applyPeakMask(_ mask: CAGradientLayer, window: SpectrumPhaseGeometry.PeakWindow, laneWidth: CGFloat, height: CGFloat) {
        let lane = max(1, laneWidth)
        let core = min(window.width, lane)
        mask.bounds = CGRect(x: 0, y: 0, width: core, height: height)
        mask.position = CGPoint(x: 0, y: height / 2)
        mask.colors = SpectrumPhaseGeometry.windowAlphas.map {
            CGColor(red: 0, green: 0, blue: 0, alpha: $0)
        }
        mask.locations = SpectrumPhaseGeometry.windowLocations.map { NSNumber(value: $0) }
    }

    @discardableResult
    private static func applyMaskPhase(_ mask: CAGradientLayer, journey: SpectrumPhaseGeometry.PeakJourney, phase: Double) -> CGFloat {
        let position = journey.offset(at: phase)
        var transform = CATransform3DIdentity
        transform.m41 = position
        mask.transform = transform
        return position
    }

    /// The travelling light field, mirrored when the lane grows leftward.
    /// `origin` is the one time origin shared by every spectrum animation in
    /// this update, so the field and its mask stay in lockstep.
    private static func ensureFieldAnimation(
        _ layer: CAGradientLayer, field: LightField, cycle: Double, restart: Bool, origin: CFTimeInterval
    ) {
        let duration = cycle * field.cycleFactor
        let existing = layer.animation(forKey: "fieldTravel") as? CABasicAnimation
        guard restart || existing?.duration != duration
            || existing?.fromValue as? CGFloat != field.fromX
            || existing?.toValue as? CGFloat != field.toX else { return }
        let localOrigin = layer.convertTime(origin, from: nil)
        let carry = phaseCarry(from: existing, now: localOrigin)
        let travel = CABasicAnimation(keyPath: "position.x")
        travel.fromValue = field.fromX
        travel.toValue = field.toX
        travel.duration = duration
        travel.repeatCount = .infinity
        travel.timingFunction = CAMediaTimingFunction(name: .linear)
        travel.beginTime = localOrigin
        travel.timeOffset = carry * duration
        layer.add(travel, forKey: "fieldTravel")
    }

    /// The local peak window shares the field's endpoints, duration, direction
    /// and time origin, so the mask can never drift away from the light.
    private static func ensurePeakTravel(
        _ mask: CAGradientLayer, journey: SpectrumPhaseGeometry.PeakJourney, cycle: Double, restart: Bool, origin: CFTimeInterval
    ) {
        let duration = cycle * journey.cycleFactor
        let existing = mask.animation(forKey: "peakTravel") as? CABasicAnimation
        guard restart || existing?.duration != duration
            || existing?.fromValue as? CGFloat != journey.from
            || existing?.toValue as? CGFloat != journey.to else { return }
        let localOrigin = mask.convertTime(origin, from: nil)
        let carry = phaseCarry(from: existing, now: localOrigin)
        let travel = CABasicAnimation(keyPath: "transform.translation.x")
        travel.fromValue = journey.from
        travel.toValue = journey.to
        travel.duration = duration
        travel.repeatCount = .infinity
        travel.timingFunction = CAMediaTimingFunction(name: .linear)
        travel.beginTime = localOrigin
        travel.timeOffset = carry * duration
        mask.add(travel, forKey: "peakTravel")
    }

    /// Normalised phase carried across a duration change so a live floor
    /// adjustment re-times from where the animation already is. The layer keeps
    /// its identity; only the timeline is rewritten.
    static func phaseCarry(from animation: CAAnimation?, now: CFTimeInterval) -> Double {
        guard let animation, animation.duration > 0 else { return 0 }
        let previous = animation.duration
        let begin = animation.beginTime == 0 ? now : animation.beginTime
        let elapsed = now - begin + animation.timeOffset
        let wrapped = elapsed.truncatingRemainder(dividingBy: previous)
        return ((wrapped / previous) + 1).truncatingRemainder(dividingBy: 1)
    }

    /// Samples horizontal peak motion for offline tests/preview. The vertical
    /// breath is held at 0.97 to isolate the moving brightness window; live CA
    /// composition is validated separately. Never call this on the live tree.
    static func applySampledPhase(
        into lane: CALayer,
        spec: LaneRenderSpec,
        cycle: Double,
        phase: Double
    ) {
        guard let root = LayerSlot.root(named: "spectrum", in: lane) else { return }
        guard spec.signal?.isRunning == true, !spec.reduceMotion else {
            stopSpectrumAnimations(root)
            return
        }
        let region = spec.geometry.localFillBounds
        let size = region.size
        let fields = LightFieldGeometry.racetrack(size: size, growsTowardRight: spec.geometry.growsTowardRight)
        let model = SpectrumPhaseGeometry(
            size: size, fields: fields, cycle: cycle, growsTowardRight: spec.geometry.growsTowardRight
        )
        let travels = spec.showsTravelingLight
        let sample = model.sample(at: phase)
        let journey = travels ? model.primary : model.parkedJourneys[0]
        let journeyPhase = travels ? phase : 0

        for (index, field) in fields.enumerated() {
            guard let layer = root.sublayers?.first(where: { $0.name == "field\(index)" }) else { continue }
            layer.removeAnimation(forKey: "fieldTravel")
            layer.position.x = travels ? sample.lightFieldOffsets[index] : size.width / 2
        }

        for group in 0..<rayGroupCount {
            let peak = LayerSlot.named("peak\(group)", in: root)
            peak.removeAnimation(forKey: "peakBreath")
            peak.transform = CATransform3DMakeScale(1, 0.97, 1)
            guard let gradient = peak.mask as? CAGradientLayer else { continue }
            gradient.removeAnimation(forKey: "peakTravel")
            _ = applyMaskPhase(gradient, journey: journey, phase: journeyPhase)
        }
    }

    // MARK: - Light field geometry (pure)

    enum StopPattern: Equatable {
        case clear
        case tint(Double)
        case white(Double)
    }

    struct LightField: Equatable {
        var frame: CGRect
        var stops: [StopPattern]
        var locations: [Double]
        var opacity: Double
        var fromX: CGFloat
        var toX: CGFloat
        var restX: CGFloat
        var cycleFactor: Double
    }

    enum LightFieldGeometry {
        /// Two fields at different speeds (and mirrored directions), matching
        /// the reference's primary cursor + secondary reflected cursor.
        static func racetrack(size: CGSize, growsTowardRight: Bool) -> [LightField] {
            let width = max(size.width, 1)
            let primaryWidth = min(width, max(140, width * 0.42))
            let secondaryWidth = min(width, max(90, width * 0.26))

            func travel(_ fieldWidth: CGFloat, forward: Bool) -> (from: CGFloat, to: CGFloat, rest: CGFloat) {
                let leadingStart: CGFloat = -fieldWidth / 2
                let leadingEnd = width + fieldWidth / 2
                let start = growsTowardRight == forward ? leadingStart : leadingEnd
                let end = growsTowardRight == forward ? leadingEnd : leadingStart
                return (start, end, start)
            }

            let primary = travel(primaryWidth, forward: true)
            let secondary = travel(secondaryWidth, forward: false)
            return [
                LightField(
                    frame: CGRect(x: 0, y: 0, width: primaryWidth, height: size.height),
                    stops: [.clear, .tint(0.10), .white(0.09), .tint(0.30), .clear],
                    locations: [0, 0.22, 0.5, 0.78, 1],
                    opacity: 0.95,
                    fromX: primary.from, toX: primary.to, restX: primary.rest,
                    cycleFactor: 1.0
                ),
                LightField(
                    frame: CGRect(x: 0, y: 0, width: secondaryWidth, height: size.height),
                    stops: [.clear, .tint(0.07), .tint(0.16), .clear],
                    locations: [0, 0.3, 0.7, 1],
                    opacity: 0.7,
                    fromX: secondary.from, toX: secondary.to, restX: secondary.rest,
                    cycleFactor: 1.7
                ),
            ]
        }
    }
}

/// Deterministic ray-curtain textures, cached per (size, colour, density).
/// The texture is the density: 100% means "clearly visible rays at 30–34pt",
/// and it costs one bitmap, not one layer per ray.
@MainActor
enum RayTextureCache {
    private static var cache: [String: CGImage] = [:]
    private static var order: [String] = []
    private static let limit = 12

    static func image(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        group: Int,
        groupCount: Int,
        color: RGBAColor,
        density: Double,
        grain: Double
    ) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let key = "\(Int(width.rounded()))x\(Int(height.rounded()))@\(scale)g\(group)/\(groupCount)"
            + "|\(color.hexString)|\(Int((density * 100).rounded()))|\(Int((grain * 100).rounded()))"
        if let cached = cache[key] { return cached }

        guard let image = draw(width: width, height: height, scale: scale, group: group, groupCount: groupCount,
                               color: color, density: density, grain: grain) else { return nil }
        cache[key] = image
        order.append(key)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        return image
    }

    private static func draw(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        group: Int,
        groupCount: Int,
        color: RGBAColor,
        density: Double,
        grain: Double
    ) -> CGImage? {
        let pixelWidth = max(1, Int((width * scale).rounded()))
        let pixelHeight = max(1, Int((height * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)

        // The V5 density curve: 100% is roughly 1.8 rays per 8.5pt — clearly
        // visible on a 30pt strip; 0% still leaves a sparse curtain.
        let densityBoost = 0.55 + density * 1.25
        let rayCount = max(24, Int((width / 8.5 * densityBoost).rounded()))

        for index in group..<rayCount where index % groupCount == group {
            let u = (CGFloat(index) + 0.5) / CGFloat(rayCount)
            let x = u * width
            let wave1 = 0.5 + 0.5 * sin(Double(u) * .pi * 4.1 + Double(index) * 0.072)
            let wave2 = 0.5 + 0.5 * sin(Double(u) * .pi * 2.4 + Double(index) * 0.27)
            let crest = 0.61 * wave1 + 0.39 * wave2
            // A static focus profile keeps the curtain from looking like a
            // comb; the moving field adds the rest of the travelling light.
            let focus = max(exp(-pow((Double(u) - 0.30) / 0.16, 2)),
                            0.6 * exp(-pow((Double(u) - 0.74) / 0.20, 2)))
            // Taller and more opaque than the browser lab's canvas pass: the
            // native band is composited under the system menu bar material,
            // which costs roughly 40% of the contrast we draw.
            let rayHeight = height * CGFloat(0.32 + 0.48 * crest + 0.34 * focus)
            let alpha = min(1, 0.46 + 0.36 * crest + 0.42 * focus)
            // The V5 curtain stands on the strip: every ray's base sits on the
            // bottom edge (Quartz y = 0), so only the tips wave. Starting at
            // `height - rayHeight` instead would hang the curtain from the top
            // edge and put the ragged hem at the bottom.
            let base: CGFloat = 0

            drawRay(in: context, x: x, y: base, height: rayHeight, alpha: alpha, color: color)
        }

        if grain > 0.001 {
            drawGrain(in: context, width: width, height: height, intensity: grain)
        }

        return context.makeImage()
    }

    /// One fine luminous ray: a soft chromatic halo plus a bright core that
    /// whitens toward the baseline the ray stands on.
    private static func drawRay(in context: CGContext, x: CGFloat, y: CGFloat, height: CGFloat, alpha: Double, color: RGBAColor) {
        let haloWidth: CGFloat = 4.2
        let halo = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.withAlpha(0).cgColor,
                color.withAlpha(alpha * 0.34).cgColor,
                color.withAlpha(alpha * 0.86).cgColor,
                color.withAlpha(alpha * 0.98).cgColor,
            ] as CFArray,
            locations: [0, 0.18, 0.64, 1]
        )
        if let halo {
            context.saveGState()
            context.clip(to: CGRect(x: x - haloWidth / 2, y: y, width: haloWidth, height: height))
            context.drawLinearGradient(halo, start: CGPoint(x: 0, y: y + height), end: CGPoint(x: 0, y: y), options: [])
            context.restoreGState()
        }

        let coreWidth: CGFloat = 1.3
        let core = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.withAlpha(0).cgColor,
                color.withAlpha(min(1, alpha * 0.5)).cgColor,
                CGColor(red: 1, green: 1, blue: 1, alpha: min(1, alpha)),
            ] as CFArray,
            locations: [0, 0.5, 1]
        )
        if let core {
            context.saveGState()
            context.clip(to: CGRect(x: x - coreWidth / 2, y: y, width: coreWidth, height: height))
            context.drawLinearGradient(core, start: CGPoint(x: 0, y: y + height), end: CGPoint(x: 0, y: y), options: [])
            context.restoreGState()
        }
    }

    /// Optional frosted speckle. Default grain is 0 — no noise unless asked.
    private static func drawGrain(in context: CGContext, width: CGFloat, height: CGFloat, intensity: Double) {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFF) / 65535
        }
        let step: CGFloat = 2
        let alpha = 0.05 + intensity * 0.10
        var y: CGFloat = 0
        while y < height {
            var x: CGFloat = 0
            while x < width {
                let value = next()
                if value > 0.72 {
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha * (value - 0.72) / 0.28))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                } else if value < 0.18 {
                    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: alpha * (0.18 - value) / 0.18))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
                x += step
            }
            y += step
        }
    }
}

/// Pure, nonisolated geometry for the deterministic peak phase sampler. Shared
/// by the live Core Animation timelines and the offline rasteriser so a frozen
/// frame and the running animation can never disagree about where the peak is.
///
/// Deliberately outside `@MainActor GlassSpectrumRenderer` so it stays a plain
/// `Sendable` value with no actor-isolated members.
struct SpectrumPhaseGeometry: Sendable {
    static let windowLocations: [Double] = [0, 0.25, 0.5, 0.75, 1]
    static let windowAlphas: [Double] = [0, 0.15, 1, 0.15, 0]
    /// Window plateau as a fraction of the visible lane width, clamped to the
    /// plan's 20%–32% range; the secondary reflection is narrower and weaker.
    static let primaryPeakWidthFraction: CGFloat = 0.26
    static let secondaryPeakWidthFraction: CGFloat = 0.18
    /// Fraction of the window spent fading at each edge of the travelling mask.
    static let peakEdgeFadeFraction: CGFloat = 0.15

    struct PeakWindow: Equatable, Sendable {
        var center: CGFloat
        var width: CGFloat

        func sample(offset: CGFloat) -> PeakWindowSample {
            PeakWindowSample(offset: offset, alphaAtOffset: 1, window: width)
        }
    }

    struct PeakWindowSample: Equatable, Sendable {
        var offset: CGFloat
        var alphaAtOffset: Double
        var window: CGFloat
    }

    /// One peak's travel: the same endpoints, duration and direction as its
    /// light field, so a positive phase advances mask and field together.
    struct PeakJourney: Equatable, Sendable {
        var from: CGFloat
        var to: CGFloat
        var cycleFactor: Double
        var window: PeakWindow
        /// True when increasing phase moves toward the growing edge.
        var travelsTowardLeadingEdge: Bool

        func offset(at phase: Double) -> CGFloat {
            let wrapped = phase.truncatingRemainder(dividingBy: 1)
            let normalised = wrapped < 0 ? wrapped + 1 : wrapped
            return from + (to - from) * CGFloat(normalised)
        }

        func sample(at phase: Double) -> PeakWindowSample {
            window.sample(offset: offset(at: phase))
        }
    }

    struct PeakSample: Equatable, Sendable {
        var primary: PeakWindowSample
        var secondary: PeakWindowSample
        /// Wide light-field centres; when travelling is on these coincide with
        /// the mask offsets above.
        var lightFieldOffsets: [CGFloat]
    }

    var laneWidth: CGFloat
    var primary: PeakJourney
    var secondary: PeakJourney
    var cycle: Double

    init(size: CGSize, fields: [GlassSpectrumRenderer.LightField], cycle: Double, growsTowardRight: Bool) {
        let lane = max(1, size.width)
        laneWidth = lane
        self.cycle = cycle
        func plateau(_ fraction: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(lane * fraction, lane * lower), lane * upper)
        }
        let primaryWindow = PeakWindow(
            center: 0,
            width: plateau(Self.primaryPeakWidthFraction, lower: 0.20, upper: 0.32)
        )
        let secondaryWindow = PeakWindow(
            center: 0,
            width: plateau(Self.secondaryPeakWidthFraction, lower: 0.14, upper: 0.24)
        )
        let primaryField = fields.first
        let secondaryField = fields.count > 1 ? fields[1] : primaryField
        primary = PeakJourney(
            from: primaryField?.fromX ?? 0,
            to: primaryField?.toX ?? lane,
            cycleFactor: primaryField?.cycleFactor ?? 1,
            window: primaryWindow,
            travelsTowardLeadingEdge: growsTowardRight
        )
        secondary = PeakJourney(
            from: secondaryField?.fromX ?? lane,
            to: secondaryField?.toX ?? 0,
            cycleFactor: secondaryField?.cycleFactor ?? 1.7,
            window: secondaryWindow,
            travelsTowardLeadingEdge: !growsTowardRight
        )
    }

    var journeys: [PeakJourney] { [primary, secondary] }

    func sample(at phase: Double) -> PeakSample {
        PeakSample(
            primary: primary.sample(at: phase / primary.cycleFactor),
            secondary: secondary.sample(at: phase / secondary.cycleFactor),
            lightFieldOffsets: [primary.offset(at: phase / primary.cycleFactor),
                               secondary.offset(at: phase / secondary.cycleFactor)]
        )
    }

    /// Both peaks parked on the lane centre: a fixed local undulation with no
    /// horizontal crossing. Used when `showsTravelingLight` is off and when
    /// Reduce Motion freezes the lane.
    var parkedJourneys: [PeakJourney] {
        let centre = laneWidth / 2
        return journeys.map { journey in
            PeakJourney(
                from: centre,
                to: centre,
                cycleFactor: journey.cycleFactor,
                window: journey.window,
                travelsTowardLeadingEdge: journey.travelsTowardLeadingEdge
            )
        }
    }

    func maskAlpha(at x: CGFloat, phase: Double) -> Double {
        Self.rampAlpha(x, sample: primary.sample(at: phase / primary.cycleFactor))
    }

    static func rampAlpha(_ x: CGFloat, sample: PeakWindowSample) -> Double {
        let u = Double((x - sample.offset) / max(1, sample.window)) + 0.5
        guard u >= 0, u <= 1 else { return 0 }
        for index in 1..<windowLocations.count where u <= windowLocations[index] {
            let start = windowLocations[index - 1]
            let progress = (u - start) / (windowLocations[index] - start)
            return windowAlphas[index - 1] + (windowAlphas[index] - windowAlphas[index - 1]) * progress
        }
        return 0
    }
}
