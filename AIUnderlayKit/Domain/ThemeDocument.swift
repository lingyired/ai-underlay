import Foundation

/// A versioned, **appearance-only** theme.
///
/// A theme can only describe how things look. It cannot invent quota windows,
/// change monitoring data, or reorder the Error > Waiting > Unread priority —
/// the priority is expressed by the resolver, never by the file. That is what
/// lets an AI agent author themes without touching Swift.
///
/// `schemaVersion = 1` files keep working exactly as before. Version 2 adds
/// the Glass Spectrum vocabulary: a `material` section, per-provider
/// `quotaBaseColor` / `agentThemeColor`, global `signals` lights and the
/// `attention` ribbon geometry. Both versions are decoded into the same
/// `ResolvedGlassTheme` by `ThemeResolver`.
public struct ThemeDocument: Codable, Sendable, Equatable {
    /// The version this app writes when exporting. Older versions are still
    /// read; unknown future versions are rejected rather than guessed at.
    public static let currentSchemaVersion = 2
    public static let supportedSchemaVersions: [Int] = [1, 2]

    public struct Global: Codable, Sendable, Equatable {
        public var trackColor: String?
        public var trackOpacity: Double?
        public var baselineColor: String?
        public var baselineOpacity: Double?
        public var baselineEnabled: Bool?
        /// v2: the bed under a known quota. V5 default: opaque black.
        public var exhaustedTrackColor: String?
        public var exhaustedTrackOpacity: Double?

        public init(
            trackColor: String? = nil,
            trackOpacity: Double? = nil,
            baselineColor: String? = nil,
            baselineOpacity: Double? = nil,
            baselineEnabled: Bool? = nil,
            exhaustedTrackColor: String? = nil,
            exhaustedTrackOpacity: Double? = nil
        ) {
            self.trackColor = trackColor
            self.trackOpacity = trackOpacity
            self.baselineColor = baselineColor
            self.baselineOpacity = baselineOpacity
            self.baselineEnabled = baselineEnabled
            self.exhaustedTrackColor = exhaustedTrackColor
            self.exhaustedTrackOpacity = exhaustedTrackOpacity
        }
    }

    public struct Provider: Codable, Sendable, Equatable {
        /// Longest window first, so index 0 is the outermost layer.
        public var quotaLayers: [String]?
        /// v2: one base colour; the tier ladder derives from it.
        public var quotaBaseColor: String?
        /// v2: this provider's glass tint. Never touches quotas or signals.
        public var agentThemeColor: String?
        /// v1 legacy: the colour of the moving effect.
        public var spectrumColor: String?
        public var spectrumOpacity: Double?

        public init(
            quotaLayers: [String]? = nil,
            quotaBaseColor: String? = nil,
            agentThemeColor: String? = nil,
            spectrumColor: String? = nil,
            spectrumOpacity: Double? = nil
        ) {
            self.quotaLayers = quotaLayers
            self.quotaBaseColor = quotaBaseColor
            self.agentThemeColor = agentThemeColor
            self.spectrumColor = spectrumColor
            self.spectrumOpacity = spectrumOpacity
        }
    }

    public struct StateStyle: Codable, Sendable, Equatable {
        public var overlayColor: String?
        public var overlayOpacity: Double?
        public var spectrumColor: String?
        public var borderColor: String?
        public var borderWidth: Double?

        public init(
            overlayColor: String? = nil,
            overlayOpacity: Double? = nil,
            spectrumColor: String? = nil,
            borderColor: String? = nil,
            borderWidth: Double? = nil
        ) {
            self.overlayColor = overlayColor
            self.overlayOpacity = overlayOpacity
            self.spectrumColor = spectrumColor
            self.borderColor = borderColor
            self.borderWidth = borderWidth
        }
    }

    /// v2: one signal light per state. Global semantics — the priority itself
    /// stays a code constant.
    public struct SignalStyle: Codable, Sendable, Equatable {
        public var lightColor: String?

        public init(lightColor: String? = nil) {
            self.lightColor = lightColor
        }
    }

    public struct Signals: Codable, Sendable, Equatable {
        public var running: SignalStyle?
        public var error: SignalStyle?
        public var waiting: SignalStyle?
        public var unread: SignalStyle?

        public init(
            running: SignalStyle? = nil,
            error: SignalStyle? = nil,
            waiting: SignalStyle? = nil,
            unread: SignalStyle? = nil
        ) {
            self.running = running
            self.error = error
            self.waiting = waiting
            self.unread = unread
        }
    }

    /// v2: the glass material, as renderer targets.
    public struct Material: Codable, Sendable, Equatable {
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

        var overrides: GlassMaterialOverrides {
            GlassMaterialOverrides(
                blurRadiusTarget: blurRadiusTarget,
                ambientGlow: ambientGlow,
                grain: grain,
                rayDensity: rayDensity,
                quotaOpacity: quotaOpacity,
                agentThemeStrength: agentThemeStrength
            )
        }
    }

    public struct Attention: Codable, Sendable, Equatable {
        public var topLineHeight: Double?
        public var bottomRibbonHeight: Double?
        public var sweepSecondsError: Double?
        public var sweepSecondsWaiting: Double?
        public var sweepSecondsUnread: Double?

        public init(
            topLineHeight: Double? = nil,
            bottomRibbonHeight: Double? = nil,
            sweepSecondsError: Double? = nil,
            sweepSecondsWaiting: Double? = nil,
            sweepSecondsUnread: Double? = nil
        ) {
            self.topLineHeight = topLineHeight
            self.bottomRibbonHeight = bottomRibbonHeight
            self.sweepSecondsError = sweepSecondsError
            self.sweepSecondsWaiting = sweepSecondsWaiting
            self.sweepSecondsUnread = sweepSecondsUnread
        }
    }

    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var global: Global?
    /// Keyed by provider id (`codex`, `claude`).
    public var providers: [String: Provider]?
    /// v1 states: `waiting`, `error` (and `recovering` when it is defined).
    public var states: [String: StateStyle]?
    /// v2 machine state lights.
    public var signals: Signals?
    /// v2 material targets.
    public var material: Material?
    /// v2 attention ribbon geometry.
    public var attention: Attention?

    public init(
        schemaVersion: Int = ThemeDocument.currentSchemaVersion,
        id: String,
        name: String,
        global: Global? = nil,
        providers: [String: Provider]? = nil,
        states: [String: StateStyle]? = nil,
        signals: Signals? = nil,
        material: Material? = nil,
        attention: Attention? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.global = global
        self.providers = providers
        self.states = states
        self.signals = signals
        self.material = material
        self.attention = attention
    }
}

/// A loose sRGB color parsed from a theme file.
public struct ThemeColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RRGGBB`, `RRGGBB`, `#RGB`, or `#RRGGBBAA`. Returns nil for
    /// anything else so a typo is reported instead of silently rendering black.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 3 || text.count == 6 || text.count == 8,
              text.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(text, radix: 16)
        else { return nil }

        func component(_ shift: UInt64) -> Double {
            Double((value >> shift) & 0xFF) / 255
        }
        switch text.count {
        case 3:
            func nibble(_ shift: UInt64) -> Double {
                Double((value >> shift) & 0xF) / 15
            }
            self.init(red: nibble(8), green: nibble(4), blue: nibble(0))
        case 6:
            self.init(red: component(16), green: component(8), blue: component(0))
        default:
            self.init(red: component(24), green: component(16), blue: component(8), alpha: component(0))
        }
    }
}

/// Reads and validates theme JSON. Pure: no file system, no AppKit — the
/// store owns I/O, this owns the rules.
public enum ThemeLoader {
    public enum Failure: Error, Equatable, Sendable {
        case unreadable(String)
        case unsupportedSchemaVersion(Int)
        case invalid([String])

        /// One short line for the settings UI.
        public var message: String {
            switch self {
            case .unreadable(let detail): return "无法解析：\(detail)"
            case .unsupportedSchemaVersion(let version):
                return "不支持的主题版本 schemaVersion=\(version)（本版本支持 \(ThemeDocument.supportedSchemaVersions.map(String.init).joined(separator: "/"))）"
            case .invalid(let issues): return issues.joined(separator: "；")
            }
        }
    }

    public static func decode(_ data: Data) throws -> ThemeDocument {
        let document: ThemeDocument
        do {
            document = try JSONDecoder().decode(ThemeDocument.self, from: data)
        } catch {
            throw Failure.unreadable(String(describing: error))
        }
        guard ThemeDocument.supportedSchemaVersions.contains(document.schemaVersion) else {
            throw Failure.unsupportedSchemaVersion(document.schemaVersion)
        }
        let issues = validate(document)
        guard issues.isEmpty else { throw Failure.invalid(issues) }
        return document
    }

    /// Empty means valid.
    public static func validate(_ document: ThemeDocument) -> [String] {
        var issues: [String] = []

        guard ThemeDocument.supportedSchemaVersions.contains(document.schemaVersion) else {
            return ["schemaVersion 必须为 \(ThemeDocument.supportedSchemaVersions.map(String.init).joined(separator: " 或 "))"]
        }
        if document.id.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("id 不能为空")
        } else if document.id.contains("/") || document.id.contains("\\") {
            issues.append("id 不能包含路径分隔符")
        }
        if document.name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("name 不能为空")
        }

        func check(_ color: String?, _ label: String) {
            guard let color else { return }
            if ThemeColor(hex: color) == nil {
                issues.append("\(label) 不是合法颜色：\(color)")
            }
        }
        func check(_ value: Double?, _ label: String, in range: ClosedRange<Double>) {
            guard let value else { return }
            if !value.isFinite || !range.contains(value) {
                issues.append("\(label) 必须在 \(range.lowerBound)…\(range.upperBound) 之间")
            }
        }

        check(document.global?.trackColor, "global.trackColor")
        check(document.global?.trackOpacity, "global.trackOpacity", in: 0...1)
        check(document.global?.baselineColor, "global.baselineColor")
        check(document.global?.baselineOpacity, "global.baselineOpacity", in: 0...1)
        check(document.global?.exhaustedTrackColor, "global.exhaustedTrackColor")
        check(document.global?.exhaustedTrackOpacity, "global.exhaustedTrackOpacity", in: 0...1)

        for (providerId, provider) in document.providers ?? [:] {
            check(provider.spectrumColor, "providers.\(providerId).spectrumColor")
            check(provider.spectrumOpacity, "providers.\(providerId).spectrumOpacity", in: 0...1)
            check(provider.quotaBaseColor, "providers.\(providerId).quotaBaseColor")
            check(provider.agentThemeColor, "providers.\(providerId).agentThemeColor")
            let layers = provider.quotaLayers ?? []
            if layers.count > 3 {
                issues.append("providers.\(providerId).quotaLayers 最多 3 层（外层→内层）")
            }
            for (index, layer) in layers.enumerated() {
                check(layer, "providers.\(providerId).quotaLayers[\(index)]")
            }
        }

        for (state, style) in document.states ?? [:] {
            check(style.overlayColor, "states.\(state).overlayColor")
            check(style.overlayOpacity, "states.\(state).overlayOpacity", in: 0...1)
            check(style.spectrumColor, "states.\(state).spectrumColor")
            check(style.borderColor, "states.\(state).borderColor")
            check(style.borderWidth, "states.\(state).borderWidth", in: 0...10)
        }

        for (key, signal) in signalStyles(of: document) {
            check(signal.lightColor, "signals.\(key).lightColor")
        }

        check(document.material?.blurRadiusTarget, "material.blurRadiusTarget", in: 0...32)
        check(document.material?.ambientGlow, "material.ambientGlow", in: 0...1)
        check(document.material?.grain, "material.grain", in: 0...1)
        check(document.material?.rayDensity, "material.rayDensity", in: 0...1)
        check(document.material?.quotaOpacity, "material.quotaOpacity", in: 0...1)
        check(document.material?.agentThemeStrength, "material.agentThemeStrength", in: 0...1)

        check(document.attention?.topLineHeight, "attention.topLineHeight", in: 0...6)
        check(document.attention?.bottomRibbonHeight, "attention.bottomRibbonHeight", in: 0...10)
        check(document.attention?.sweepSecondsError, "attention.sweepSecondsError", in: 1...60)
        check(document.attention?.sweepSecondsWaiting, "attention.sweepSecondsWaiting", in: 1...60)
        check(document.attention?.sweepSecondsUnread, "attention.sweepSecondsUnread", in: 1...60)

        return issues
    }

    /// The v2 signal styles as (key, style) pairs, for iteration.
    static func signalStyles(of document: ThemeDocument) -> [(String, ThemeDocument.SignalStyle)] {
        guard let signals = document.signals else { return [] }
        return [
            ("running", signals.running),
            ("error", signals.error),
            ("waiting", signals.waiting),
            ("unread", signals.unread),
        ].compactMap { key, style in style.map { (key, $0) } }
    }
}
