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
    /// `AttentionKind` raw value (+ "running") → hex. Global, state-driven.
    public var signalColors: [String: String]
    /// The fully-exhausted quota bed. V5 default: opaque black.
    public var exhaustedTrackColor: String?
    /// Field-wise material overrides, or nil for "follow the theme/defaults".
    public var material: GlassMaterialOverrides?

    public init(
        agentThemeColors: [String: String] = [:],
        quotaBaseColors: [String: String] = [:],
        signalColors: [String: String] = [:],
        exhaustedTrackColor: String? = nil,
        material: GlassMaterialOverrides? = nil
    ) {
        self.agentThemeColors = agentThemeColors
        self.quotaBaseColors = quotaBaseColors
        self.signalColors = signalColors
        self.exhaustedTrackColor = exhaustedTrackColor
        self.material = material
    }

    public static let empty = GlassAppearance()

    public var isEmpty: Bool {
        agentThemeColors.isEmpty && quotaBaseColors.isEmpty && signalColors.isEmpty
            && exhaustedTrackColor == nil && (material?.isEmpty ?? true)
    }

    /// Tolerant decoding: a malformed dictionary entry must never fail the
    /// whole settings file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agentThemeColors = (try? c.decodeIfPresent([String: String].self, forKey: .agentThemeColors)) ?? [:]
        quotaBaseColors = (try? c.decodeIfPresent([String: String].self, forKey: .quotaBaseColors)) ?? [:]
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

    public static let selectedV5 = GlassSignalLights(
        running: RGBAColor(red: 0xD9 / 255, green: 0xEE / 255, blue: 0xFF / 255),
        error: RGBAColor(red: 0xFF / 255, green: 0x75 / 255, blue: 0x96 / 255),
        waiting: RGBAColor(red: 0xFF / 255, green: 0xE1 / 255, blue: 0xA0 / 255),
        unread: RGBAColor(red: 0x64 / 255, green: 0xF1 / 255, blue: 0xBD / 255)
    )
}
