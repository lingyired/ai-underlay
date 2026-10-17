import Foundation

/// How one provider's quota windows spread across the two dual lanes.
///
/// Only meaningful in `.dual` layout with exactly one enabled provider: the
/// 5-hour session window and everything else (weekly, monthly, …) go to
/// opposite sides of the notch instead of nesting on one side.
public enum DualWindowSplit: String, Codable, Sendable, CaseIterable {
    /// No split: the provider's windows stay nested on its own side.
    case none
    /// 5-hour session window left, every remaining window right.
    case sessionLeft
    /// 5-hour session window right, every remaining window left.
    case sessionRight

    /// The side that must carry the 5-hour session window, or nil when the
    /// provider keeps all its windows together.
    public var sessionSide: GaugeSide? {
        switch self {
        case .none: return nil
        case .sessionLeft: return .left
        case .sessionRight: return .right
        }
    }
}

/// Which side of an active one-provider dual-window split a lane draws.
///
/// The role, not the screen side, carries the colour: flipping the split moves
/// the 5-hour window to the other side and its colour moves with it, so what a
/// colour means never changes underneath the user.
public enum SplitLaneRole: String, Codable, Sendable, CaseIterable {
    /// The side that carries the 5-hour session window.
    case session
    /// The side that keeps every remaining window (weekly, monthly, …).
    case weekly
}

/// The quota base colour of one side of a dual-window split.
///
/// Splitting one provider across both lanes would otherwise paint both sides
/// with its single base colour, and a glance could not tell the 5-hour window
/// from the weekly one. So the session side turns the provider's own hue by
/// `sessionHueShift`; the weekly side keeps the provider colour untouched. A
/// user override (`GlassAppearance.splitQuotaBaseColors`) always wins.
public enum SplitLaneColors {
    /// −30°: far enough that the two sides read as different colours, close
    /// enough that each stays inside its provider's colour family.
    public static let sessionHueShift: Double = -30.0 / 360.0

    /// The base colour for one side. `providerBase` is the provider's own
    /// full-brightness quota colour *after* theme and per-provider overrides,
    /// so a themed provider keeps its theme on both sides.
    public static func baseColor(
        role: SplitLaneRole,
        providerBase: RGBAColor,
        overrides: [String: String] = [:]
    ) -> RGBAColor {
        if let hex = overrides[role.rawValue], let color = RGBAColor(hex: hex) {
            return color
        }
        switch role {
        case .weekly: return providerBase
        case .session: return providerBase.rotatedHue(by: sessionHueShift)
        }
    }
}

/// Which provider each lane shows, resolved from the app-level provider
/// switches, the layout, and the dual-window split. Pure, so the whole
/// settings matrix is unit-tested without an `AppCoordinator`.
public struct LanePlan: Equatable, Sendable {
    /// Provider for the single full-width bar; nil when every provider is off.
    public var singleProviderId: String?
    public var leftProviderId: String?
    public var rightProviderId: String?
    /// When both dual lanes show the same provider, which side carries its
    /// 5-hour session window (the other side carries the remaining windows).
    public var splitSessionSide: GaugeSide?

    public init(
        singleProviderId: String?,
        leftProviderId: String?,
        rightProviderId: String?,
        splitSessionSide: GaugeSide?
    ) {
        self.singleProviderId = singleProviderId
        self.leftProviderId = leftProviderId
        self.rightProviderId = rightProviderId
        self.splitSessionSide = splitSessionSide
    }

    /// The role `side` plays while this plan splits one provider across both
    /// lanes, or nil in every other layout. Both lanes must really show the
    /// same provider: two providers keep their own colours, untouched.
    public func splitRole(for side: GaugeSide) -> SplitLaneRole? {
        guard let splitSessionSide,
              let providerId = leftProviderId,
              rightProviderId == providerId else { return nil }
        return splitSessionSide == side ? .session : .weekly
    }
}

public enum LanePlanResolver {
    /// One lane's provider and the exact windows it draws. Windows are
    /// longest-first; an empty array is the neutral groove of an offline lane.
    public struct LaneTarget: Equatable, Sendable {
        public var providerId: String
        public var windows: [QuotaWindow]

        public init(providerId: String, windows: [QuotaWindow]) {
            self.providerId = providerId
            self.windows = windows
        }
    }

    /// Resolves the plan for the current settings.
    ///
    /// - `enabledProviders` does not need to be ordered; `supportedProviders`
    ///   supplies both the order and each provider's home side.
    public static func plan(
        enabledProviders: [String],
        supportedProviders: [String],
        layout: LayoutMode,
        split: DualWindowSplit
    ) -> LanePlan {
        let enabled = supportedProviders.filter { enabledProviders.contains($0) }

        switch layout {
        case .single:
            return LanePlan(
                singleProviderId: enabled.first,
                leftProviderId: nil,
                rightProviderId: nil,
                splitSessionSide: nil
            )

        case .dual:
            if enabled.count == 1, let provider = enabled.first, let sessionSide = split.sessionSide {
                return LanePlan(
                    singleProviderId: nil,
                    leftProviderId: provider,
                    rightProviderId: provider,
                    splitSessionSide: sessionSide
                )
            }
            // Home sides follow the supported order, so each provider keeps its
            // own side when the other one is switched off. A provider beyond
            // the first two (the list currently stops there) takes any free
            // side, in order, instead of being dropped silently.
            let leftHome = supportedProviders.first
            let rightHome = supportedProviders.count > 1 ? supportedProviders[1] : nil
            var left: String?
            var right: String?
            for provider in enabled {
                if provider == leftHome, left == nil {
                    left = provider
                } else if provider == rightHome, right == nil {
                    right = provider
                } else if left == nil {
                    left = provider
                } else if right == nil {
                    right = provider
                }
            }
            return LanePlan(
                singleProviderId: nil,
                leftProviderId: left,
                rightProviderId: right,
                splitSessionSide: nil
            )
        }
    }

    /// What each lane draws right now: the plan plus the providers' window
    /// lists resolved into per-lane targets. Pure, so the split wiring is
    /// tested without an `AppCoordinator` or any rendering.
    public static func lanes(
        for plan: LanePlan,
        windowsForProvider: (String) -> [QuotaWindow]
    ) -> (left: LaneTarget?, right: LaneTarget?) {
        if let sessionSide = plan.splitSessionSide,
           let providerId = plan.leftProviderId,
           plan.rightProviderId == providerId {
            let split = WindowSplit.split(windowsForProvider(providerId), sessionSide: sessionSide)
            return (
                left: LaneTarget(providerId: providerId, windows: split.left),
                right: LaneTarget(providerId: providerId, windows: split.right)
            )
        }
        let left = (plan.singleProviderId ?? plan.leftProviderId).map {
            LaneTarget(providerId: $0, windows: windowsForProvider($0))
        }
        let right = plan.rightProviderId.map {
            LaneTarget(providerId: $0, windows: windowsForProvider($0))
        }
        return (left: left, right: right)
    }
}

/// Splits one provider's windows across the dual lanes.
public enum WindowSplit {
    /// `windows` arrive longest-first. The 5-hour (session) window goes to
    /// `sessionSide`; every other window stays together on the opposite side
    /// with its order preserved.
    public static func split(
        _ windows: [QuotaWindow],
        sessionSide: GaugeSide
    ) -> (left: [QuotaWindow], right: [QuotaWindow]) {
        var session: [QuotaWindow] = []
        var rest: [QuotaWindow] = []
        for window in windows {
            if window.kind == .session {
                session.append(window)
            } else {
                rest.append(window)
            }
        }
        return sessionSide == .left
            ? (left: session, right: rest)
            : (left: rest, right: session)
    }
}
