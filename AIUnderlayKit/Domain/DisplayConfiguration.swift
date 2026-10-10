import Foundation

/// single = one provider across the whole bar; dual = one provider per side.
public enum LayoutMode: String, Codable, Sendable, CaseIterable {
    case single
    case dual
}

/// Where the gauge grows from. `notch` anchors at the notch edge; `outerEdge`
/// anchors at the screen edge. Meaning of the data is independent of direction.
public enum AnchorMode: String, Codable, Sendable, CaseIterable {
    case notch
    case outerEdge
}

/// Direction for a single full-width bar.
public enum SingleBarDirection: String, Codable, Sendable, CaseIterable {
    case leadingToTrailing
    case trailingToLeading
}

/// Which side of the display a provider is assigned to.
public enum GaugeSide: String, Codable, Sendable, CaseIterable {
    case left
    case right
}

/// Binds a side to a provider and (optionally) a specific account snapshot.
public struct SideAssignment: Codable, Sendable, Equatable {
    public var side: GaugeSide
    public var providerId: String
    public var accountKey: String?

    public init(side: GaugeSide, providerId: String, accountKey: String? = nil) {
        self.side = side
        self.providerId = providerId
        self.accountKey = accountKey
    }
}

/// Per-display overlay configuration. Each display is configured independently
/// so different monitors can show different providers (or nothing).
public struct DisplayConfiguration: Codable, Sendable, Equatable {
    /// Stable display identifier (screen number), not an array index.
    public var displayID: String
    public var isEnabled: Bool
    public var layout: LayoutMode
    public var anchor: AnchorMode
    public var singleDirection: SingleBarDirection
    /// For single layout: the provider shown. For dual: per-side assignments.
    public var singleProviderId: String?
    public var assignments: [SideAssignment]

    public init(
        displayID: String,
        isEnabled: Bool = true,
        layout: LayoutMode = .dual,
        anchor: AnchorMode = .outerEdge,
        singleDirection: SingleBarDirection = .leadingToTrailing,
        singleProviderId: String? = nil,
        assignments: [SideAssignment] = []
    ) {
        self.displayID = displayID
        self.isEnabled = isEnabled
        self.layout = layout
        self.anchor = anchor
        self.singleDirection = singleDirection
        self.singleProviderId = singleProviderId
        self.assignments = assignments
    }
}
