import CoreGraphics

/// The geometry of one provider's fill area on the menu bar strip.
///
/// `trackRect` is the backing groove and always spans the full screen width —
/// even in notch-dual mode — because the notch is a rounded physical cutout and
/// a track clipped to the notch edge would leak wallpaper at the corners.
/// `fillBounds` is the region this provider's fill may occupy (it stops at the
/// notch edge); each provider clips its fill to its own bounds.
public struct GaugeGeometry: Equatable, Sendable {
    public var trackRect: CGRect
    public var fillBounds: CGRect
    /// The slice of the shared full-width track this lane paints as its groove.
    ///
    /// The track is one continuous underlay — it never stops at the notch edge,
    /// or wallpaper leaks through the notch's rounded corners. But each side
    /// paints only its own half, so the union still covers the whole screen
    /// while neither lane can wash over the other side's fills.
    public var trackBounds: CGRect
    public var growsTowardRight: Bool
    public var fullBleed: Bool

    public init(
        trackRect: CGRect,
        fillBounds: CGRect,
        growsTowardRight: Bool,
        fullBleed: Bool = true,
        trackBounds: CGRect? = nil
    ) {
        self.trackRect = trackRect
        self.fillBounds = fillBounds
        self.trackBounds = trackBounds ?? trackRect
        self.growsTowardRight = growsTowardRight
        self.fullBleed = fullBleed
    }

    /// `fillBounds` in the lane's own coordinate space. The lane is placed at
    /// `trackRect`, so renderers that clip to one provider's region (the light
    /// curtain, the attention band) use this instead of the screen-wide size.
    public var localFillBounds: CGRect {
        fillBounds.offsetBy(dx: -trackRect.minX, dy: -trackRect.minY)
    }

    /// `trackBounds` in the lane's own coordinate space, for the groove and its
    /// machined edges.
    public var localTrackBounds: CGRect {
        trackBounds.offsetBy(dx: -trackRect.minX, dy: -trackRect.minY)
    }

    /// The anchor X the fill grows from: the leading edge when growing right,
    /// the trailing edge when growing left.
    public var anchorX: CGFloat {
        growsTowardRight ? fillBounds.minX : fillBounds.maxX
    }

    /// Rect for a fill of `length` points measured from the anchor, growing in
    /// this segment's direction. Length is clamped to the segment's width.
    public func fillRect(forLength length: CGFloat) -> CGRect {
        let clamped = max(0, min(length, fillBounds.width))
        let x = growsTowardRight ? anchorX : anchorX - clamped
        return CGRect(x: x, y: fillBounds.minY, width: clamped, height: fillBounds.height)
    }
}

/// A gauge geometry paired with the side it belongs to.
public struct PlacedGauge: Equatable, Sendable {
    public var side: GaugeSide
    public var geometry: GaugeGeometry

    public init(side: GaugeSide, geometry: GaugeGeometry) {
        self.side = side
        self.geometry = geometry
    }
}

/// Pure layout: turns a display configuration plus screen metrics into the
/// concrete geometry for each side. No AppKit types are used, so this is fully
/// unit-testable and independent of any real display.
public enum GaugeLayout {
    public static func layout(
        mode: LayoutMode,
        anchor: AnchorMode,
        singleDirection: SingleBarDirection,
        screenFrame: CGRect,
        menuBarHeight: CGFloat,
        notchEdges: (left: CGFloat, right: CGFloat)?
    ) -> [PlacedGauge] {
        let track = CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - menuBarHeight,
            width: screenFrame.width,
            height: menuBarHeight
        )

        switch mode {
        case .single:
            let growsRight = singleDirection == .leadingToTrailing
            return [PlacedGauge(
                side: .left,
                geometry: GaugeGeometry(trackRect: track, fillBounds: track, growsTowardRight: growsRight)
            )]

        case .dual:
            // Inner edge = notch edge when present, otherwise the screen midline.
            let innerLeft = notchEdges?.left ?? screenFrame.midX
            let innerRight = notchEdges?.right ?? screenFrame.midX
            let outerLeft = screenFrame.minX
            let outerRight = screenFrame.maxX

            // Each side owns one half of the shared track: the two halves meet
            // at the midline, so the groove stays continuous through the notch
            // gap and neither lane paints over the other's fills.
            let leftTrack = CGRect(x: outerLeft, y: track.minY,
                                   width: max(0, screenFrame.midX - outerLeft), height: track.height)
            let rightTrack = CGRect(x: screenFrame.midX, y: track.minY,
                                    width: max(0, outerRight - screenFrame.midX), height: track.height)

            let left: GaugeGeometry
            let right: GaugeGeometry
            switch anchor {
            case .notch:
                // Anchor at the inner edge, grow outward.
                left = GaugeGeometry(
                    trackRect: track,
                    fillBounds: CGRect(x: outerLeft, y: track.minY,
                                       width: max(0, innerLeft - outerLeft), height: track.height),
                    growsTowardRight: false,
                    trackBounds: leftTrack
                )
                right = GaugeGeometry(
                    trackRect: track,
                    fillBounds: CGRect(x: innerRight, y: track.minY,
                                       width: max(0, outerRight - innerRight), height: track.height),
                    growsTowardRight: true,
                    trackBounds: rightTrack
                )
            case .outerEdge:
                // Anchor at the screen edge, grow inward toward the notch/midline.
                left = GaugeGeometry(
                    trackRect: track,
                    fillBounds: CGRect(x: outerLeft, y: track.minY,
                                       width: max(0, innerLeft - outerLeft), height: track.height),
                    growsTowardRight: true,
                    trackBounds: leftTrack
                )
                right = GaugeGeometry(
                    trackRect: track,
                    fillBounds: CGRect(x: innerRight, y: track.minY,
                                       width: max(0, outerRight - innerRight), height: track.height),
                    growsTowardRight: false,
                    trackBounds: rightTrack
                )
            }
            return [PlacedGauge(side: .left, geometry: left), PlacedGauge(side: .right, geometry: right)]
        }
    }
}
