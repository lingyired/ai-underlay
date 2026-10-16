import QuartzCore

/// Helpers for building a **stable** layer tree: named slots are found and
/// reused across updates, so re-rendering (a quota refresh, a theme hot
/// reload) mutates properties in place instead of destroying layers. That is
/// what keeps running animations from restarting on every data poll.
enum LayerSlot {
    /// Find-or-create a child layer by name. Identity is preserved.
    static func named(_ name: String, in parent: CALayer) -> CALayer {
        if let existing = parent.sublayers?.first(where: { $0.name == name }) {
            return existing
        }
        let layer = CALayer()
        layer.name = name
        parent.addSublayer(layer)
        return layer
    }

    /// Find-or-create a child of the given type by name.
    static func named<T: CALayer>(_ name: String, in parent: CALayer, as type: T.Type) -> T {
        if let existing = parent.sublayers?.first(where: { $0.name == name }) as? T {
            return existing
        }
        if let stale = parent.sublayers?.first(where: { $0.name == name }) {
            stale.removeFromSuperlayer()
        }
        let layer = T()
        layer.name = name
        parent.addSublayer(layer)
        return layer
    }

    /// The named slot inside `lane`, accepting either the lane itself or one
    /// of its direct children. Teardown helpers use this so they can be
    /// called with a lane root, a bare effect root, or a nested host.
    static func root(named name: String, in lane: CALayer) -> CALayer? {
        if lane.name == name { return lane }
        return lane.sublayers?.first { $0.name == name }
    }

    /// Keep exactly the named children, in the given order, and remove the
    /// rest. Order is enforced so z-order never drifts after the quota window
    /// count changes.
    static func reconcile(_ parent: CALayer, keeping names: [String]) {
        let existing = parent.sublayers ?? []
        var ordered: [CALayer] = []
        ordered.reserveCapacity(names.count)
        for name in names {
            if let layer = existing.first(where: { $0.name == name }) {
                ordered.append(layer)
            }
        }
        let changed = existing.count != ordered.count
            || zip(existing, ordered).contains { $0 !== $1 }
        if changed {
            parent.sublayers = ordered
        }
    }

    /// The z-order of one provider lane: glass → spectrum → sheen → attention
    /// → baseline. The sheen (`scrim`) is V5's `.zone .sheen`, a normal-blend
    /// layer above the screen-blended ray group — it cannot live inside that
    /// group or the screen filter would neutralize it. The baseline is last so
    /// it stays readable over every effect.
    static let laneOrder = ["quotaGlass", "spectrum", "scrim", "attention", "baseline"]

    static func reconcileLane(_ lane: CALayer) {
        reconcile(lane, keeping: laneOrder)
    }
}

extension CGColor {
    /// A copy of this colour at a different alpha, guarding the range.
    func withAlpha(_ alpha: Double) -> CGColor {
        copy(alpha: min(max(alpha, 0), 1)) ?? self
    }
}
