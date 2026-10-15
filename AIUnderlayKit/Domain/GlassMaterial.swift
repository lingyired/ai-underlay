import Foundation

/// The glass material, as pure numbers.
///
/// These are *targets*, not raw browser pixels: the native renderer maps them
/// onto Core Animation textures and gradients (see `fake glass` in
/// `docs/architecture.md`). Every field except `blurRadiusTarget` is a 0…1
/// strength; `blurRadiusTarget` is a 0…32 point softness target carried over
/// from the V5 browser reference.
///
/// `blurRadiusTarget` is consumed by `GlassMaterialRenderer`, which turns it
/// into a real pre-blurred halo texture (rendered glass, not desktop backdrop
/// sampling): `kernelRadiusPixels = value × backingScale × 0.5`. The stored key,
/// its 0…32 range and its default of 17 stay backward compatible.
public struct GlassMaterialParameters: Codable, Sendable, Equatable {
    public var blurRadiusTarget: Double
    public var ambientGlow: Double
    public var grain: Double
    public var rayDensity: Double
    public var quotaOpacity: Double
    public var agentThemeStrength: Double

    public init(
        blurRadiusTarget: Double = 17,
        ambientGlow: Double = 0,
        grain: Double = 0,
        rayDensity: Double = 1,
        quotaOpacity: Double = 1,
        agentThemeStrength: Double = 1
    ) {
        self.blurRadiusTarget = blurRadiusTarget
        self.ambientGlow = ambientGlow
        self.grain = grain
        self.rayDensity = rayDensity
        self.quotaOpacity = quotaOpacity
        self.agentThemeStrength = agentThemeStrength
    }

    /// The exact parameters the user selected in the V5 material lab.
    public static let selectedV5 = GlassMaterialParameters()

    /// Clamps every field into its legal range. Renderers always consume the
    /// clamped value so a bad file can never produce an invisible or broken
    /// bar; the loader separately reports out-of-range values as errors.
    public var clamped: GlassMaterialParameters {
        GlassMaterialParameters(
            blurRadiusTarget: min(max(blurRadiusTarget, 0), 32),
            ambientGlow: min(max(ambientGlow, 0), 1),
            grain: min(max(grain, 0), 1),
            rayDensity: min(max(rayDensity, 0), 1),
            quotaOpacity: min(max(quotaOpacity, 0), 1),
            agentThemeStrength: min(max(agentThemeStrength, 0), 1)
        )
    }

}

/// Partial material values, as they appear in a theme file or in the user's
/// appearance overrides. A `nil` field means "keep the lower-priority value".
public struct GlassMaterialOverrides: Codable, Sendable, Equatable {
    public var blurRadiusTarget: Double?
    public var ambientGlow: Double?
    public var grain: Double?
    public var rayDensity: Double?
    public var quotaOpacity: Double?
    public var agentThemeStrength: Double?

    public init(
        blurRadiusTarget: Double? = nil,
        ambientGlow: Double? = nil,
        grain: Double? = nil,
        rayDensity: Double? = nil,
        quotaOpacity: Double? = nil,
        agentThemeStrength: Double? = nil
    ) {
        self.blurRadiusTarget = blurRadiusTarget
        self.ambientGlow = ambientGlow
        self.grain = grain
        self.rayDensity = rayDensity
        self.quotaOpacity = quotaOpacity
        self.agentThemeStrength = agentThemeStrength
    }

    public var isEmpty: Bool {
        blurRadiusTarget == nil && ambientGlow == nil && grain == nil
            && rayDensity == nil && quotaOpacity == nil && agentThemeStrength == nil
    }

    /// Field-wise resolution. The user's own UI edits outrank the theme file,
    /// which outranks the built-in V5 defaults. Every result is clamped.
    public static func resolve(
        base: GlassMaterialParameters,
        theme: GlassMaterialOverrides?,
        user: GlassMaterialOverrides?
    ) -> GlassMaterialParameters {
        func pick(_ user: Double?, _ theme: Double?, _ fallback: Double) -> Double {
            user ?? theme ?? fallback
        }
        return GlassMaterialParameters(
            blurRadiusTarget: pick(user?.blurRadiusTarget, theme?.blurRadiusTarget, base.blurRadiusTarget),
            ambientGlow: pick(user?.ambientGlow, theme?.ambientGlow, base.ambientGlow),
            grain: pick(user?.grain, theme?.grain, base.grain),
            rayDensity: pick(user?.rayDensity, theme?.rayDensity, base.rayDensity),
            quotaOpacity: pick(user?.quotaOpacity, theme?.quotaOpacity, base.quotaOpacity),
            agentThemeStrength: pick(user?.agentThemeStrength, theme?.agentThemeStrength, base.agentThemeStrength)
        ).clamped
    }
}

/// Sizes of the attention ribbon, in points. The V5 reference is a 34px
/// browser strip; the native band is 30/32/34pt and the renderer clamps these
/// to the live lane height.
public struct AttentionGeometry: Codable, Sendable, Equatable {
    public var topLineHeight: Double
    public var bottomRibbonHeight: Double
    public var sweepSecondsError: Double
    public var sweepSecondsWaiting: Double
    public var sweepSecondsUnread: Double

    public init(
        topLineHeight: Double = 2,
        bottomRibbonHeight: Double = 5,
        sweepSecondsError: Double = 4,
        sweepSecondsWaiting: Double = 5,
        sweepSecondsUnread: Double = 7
    ) {
        self.topLineHeight = topLineHeight
        self.bottomRibbonHeight = bottomRibbonHeight
        self.sweepSecondsError = sweepSecondsError
        self.sweepSecondsWaiting = sweepSecondsWaiting
        self.sweepSecondsUnread = sweepSecondsUnread
    }

    public static let selectedV5 = AttentionGeometry()

    public func sweepSeconds(for attention: AttentionKind) -> Double {
        switch attention {
        case .error: return sweepSecondsError
        case .waiting: return sweepSecondsWaiting
        case .unread: return sweepSecondsUnread
        case .none: return sweepSecondsWaiting
        }
    }

    public var clamped: AttentionGeometry {
        func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
            min(max(value, low), high)
        }
        return AttentionGeometry(
            topLineHeight: clamp(topLineHeight, 0, 6),
            bottomRibbonHeight: clamp(bottomRibbonHeight, 0, 10),
            sweepSecondsError: clamp(sweepSecondsError, 1, 60),
            sweepSecondsWaiting: clamp(sweepSecondsWaiting, 1, 60),
            sweepSecondsUnread: clamp(sweepSecondsUnread, 1, 60)
        )
    }
}
