import AppKit

/// The one and only running effect: a dense fine-ray light curtain whose
/// individual rays rise and fall with a travelling wave, in the signal light
/// colour. Like the V5 lab, the rays stand on the strip's bottom edge — the
/// bases form one baseline and only the tips wave.
///
/// ## How the motion is produced
///
/// The ray *shape* is a function of time, not a static texture that gets
/// scaled: `SpectrumWaveModel` samples every ray at a phase, and the renderer
/// rasterises a short sequence of those phases (`framesPerCycle`, 12–24). Core
/// Animation then plays that sequence with a discrete keyframe animation on
/// `contents`, so the wave runs in the render server with no per-frame CPU
/// work and no timer in the app.
///
/// This is deliberately the V5 lab's low cadence rather than 60 fps: V5
/// repaints its canvas about every 90 ms ("the amplitude change, not a high
/// framerate, makes Running recognizable"). A half-width lane plays 24 frames
/// per 0.70 Hz cycle (~17 fps) and a wide single-bar lane still plays 16
/// (~11 fps), because the frame count is capped by a bitmap budget. A lane
/// therefore needs **one** animated layer: no layer per ray, no shader, no
/// display link.
@MainActor
public enum GlassSpectrumRenderer {
    /// Frames per cycle for a half-width lane. A 0.70 Hz cycle over 24 frames
    /// is ~17 fps: smooth enough for the ray height to read as a wave, cheap
    /// enough to stay well inside the byte budget.
    public static let nominalFramesPerCycle = 24
    /// Never fewer than this: below it the wave reads as stepping rather than
    /// flowing.
    public static let minimumFramesPerCycle = 12
    /// The most frames a single cycle ever holds, even on a tiny lane.
    public static let maximumFramesPerCycle = 24
    /// The cadence the frame count aims for. A faster tempo gets fewer frames
    /// rather than more refreshes: the wave reads as motion well below 60 fps,
    /// and the render server should not be asked for a new frame every 16 ms.
    public static let referenceFramesPerSecond = 18
    /// Frame counts are rounded to this step, so dragging the tempo slider
    /// does not rebuild the sequence for every in-between value.
    public static let frameCountStep = 4
    /// One sequence's bitmap budget. A wide single-bar lane is ~983 KiB per
    /// frame, so a 2048 pt lane lands on 16 frames and a half-width lane on 24.
    public static let maxSequenceBytes = 16 * 1024 * 1024
    /// Continuous per-lane animation budget: the curtain plus the attention
    /// band's own layers. Far below the old bed/peak/mask/field tree.
    public static let maxAnimatedLayers = 4

    /// Animation key owned by this renderer.
    static let curtainKey = "curtainFrames"

    /// The keyframe timeline for a phase sequence.
    ///
    /// A `contents` keyframe animation needs the timeline to close at one whole
    /// cycle: with the last key time below `1.0` Core Animation falls back to
    /// the *model* value for the remaining stretch, so the last frame is never
    /// shown and whichever frame precedes it holds for two steps — a visible
    /// hitch once per cycle. Closing the timeline with the first phase again
    /// gives every frame exactly one step.
    static func curtainKeyframeTimeline(frames: [CGImage]) -> (values: [CGImage], keyTimes: [NSNumber]) {
        guard let first = frames.first else { return ([], []) }
        let values = frames + [first]
        let keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        return (values, keyTimes)
    }

    // MARK: - Sizing

    public static func framesPerCycle(
        width: CGFloat, height: CGFloat, scale: CGFloat, cycle: Double = 1 / SpectrumRhythm.floorFrequencyHz
    ) -> Int {
        let bytes = pixelByteCount(width: width, height: height, scale: scale)
        let affordable = bytes > 0 ? maxSequenceBytes / bytes : nominalFramesPerCycle
        let cadence = cycle.isFinite && cycle > 0
            ? Int((cycle * Double(referenceFramesPerSecond)).rounded())
            : nominalFramesPerCycle
        let ceiling = min(maximumFramesPerCycle, max(minimumFramesPerCycle, min(affordable, cadence)))
        let rounded = Int((Double(ceiling) / Double(frameCountStep)).rounded()) * frameCountStep
        return min(ceiling, max(minimumFramesPerCycle, rounded))
    }

    static func pixelByteCount(width: CGFloat, height: CGFloat, scale: CGFloat) -> Int {
        guard width > 0, height > 0, scale > 0 else { return 0 }
        let pixels = Int((width * scale).rounded()) * Int((height * scale).rounded())
        return pixels * 4
    }

    /// Frame index shown for a phase (0…1 per loop).
    static func frameIndex(forPhase phase: Double, frameCount: Int) -> Int {
        guard frameCount > 1 else { return 0 }
        let wrapped = SpectrumWaveModel.wrappedPhase(phase)
        return min(frameCount - 1, Int(wrapped * Double(frameCount)))
    }

    // MARK: - Rendering

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
            // The Lane region is not the quota's remaining length. A tall crest
            // must never relight the known-exhausted black area, so the whole
            // spectrum subtree is clipped to the real outermost length from
            // `NestedGauge`. Static, lane-local, mirroring `fillRect`.
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
            stopAnimations(lane)
            return
        }
        root.isHidden = false

        let color = spec.glass.signalLights.paintedLight(for: spec.signal?.attention ?? .none)
        let density = spec.glass.material.rayDensity
        let size = region.size
        let scale = lane.contentsScale > 0 ? lane.contentsScale : (NSScreen.main?.backingScaleFactor ?? 2)
        let animated = !spec.reduceMotion

        // The curtain stands on the quota fill itself. Earlier builds put a
        // 0.45-alpha black scrim across the bottom 82% of the fill "to give the
        // rays something dark to stand on"; V5's own equivalent is `.zone
        // .sheen`, `linear-gradient(to bottom, transparent 76%, #08162a1f
        // 100%)` — a 0.12 machined bottom edge, not a half-black curtain. The
        // old scrim was the whole "灰蒙蒙" film: on the 12-tap dump it cost the
        // inner fill 38/255 of blue (155 native vs 193 in the lab).
        //
        // The scrim therefore reproduces V5's sheen exactly in geometry and
        // colour, minus the `#ffffff24 0px` top line: that 1px white top edge
        // is the "白线/内阴影" this lane deliberately removed in 551e647.
        // Static — Reduce Motion keeps it.
        let scrim = LayerSlot.named("scrim", in: root, as: CAGradientLayer.self)
        scrim.frame = CGRect(origin: .zero, size: size)
        scrim.type = .axial
        scrim.startPoint = CGPoint(x: 0.5, y: 0)
        scrim.endPoint = CGPoint(x: 0.5, y: 1)
        scrim.colors = [
            CGColor(red: 8 / 255, green: 22 / 255, blue: 42 / 255, alpha: 0),
            CGColor(red: 8 / 255, green: 22 / 255, blue: 42 / 255, alpha: 0.12),
        ]
        scrim.locations = [0.76, 1]

        let curtain = LayerSlot.named("curtain", in: root)
        curtain.frame = CGRect(origin: .zero, size: size)
        curtain.contentsScale = scale
        curtain.contentsGravity = .resize
        curtain.masksToBounds = true

        let frames = SpectrumFrameCache.sequence(
            width: size.width, height: size.height, scale: scale, cycle: cycle,
            color: color, density: density, intensity: spec.waveIntensity,
            travels: spec.showsTravelingLight, growsTowardRight: spec.geometry.growsTowardRight
        )
        if animated, frames.count > 1 {
            ensureCurtainAnimation(curtain, frames: frames, cycle: cycle, restart: restart)
        } else {
            curtain.removeAnimation(forKey: curtainKey)
            _ = setCurtainFrame(curtain, frames: frames, phase: 0)
        }

        LayerSlot.reconcile(root, keeping: ["scrim", "curtain"])
    }

    /// Freezes one lane at one phase: the offline preview path and the test
    /// hook. Never call this on the live tree while it is running.
    @discardableResult
    public static func applySampledPhase(into lane: CALayer, spec: LaneRenderSpec, phase: Double) -> Bool {
        guard let root = LayerSlot.root(named: "spectrum", in: lane) else { return false }
        stopAnimations(lane)
        guard spec.signal?.isRunning == true, !spec.reduceMotion else { return false }
        let cycle = SpectrumRhythm.cycleDuration(
            outputTPS: spec.signal?.observedOutputTPS, floorHz: spec.spectrumFloorHz
        )
        let region = spec.geometry.localFillBounds
        let size = region.size
        let scale = lane.contentsScale > 0 ? lane.contentsScale : (NSScreen.main?.backingScaleFactor ?? 2)
        let curtain = LayerSlot.named("curtain", in: root)
        let frames = SpectrumFrameCache.sequence(
            width: size.width, height: size.height, scale: scale, cycle: cycle,
            color: spec.glass.signalLights.paintedLight(for: spec.signal?.attention ?? .none),
            density: spec.glass.material.rayDensity, intensity: spec.waveIntensity,
            travels: spec.showsTravelingLight, growsTowardRight: spec.geometry.growsTowardRight
        )
        return setCurtainFrame(curtain, frames: frames, phase: phase)
    }

    @discardableResult
    private static func setCurtainFrame(_ curtain: CALayer, frames: [CGImage], phase: Double) -> Bool {
        guard !frames.isEmpty else { return false }
        let index = frameIndex(forPhase: phase, frameCount: frames.count)
        curtain.contents = frames[index]
        return true
    }

    /// The rasterised frame for one spec at one phase — used by the offline
    /// tests and the preview matrix, so a frozen PNG is the same picture the
    /// live sequence plays.
    public static func frameImage(for spec: LaneRenderSpec, phase: Double, scale: CGFloat = 2) -> CGImage? {
        let size = spec.geometry.localFillBounds.size
        return SpectrumFrameRasteriser.frame(
            width: size.width, height: size.height, scale: scale,
            color: spec.glass.signalLights.paintedLight(for: spec.signal?.attention ?? .none),
            density: spec.glass.material.rayDensity, intensity: spec.waveIntensity,
            travels: spec.showsTravelingLight, growsTowardRight: spec.geometry.growsTowardRight,
            phase: phase
        )
    }

    // MARK: - Motion

    /// Plays the pre-rasterised phase sequence as one discrete keyframe
    /// animation. `contents` is a real animatable property, and discrete
    /// keyframes make Core Animation swap whole frames in the render server —
    /// no per-frame CPU work and no timer in the app.
    private static func ensureCurtainAnimation(
        _ layer: CALayer, frames: [CGImage], cycle: Double, restart: Bool
    ) {
        let existing = layer.animation(forKey: curtainKey) as? CAKeyframeAnimation
        let timeline = curtainKeyframeTimeline(frames: frames)
        if !restart, let existing, existing.duration == cycle,
           sameImages(existing.values, timeline.values) {
            return
        }
        let localOrigin = layer.convertTime(CACurrentMediaTime(), from: nil)
        let carry = phaseCarry(from: existing, now: localOrigin)
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = timeline.values
        // Discrete keyframes: frame *i* holds from keyTime *i* to *i+1*. The
        // timeline ends with the first phase again, so the last frame is shown
        // for a full step and the loop seam is a step, not a double hold.
        animation.keyTimes = timeline.keyTimes
        animation.calculationMode = .discrete
        animation.duration = cycle
        animation.repeatCount = .infinity
        animation.beginTime = localOrigin
        animation.timeOffset = carry * cycle
        layer.contents = frames[0]
        layer.add(animation, forKey: curtainKey)
    }

    private static func sameImages(_ values: Any?, _ frames: [CGImage]) -> Bool {
        guard let images = values as? [CGImage], images.count == frames.count else { return false }
        return zip(images, frames).allSatisfy { $0 === $1 }
    }

    /// Normalised phase carried across a duration or frame-count change so a
    /// live adjustment re-times from where the animation already is. The layer
    /// keeps its identity; only the timeline is rewritten.
    static func phaseCarry(from animation: CAAnimation?, now: CFTimeInterval) -> Double {
        guard let animation, animation.duration > 0 else { return 0 }
        let previous = animation.duration
        let begin = animation.beginTime == 0 ? now : animation.beginTime
        let elapsed = now - begin + animation.timeOffset
        let wrapped = elapsed.truncatingRemainder(dividingBy: previous)
        return ((wrapped / previous) + 1).truncatingRemainder(dividingBy: 1)
    }

    /// Stops every animation this renderer owns, so a disabled overlay or a
    /// Reduce Motion switch leaves nothing ticking.
    public static func stopAnimations(_ lane: CALayer) {
        guard let root = LayerSlot.root(named: "spectrum", in: lane) else { return }
        stopSpectrumAnimations(root)
    }

    /// Recursively clears every animation key this renderer enables, including
    /// layers attached as `mask` children.
    static func stopSpectrumAnimations(_ root: CALayer) {
        var stack = [root]
        while let layer = stack.popLast() {
            layer.removeAnimation(forKey: curtainKey)
            if let mask = layer.mask {
                stack.append(mask)
            }
            stack.append(contentsOf: layer.sublayers ?? [])
        }
    }
}

/// LRU cache of rasterised phase sequences, with a byte budget.
///
/// A sequence is regenerated only when the picture actually changes (size,
/// scale, light colour, density, intensity, travel mode), never on a data
/// poll. The budget is expressed in **bytes of bitmap**, not entries: a wide
/// lane costs ~700 KiB per frame, so the cap is what keeps a 34 pt single-bar
/// lane from turning into a permanent 12 MiB allocation.
@MainActor
enum SpectrumFrameCache {
    struct Key: Hashable {
        var width: Int
        var height: Int
        var scale: Int
        var colorHex: String
        var density: Int
        var intensity: Int
        var travels: Bool
        var growsTowardRight: Bool
        var frameCount: Int
    }

    /// Total bitmap bytes kept across every lane and every variant.
    static let byteLimit = 16 * 1024 * 1024

    private static var cache: [Key: [CGImage]] = [:]
    private static var order: [Key] = []
    private static var bytesByKey: [Key: Int] = [:]
    private static var bytes = 0

    static var cachedByteCount: Int { bytes }
    static var cachedSequenceCount: Int { cache.count }

    static func sequence(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        cycle: Double,
        color: RGBAColor,
        density: Double,
        intensity: Double,
        travels: Bool,
        growsTowardRight: Bool
    ) -> [CGImage] {
        guard width > 0, height > 0 else { return [] }
        let frameCount = GlassSpectrumRenderer.framesPerCycle(
            width: width, height: height, scale: scale, cycle: cycle
        )
        let key = Key(
            width: Int(width.rounded()),
            height: Int(height.rounded()),
            scale: Int((scale * 100).rounded()),
            colorHex: color.withAlpha(1).hexString,
            density: Int((density * 100).rounded()),
            intensity: Int((SpectrumRhythm.clampedIntensity(intensity) * 100).rounded()),
            travels: travels,
            growsTowardRight: growsTowardRight,
            frameCount: frameCount
        )
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        let frames = (0..<frameCount).compactMap { index in
            SpectrumFrameRasteriser.frame(
                width: width, height: height, scale: scale, color: color,
                density: density, intensity: intensity, travels: travels,
                growsTowardRight: growsTowardRight,
                phase: SpectrumWaveModel.framePhase(index: index, count: frameCount)
            )
        }
        guard frames.count == frameCount else { return frames }
        cache[key] = frames
        order.append(key)
        let size = frames.count * GlassSpectrumRenderer.pixelByteCount(width: width, height: height, scale: scale)
        bytesByKey[key] = size
        bytes += size
        evictIfNeeded()
        return frames
    }

    /// Drops everything, including the ray sprites. Tests use it to observe
    /// cache behaviour.
    static func reset() {
        cache.removeAll()
        order.removeAll()
        bytesByKey.removeAll()
        bytes = 0
        RaySpriteCache.reset()
    }

    private static func touch(_ key: Key) {
        guard let index = order.firstIndex(of: key) else { return }
        order.remove(at: index)
        order.append(key)
    }

    private static func evictIfNeeded() {
        while bytes > byteLimit, order.count > 1, let oldest = order.first {
            order.removeFirst()
            if cache.removeValue(forKey: oldest) != nil {
                bytes -= bytesByKey.removeValue(forKey: oldest) ?? 0
            }
        }
    }
}

/// Rasterises one phase of the curtain.
///
/// The rays are stamped from a cached sprite rather than re-built from
/// `CGGradient` objects: a frame is a few hundred small blits, which keeps a
/// whole phase sequence in the low tens of milliseconds — cheap enough to
/// build on the main actor when a lane's size, colour or theme changes.
@MainActor
enum SpectrumFrameRasteriser {
    /// Reference height of the ray sprite. Taller than any real ray, so a
    /// stamped ray is always a downscale and the gradient stays smooth.
    static let spriteHeight: CGFloat = 64
    static let haloWidth: CGFloat = 4.2
    static let coreWidth: CGFloat = 1.16
    /// V5's specular reflection near the bottom edge.
    static let reflectionAlpha: Double = 0.105

    static func frame(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        color: RGBAColor,
        density: Double,
        intensity: Double,
        travels: Bool,
        growsTowardRight: Bool,
        phase: Double
    ) -> CGImage? {
        let pixelWidth = max(1, Int((width * scale).rounded()))
        let pixelHeight = max(1, Int((height * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let halo = RaySpriteCache.sprite(kind: .halo, color: color, scale: scale),
           let core = RaySpriteCache.sprite(kind: .core, color: color, scale: scale) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        let primary = SpectrumWaveModel.primaryCrestCenter(
            at: phase, travels: travels, travelsTowardRight: growsTowardRight
        )
        let secondary = SpectrumWaveModel.secondaryCrestCenter(
            at: phase, travels: travels, travelsTowardRight: growsTowardRight
        )
        let radius = SpectrumWaveModel.focusRadius(forWidth: Double(width))

        // The travelling light field caught by the frosted panel. Drawn
        // additively, like the lab's `screen` pass, so it lifts the glass
        // instead of laying a flat white sheet over it.
        context.saveGState()
        context.setBlendMode(.plusLighter)
        drawGlow(in: context, width: width, height: height,
                 center: primary, radius: radius, color: color, weight: 0.72)
        drawGlow(in: context, width: width, height: height,
                 center: secondary, radius: radius * 0.66, color: color,
                 weight: SpectrumWaveModel.secondaryWeight)
        // Soft specular reflection along the bottom edge, only under the crest.
        drawReflection(in: context, width: width, height: height, center: primary, radius: radius)
        context.restoreGState()

        // The curtain itself: every ray is a soft chromatic halo plus a bright
        // core, and every ray carries its own height and visibility.
        for ray in SpectrumWaveModel.rays(width: Double(width), density: density) {
            let sample = SpectrumWaveModel.sample(
                normalizedX: ray.normalizedX, rayIndex: ray.index, phase: phase,
                primaryCenter: primary, intensity: intensity, width: Double(width)
            )
            let rayHeight = height * CGFloat(sample.heightFraction)
            let x = CGFloat(ray.normalizedX) * width
            context.setAlpha(CGFloat(sample.alpha))
            context.draw(halo, in: CGRect(x: x - haloWidth / 2, y: 0, width: haloWidth, height: rayHeight))
            context.draw(core, in: CGRect(x: x - coreWidth / 2, y: 0, width: coreWidth, height: rayHeight))
        }
        context.setAlpha(1)

        return context.makeImage()
    }

    private static func drawGlow(
        in context: CGContext, width: CGFloat, height: CGFloat,
        center: Double, radius: Double, color: RGBAColor, weight: Double
    ) {
        guard radius > 0 else { return }
        let centerX = CGFloat(center) * width
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                // V5 Aurora's stops. The Acrylic scene uses 0.22 / 0.10; the
                // selected material is Aurora, whose light field is brighter
                // (0.28 / 0.14) because its whole panel is meant to catch the
                // crest. Using the Acrylic pair here is why the travelling
                // field looked weak next to the lab.
                color.withAlpha(0.28 * weight).cgColor,
                color.withAlpha(0.14 * weight).cgColor,
                color.withAlpha(0).cgColor,
            ] as CFArray,
            locations: [0, 0.34, 1]
        )
        guard let gradient else { return }
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: width, height: height))
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: centerX, y: height * 0.77), startRadius: 0,
            endCenter: CGPoint(x: centerX, y: height * 0.77), endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    private static func drawReflection(
        in context: CGContext, width: CGFloat, height: CGFloat, center: Double, radius: Double
    ) {
        guard radius > 0, width > 0 else { return }
        let centerX = CGFloat(center) * width
        let half = CGFloat(radius) * 0.5
        let left = max(0, centerX - half)
        let right = min(width, centerX + half)
        guard right > left else { return }
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0),
                CGColor(red: 1, green: 1, blue: 1, alpha: reflectionAlpha),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0),
            ] as CFArray,
            locations: [0, 0.5, 1]
        )
        guard let gradient else { return }
        context.saveGState()
        context.clip(to: CGRect(x: left, y: 0, width: right - left, height: height * 0.28))
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: left, y: 0), end: CGPoint(x: right, y: 0), options: []
        )
        context.restoreGState()
    }
}

/// Cached ray sprites. One sprite per (kind, colour, scale) — the density model
/// decides how often a sprite is stamped, never how many layers exist.
@MainActor
enum RaySpriteCache {
    enum Kind: Hashable {
        case halo
        case core
    }

    private static var cache: [String: CGImage] = [:]

    static func sprite(kind: Kind, color: RGBAColor, scale: CGFloat) -> CGImage? {
        let key = "\(kind)|\(color.withAlpha(1).hexString)|\(Int((scale * 100).rounded()))"
        if let cached = cache[key] { return cached }
        guard let image = draw(kind: kind, color: color, scale: scale) else { return nil }
        cache[key] = image
        return image
    }

    static func reset() { cache.removeAll() }

    private static func draw(kind: Kind, color: RGBAColor, scale: CGFloat) -> CGImage? {
        let width: CGFloat = kind == .halo ? SpectrumFrameRasteriser.haloWidth : SpectrumFrameRasteriser.coreWidth
        let pixelWidth = max(1, Int((width * scale).rounded()))
        let pixelHeight = max(2, Int((SpectrumFrameRasteriser.spriteHeight * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)

        let gradient: CGGradient?
        switch kind {
        case .halo:
            // Tip → base: the chromatic halo of a fine ray.
            gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    color.withAlpha(0).cgColor,
                    color.withAlpha(0.28).cgColor,
                    color.withAlpha(0.78).cgColor,
                    color.withAlpha(0.92).cgColor,
                ] as CFArray,
                locations: [0, 0.18, 0.64, 1]
            )
        case .core:
            // Tip → base: a white-hot centre that whitens where it meets the
            // strip. V5's stops are `rgba(255,255,255,0)` → `rgba(tint,.42)`
            // → `rgba(#f5faff, min(.90, alpha·.76))`; because the whole sprite
            // is stamped at `setAlpha(sample.alpha)`, the native stops below
            // are already that same effective ramp — the base is a fixed
            // near-white whose *coverage* is what scales with the sample.
            //
            // The "glowing white column" look the fidelity pass set out to fix
            // is therefore not a wrong base colour: it is the halo being too
            // dim around a correct core. Raise the curtain's body (see
            // `SpectrumWaveModel.baseAlpha`) rather than tinting the core.
            gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    CGColor(red: 1, green: 1, blue: 1, alpha: 0),
                    color.withAlpha(0.42).cgColor,
                    CGColor(red: 0xf5 / 255, green: 0xfa / 255, blue: 1, alpha: 0.76),
                ] as CFArray,
                locations: [0, 0.5, 1]
            )
        }
        guard let gradient else { return nil }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: SpectrumFrameRasteriser.spriteHeight),
            end: CGPoint(x: 0, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        return context.makeImage()
    }
}
