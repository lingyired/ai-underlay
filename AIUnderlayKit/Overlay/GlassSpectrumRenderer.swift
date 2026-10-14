import AppKit

/// The one and only running effect: a dense fine-ray light curtain with a
/// traveling light field and a soft specular crest, in the signal light colour.
///
/// Everything is Core Animation over **pre-rendered textures**: the ray curtain
/// is rasterised once per (size, colour, density) and cached, and motion is a
/// handful of transform/position animations on a few layers. There is no
/// per-frame CPU work, no shader, and no one-layer-per-ray. Ray density is a
/// texture property, never a layer count.
@MainActor
public enum GlassSpectrumRenderer {
    /// Animated layers per lane: three interleaved ray groups + two light
    /// fields. The budget is asserted in tests.
    public static let rayGroupCount = 3
    public static let maxAnimatedLayers = 6

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
        root.frame = CGRect(origin: .zero, size: spec.geometry.trackRect.size)
        root.masksToBounds = true

        guard running else {
            root.isHidden = true
            stopAnimations(root)
            return
        }
        root.isHidden = false

        let color = spec.glass.signalLights.light(for: spec.signal?.attention ?? .none)
        let density = spec.glass.material.rayDensity
        let grain = spec.glass.material.grain
        let size = spec.geometry.trackRect.size
        let scale = lane.contentsScale > 0 ? lane.contentsScale : (NSScreen.main?.backingScaleFactor ?? 2)
        let animated = !spec.reduceMotion

        var slots: [String] = []
        for group in 0..<rayGroupCount {
            let name = "rays\(group)"
            slots.append(name)
            let rays = LayerSlot.named(name, in: root)
            rays.frame = CGRect(origin: .zero, size: size)
            rays.contentsScale = scale
            rays.contents = RayTextureCache.image(
                width: size.width, height: size.height, scale: scale,
                group: group, groupCount: rayGroupCount,
                color: color, density: density, grain: grain
            )
            rays.opacity = 0.92
            if animated {
                ensureRayAnimation(rays, cycle: cycle, group: group, restart: restart)
            } else {
                rays.removeAnimation(forKey: "rayBreath")
                rays.transform = CATransform3DMakeScale(1, 0.92, 1)
            }
        }

        for (index, field) in LightFieldGeometry.racetrack(size: size, growsTowardRight: spec.geometry.growsTowardRight).enumerated() {
            let name = "field\(index)"
            slots.append(name)
            let layer = LayerSlot.named(name, in: root, as: CAGradientLayer.self)
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
                ensureFieldAnimation(layer, field: field, cycle: cycle, index: index, restart: restart)
            } else {
                layer.removeAnimation(forKey: "fieldTravel")
                layer.position.x = field.restX
            }
        }
        LayerSlot.reconcile(root, keeping: slots)
    }

    /// Stops every animation this renderer owns, so a disabled overlay or a
    /// Reduce Motion switch leaves nothing ticking.
    public static func stopAnimations(_ lane: CALayer) {
        guard let root = LayerSlot.root(named: "spectrum", in: lane) else { return }
        for layer in root.sublayers ?? [] {
            layer.removeAnimation(forKey: "rayBreath")
            layer.removeAnimation(forKey: "fieldTravel")
        }
    }

    // MARK: - Motion

    /// Each ray group pulses on the same cycle with a phase offset, so the
    /// curtain reads as waves travelling through the light field.
    private static func ensureRayAnimation(_ layer: CALayer, cycle: Double, group: Int, restart: Bool) {
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        let size = layer.bounds.size
        layer.position = CGPoint(x: size.width / 2, y: 0)
        layer.bounds = CGRect(origin: .zero, size: size)
        let existing = layer.animation(forKey: "rayBreath") as? CAKeyframeAnimation
        if !restart, existing?.duration == cycle { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        animation.values = [0.82, 1.0, 0.88, 0.82]
        animation.keyTimes = [0, 0.34, 0.72, 1]
        animation.duration = cycle
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.beginTime = CACurrentMediaTime() - cycle * Double(group) / Double(rayGroupCount)
        layer.add(animation, forKey: "rayBreath")
    }

    /// The traveling light field, mirrored when the lane grows leftward.
    private static func ensureFieldAnimation(_ layer: CAGradientLayer, field: LightField, cycle: Double, index: Int, restart: Bool) {
        let existing = layer.animation(forKey: "fieldTravel") as? CABasicAnimation
        let duration = cycle * field.cycleFactor
        if !restart, existing?.duration == duration { return }
        let travel = CABasicAnimation(keyPath: "position.x")
        travel.fromValue = field.fromX
        travel.toValue = field.toX
        travel.duration = duration
        travel.repeatCount = .infinity
        travel.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(travel, forKey: "fieldTravel")
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
            let rayHeight = height * CGFloat(0.20 + 0.50 * crest + 0.30 * focus)
            let alpha = min(0.96, 0.20 + 0.30 * crest + 0.46 * focus)
            let y = height - rayHeight

            drawRay(in: context, x: x, y: y, height: rayHeight, alpha: alpha, color: color)
        }

        if grain > 0.001 {
            drawGrain(in: context, width: width, height: height, intensity: grain)
        }

        return context.makeImage()
    }

    /// One fine luminous ray: a soft chromatic halo plus a bright core that
    /// whitens toward the bar's baseline.
    private static func drawRay(in context: CGContext, x: CGFloat, y: CGFloat, height: CGFloat, alpha: Double, color: RGBAColor) {
        let haloWidth: CGFloat = 4.2
        let halo = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.withAlpha(0).cgColor,
                color.withAlpha(alpha * 0.28).cgColor,
                color.withAlpha(alpha * 0.78).cgColor,
                color.withAlpha(alpha * 0.92).cgColor,
            ] as CFArray,
            locations: [0, 0.18, 0.64, 1]
        )
        if let halo {
            context.saveGState()
            context.clip(to: CGRect(x: x - haloWidth / 2, y: y, width: haloWidth, height: height))
            context.drawLinearGradient(halo, start: CGPoint(x: 0, y: y + height), end: CGPoint(x: 0, y: y), options: [])
            context.restoreGState()
        }

        let coreWidth: CGFloat = 1.16
        let core = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.withAlpha(0).cgColor,
                color.withAlpha(alpha * 0.42).cgColor,
                CGColor(red: 1, green: 1, blue: 1, alpha: min(0.90, alpha * 0.76)),
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
