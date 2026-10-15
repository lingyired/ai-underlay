import AppKit

/// Owns one provider lane's persistent layer tree.
///
/// Every update mutates named slots in place instead of rebuilding the tree, so
/// a quota refresh, a theme hot reload or a repeated identical render can never
/// restart the running light field or leak layers. Only real changes — geometry
/// moved, the running flag flipped, the tempo crossed, the attention kind
/// changed — touch animations.
@MainActor
public final class GlassLayerHost {
    /// Counters the overlay tests assert on. Not used for rendering.
    public struct Diagnostics: Equatable, Sendable {
        public var updates = 0
        public var animationStarts = 0
        public var animatedLayerCount = 0
        public var layerCount = 0
    }

    public let root: CALayer
    public private(set) var diagnostics = Diagnostics()

    private var lastRunning = false
    private var lastCycle: Double?
    private var lastAttention: AttentionKind = .none
    private var lastReduceMotion = false

    public init() {
        root = CALayer()
        root.name = "laneHost"
        root.masksToBounds = true
    }

    public func update(_ spec: LaneRenderSpec) {
        diagnostics.updates += 1

        let running = spec.signal?.isRunning == true
        let attention = spec.signal?.attention ?? .none
        // Speed is normally unmeasured, so the resolved floor is the tempo that
        // actually runs; a user-picked baseline changes it live.
        let cycle = SpectrumRhythm.cycleDuration(
            outputTPS: spec.signal?.observedOutputTPS,
            floorHz: spec.spectrumFloorHz
        )

        // Restart the light field only when its drivers actually changed:
        // starting/stopping, a new tempo, or Reduce Motion freeing the layers.
        let spectrumChanged = running != lastRunning
            || (running && lastCycle != cycle)
            || spec.reduceMotion != lastReduceMotion
        let attentionChanged = attention != lastAttention || spec.reduceMotion != lastReduceMotion

        GlassQuotaRenderer.update(into: root, spec: spec)
        GlassSpectrumRenderer.update(into: root, spec: spec, running: running, cycle: cycle, restart: spectrumChanged)
        AttentionLightRenderer.update(into: root, spec: spec, attention: attention, restartSweep: attentionChanged)
        LayerSlot.reconcileLane(root)

        if spectrumChanged || attentionChanged {
            diagnostics.animationStarts += 1
        }
        lastRunning = running
        lastCycle = cycle
        lastAttention = attention
        lastReduceMotion = spec.reduceMotion
        diagnostics.layerCount = Self.countLayers(root)
        diagnostics.animatedLayerCount = Self.countAnimatedLayers(root)
    }

    /// Leaves the tree in place but stops everything and detaches it, so a
    /// disabled overlay or a removed display holds no animation resources.
    public func teardown() {
        GlassQuotaRenderer.stopAnimations(root)
        GlassSpectrumRenderer.stopAnimations(root)
        AttentionLightRenderer.stopAnimations(root)
        root.removeFromSuperlayer()
        lastRunning = false
        lastCycle = nil
        lastAttention = .none
        diagnostics.layerCount = Self.countLayers(root)
        diagnostics.animatedLayerCount = Self.countAnimatedLayers(root)
    }

    private static func countLayers(_ layer: CALayer) -> Int {
        1 + (layer.sublayers ?? []).reduce(0) { $0 + countLayers($1) }
    }

    private static func countAnimatedLayers(_ layer: CALayer) -> Int {
        let self_ = (layer.animationKeys()?.isEmpty == false) ? 1 : 0
        return self_ + (layer.sublayers ?? []).reduce(0) { $0 + countAnimatedLayers($1) }
    }
}
