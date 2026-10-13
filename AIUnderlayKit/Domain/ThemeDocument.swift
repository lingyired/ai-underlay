import Foundation

/// A versioned, **appearance-only** theme.
///
/// A theme can only describe how things look. It cannot invent quota windows,
/// change monitoring data, or reorder the Error > Waiting > Normal priority —
/// the priority is expressed by the resolver, never by the file. That is what
/// lets an AI agent author themes without touching Swift.
public struct ThemeDocument: Codable, Sendable, Equatable {
    /// Only this version is understood today. Unknown versions are rejected
    /// rather than guessed at, so a future format cannot be half-applied.
    public static let currentSchemaVersion = 1

    public struct Global: Codable, Sendable, Equatable {
        public var trackColor: String?
        public var trackOpacity: Double?
        public var baselineColor: String?
        public var baselineOpacity: Double?
        public var baselineEnabled: Bool?

        public init(
            trackColor: String? = nil,
            trackOpacity: Double? = nil,
            baselineColor: String? = nil,
            baselineOpacity: Double? = nil,
            baselineEnabled: Bool? = nil
        ) {
            self.trackColor = trackColor
            self.trackOpacity = trackOpacity
            self.baselineColor = baselineColor
            self.baselineOpacity = baselineOpacity
            self.baselineEnabled = baselineEnabled
        }
    }

    public struct Provider: Codable, Sendable, Equatable {
        /// Longest window first, so index 0 is the outermost layer.
        public var quotaLayers: [String]?
        public var spectrumColor: String?
        public var spectrumOpacity: Double?

        public init(quotaLayers: [String]? = nil, spectrumColor: String? = nil, spectrumOpacity: Double? = nil) {
            self.quotaLayers = quotaLayers
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

    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var global: Global?
    /// Keyed by provider id (`codex`, `claude`).
    public var providers: [String: Provider]?
    /// Keyed by state: `waiting`, `error` (and `recovering` when it is defined).
    public var states: [String: StateStyle]?

    public init(
        schemaVersion: Int = ThemeDocument.currentSchemaVersion,
        id: String,
        name: String,
        global: Global? = nil,
        providers: [String: Provider]? = nil,
        states: [String: StateStyle]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.global = global
        self.providers = providers
        self.states = states
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
                return "不支持的主题版本 schemaVersion=\(version)（本版本支持 \(ThemeDocument.currentSchemaVersion)）"
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
        guard document.schemaVersion == ThemeDocument.currentSchemaVersion else {
            throw Failure.unsupportedSchemaVersion(document.schemaVersion)
        }
        let issues = validate(document)
        guard issues.isEmpty else { throw Failure.invalid(issues) }
        return document
    }

    /// Empty means valid.
    public static func validate(_ document: ThemeDocument) -> [String] {
        var issues: [String] = []

        if document.schemaVersion != ThemeDocument.currentSchemaVersion {
            return ["schemaVersion 必须为 \(ThemeDocument.currentSchemaVersion)"]
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
        func check(_ opacity: Double?, _ label: String) {
            guard let opacity else { return }
            if !(0...1).contains(opacity) {
                issues.append("\(label) 必须在 0…1 之间")
            }
        }

        check(document.global?.trackColor, "global.trackColor")
        check(document.global?.trackOpacity, "global.trackOpacity")
        check(document.global?.baselineColor, "global.baselineColor")
        check(document.global?.baselineOpacity, "global.baselineOpacity")

        for (providerId, provider) in document.providers ?? [:] {
            check(provider.spectrumColor, "providers.\(providerId).spectrumColor")
            check(provider.spectrumOpacity, "providers.\(providerId).spectrumOpacity")
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
            check(style.overlayOpacity, "states.\(state).overlayOpacity")
            check(style.spectrumColor, "states.\(state).spectrumColor")
            check(style.borderColor, "states.\(state).borderColor")
            if let width = style.borderWidth, width < 0 || width > 10 {
                issues.append("states.\(state).borderWidth 必须在 0…10 之间")
            }
        }
        return issues
    }
}
