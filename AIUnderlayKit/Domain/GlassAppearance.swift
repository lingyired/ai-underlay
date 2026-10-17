import Foundation

/// The user's own colour edits, made in the settings UI.
///
/// These live in `settings.json` (not in a theme file) so a slider move is
/// instant, survives restarts, and can never fight the theme hot-reload loop.
/// Precedence everywhere is: **user appearance > theme file > built-in V5
/// defaults**. Values are hex strings so a hand-edited settings file stays
/// readable; invalid strings are ignored at resolve time, never rendered.
public struct GlassAppearance: Codable, Sendable, Equatable {
    /// providerId → hex. Tints that provider lane's glass only.
    public var agentThemeColors: [String: String]
    /// providerId → hex. The provider's quota colour; tiers derive from it.
    public var quotaBaseColors: [String: String]
    /// `SplitLaneRole` raw value → hex. The quota colour of each side while one
    /// provider is split across both lanes ("5 小时" vs "周额度"). Empty means
    /// the built-in two-tone derivation (`SplitLaneColors`). It is never
    /// applied outside an active split, so normal dual mode is unaffected.
    public var splitQuotaBaseColors: [String: String]
    /// `AttentionKind` raw value (+ "running") → hex. Global, state-driven.
    public var signalColors: [String: String]
    /// The fully-exhausted quota bed. V5 default: opaque black.
    public var exhaustedTrackColor: String?
    /// Field-wise material overrides, or nil for "follow the theme/defaults".
    public var material: GlassMaterialOverrides?

    public init(
        agentThemeColors: [String: String] = [:],
        quotaBaseColors: [String: String] = [:],
        splitQuotaBaseColors: [String: String] = [:],
        signalColors: [String: String] = [:],
        exhaustedTrackColor: String? = nil,
        material: GlassMaterialOverrides? = nil
    ) {
        self.agentThemeColors = agentThemeColors
        self.quotaBaseColors = quotaBaseColors
        self.splitQuotaBaseColors = splitQuotaBaseColors
        self.signalColors = signalColors
        self.exhaustedTrackColor = exhaustedTrackColor
        self.material = material
    }

    public static let empty = GlassAppearance()

    public var isEmpty: Bool {
        agentThemeColors.isEmpty && quotaBaseColors.isEmpty && splitQuotaBaseColors.isEmpty
            && signalColors.isEmpty && exhaustedTrackColor == nil && (material?.isEmpty ?? true)
    }

    /// Tolerant decoding: a malformed dictionary entry must never fail the
    /// whole settings file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agentThemeColors = (try? c.decodeIfPresent([String: String].self, forKey: .agentThemeColors)) ?? [:]
        quotaBaseColors = (try? c.decodeIfPresent([String: String].self, forKey: .quotaBaseColors)) ?? [:]
        splitQuotaBaseColors = (try? c.decodeIfPresent([String: String].self, forKey: .splitQuotaBaseColors)) ?? [:]
        signalColors = (try? c.decodeIfPresent([String: String].self, forKey: .signalColors)) ?? [:]
        exhaustedTrackColor = try? c.decodeIfPresent(String.self, forKey: .exhaustedTrackColor)
        material = try? c.decodeIfPresent(GlassMaterialOverrides.self, forKey: .material)
    }
}

/// The keys the signal-colour dictionary uses. Running is included because it
/// is a light colour too, even though it is not an `AttentionKind`.
public enum SignalColorKey: String, Codable, Sendable, CaseIterable {
    case running
    case error
    case waiting
    case unread
}

/// The four signal lights, already resolved for one lane.
public struct GlassSignalLights: Sendable, Equatable {
    public var running: RGBAColor
    public var error: RGBAColor
    public var waiting: RGBAColor
    public var unread: RGBAColor

    public init(running: RGBAColor, error: RGBAColor, waiting: RGBAColor, unread: RGBAColor) {
        self.running = running
        self.error = error
        self.waiting = waiting
        self.unread = unread
    }

    /// The light a running lane wears: the highest attention colour, or the
    /// running light when nothing is asking for attention.
    public func light(for attention: AttentionKind) -> RGBAColor {
        switch attention {
        case .error: return error
        case .waiting: return waiting
        case .unread: return unread
        case .none: return running
        }
    }

    /// The colour of the *light*, not of the lamp: what the wash and the
    /// ribbon's glow are painted with.
    ///
    /// V5 separates the two on purpose. `--alert` is the pale colour of the
    /// 2pt top line and the ribbon itself; `--tint` is a hand-picked, more
    /// saturated version used for the two translucent layers
    /// (`rgba(var(--tint), .24)` wash, `rgba(var(--tint), .38)` glow), so they
    /// stay legible as coloured light instead of greying the glass. We shipped
    /// the pale alert colour in both, which is the measured cause of the
    /// "等待比较灰 / 少了一些亮度" reading on hardware, where the system menu
    /// bar material already desaturates everything underneath it.
    ///
    /// The shipped palette returns V5's lab values verbatim; a user override
    /// gets the same hue with its saturation lifted instead.
    public func tint(for attention: AttentionKind) -> RGBAColor {
        let light = light(for: attention)
        if let reference = Self.v5TintReference[attention],
           reference.alert.hexString == light.hexString {
            return reference.tint
        }
        return light.saturationLifted()
    }

    /// The colour a *painted* layer wears, which is not always the colour the
    /// state is *named*: the pale alert is what Error/Waiting/Unread mean, the
    /// saturated partner is what survives the menu bar material. A quiet lane
    /// keeps its running light untouched — that is the everyday look and it is
    /// already the light field's own colour.
    public func paintedLight(for attention: AttentionKind) -> RGBAColor {
        attention == .none ? light(for: .none) : tint(for: attention)
    }

    /// V5's `.zone[data-attention=…]` pairs, copied from the lab stylesheet.
    private static let v5TintReference: [AttentionKind: (alert: RGBAColor, tint: RGBAColor)] = [
        .error: (
            alert: RGBAColor(red: 0xFF / 255, green: 0x75 / 255, blue: 0x96 / 255),
            tint: RGBAColor(red: 0xFF / 255, green: 0x58 / 255, blue: 0x7E / 255)
        ),
        .waiting: (
            alert: RGBAColor(red: 0xFF / 255, green: 0xE1 / 255, blue: 0xA0 / 255),
            tint: RGBAColor(red: 0xFF / 255, green: 0xC2 / 255, blue: 0x5B / 255)
        ),
        .unread: (
            alert: RGBAColor(red: 0x64 / 255, green: 0xF1 / 255, blue: 0xBD / 255),
            tint: RGBAColor(red: 0x2F / 255, green: 0xE7 / 255, blue: 0xAD / 255)
        ),
    ]

    public static let selectedV5 = GlassSignalLights(
        running: RGBAColor(red: 0xD9 / 255, green: 0xEE / 255, blue: 0xFF / 255),
        error: RGBAColor(red: 0xFF / 255, green: 0x75 / 255, blue: 0x96 / 255),
        waiting: RGBAColor(red: 0xFF / 255, green: 0xE1 / 255, blue: 0xA0 / 255),
        unread: RGBAColor(red: 0x64 / 255, green: 0xF1 / 255, blue: 0xBD / 255)
    )
}
