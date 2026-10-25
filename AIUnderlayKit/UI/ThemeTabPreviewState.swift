import Foundation

/// Pure state beneath the theme form. Both the UI bindings and regression tests
/// use these functions, so displayed values cannot drift from mutations/resets.
public enum ThemeTabPreviewState {
    public enum ResetScope: CaseIterable, Sendable, Equatable {
        case providerTints
        case quotaColors
        case splitColors
        case signalColors
        case material
        case all

        public var confirmation: String {
            switch self {
            case .providerTints: return "服务商玻璃主题色已恢复为当前主题。"
            case .quotaColors: return "额度颜色已恢复为当前主题。"
            case .splitColors: return "5 小时侧与周额度侧已恢复为自动推导。"
            case .signalColors: return "状态灯颜色已恢复为当前主题。"
            case .material: return "玻璃材质已恢复为当前主题。"
            case .all: return "全部外观已恢复为当前主题。"
            }
        }

        public func apply(to appearance: GlassAppearance) -> GlassAppearance {
            var updated = appearance
            switch self {
            case .providerTints:
                updated.agentThemeColors = [:]
            case .quotaColors:
                updated.quotaBaseColors = [:]
                updated.exhaustedTrackColor = nil
            case .splitColors:
                updated.splitQuotaBaseColors = [:]
            case .signalColors:
                updated.signalColors = [:]
            case .material:
                updated.material = nil
            case .all:
                updated = .empty
            }
            return updated
        }

        public func hasOverrides(in appearance: GlassAppearance) -> Bool {
            switch self {
            case .providerTints: return !appearance.agentThemeColors.isEmpty
            case .quotaColors:
                return !appearance.quotaBaseColors.isEmpty
                    || appearance.exhaustedTrackColor != nil
            case .splitColors: return !appearance.splitQuotaBaseColors.isEmpty
            case .signalColors: return !appearance.signalColors.isEmpty
            case .material: return !(appearance.material?.isEmpty ?? true)
            case .all: return !appearance.isEmpty
            }
        }
    }

    public enum MaterialField: CaseIterable, Sendable, Equatable {
        case softness
        case ambientGlow
        case grain
        case rayDensity
        case quotaOpacity
        case themeStrength

        public var materialKeyPath: WritableKeyPath<GlassMaterialOverrides, Double?> {
            switch self {
            case .softness: return \.blurRadiusTarget
            case .ambientGlow: return \.ambientGlow
            case .grain: return \.grain
            case .rayDensity: return \.rayDensity
            case .quotaOpacity: return \.quotaOpacity
            case .themeStrength: return \.agentThemeStrength
            }
        }

        public var parametersKeyPath: WritableKeyPath<GlassMaterialParameters, Double> {
            switch self {
            case .softness: return \.blurRadiusTarget
            case .ambientGlow: return \.ambientGlow
            case .grain: return \.grain
            case .rayDensity: return \.rayDensity
            case .quotaOpacity: return \.quotaOpacity
            case .themeStrength: return \.agentThemeStrength
            }
        }

        public var range: ClosedRange<Double> {
            switch self {
            case .softness: return 0...GlassMaterialRenderer.maxSoftnessPoints
            default: return 0...1
            }
        }

        public var step: Double {
            switch self {
            case .softness: return 1
            default: return 0.01
            }
        }

        public func value(in material: GlassMaterialParameters) -> Double {
            material[keyPath: parametersKeyPath]
        }

        public func display(_ value: Double) -> String {
            switch self {
            case .softness:
                return String(format: "%.0f", value)
            default:
                return "\(Int((value * 100).rounded()))%"
            }
        }
    }

    public enum ColorField {
        case glassTint(providerId: String)
        case quotaBase(providerId: String)
        case exhaustedTrack
        case split(role: SplitLaneRole)
        case signal(key: SignalColorKey)

        public func isOverridden(in appearance: GlassAppearance) -> Bool {
            storedHex(in: appearance) != nil
        }

        public var providerId: String? {
            switch self {
            case .glassTint(let providerId), .quotaBase(let providerId):
                return providerId
            case .exhaustedTrack, .split, .signal:
                return nil
            }
        }

        func storedHex(in appearance: GlassAppearance) -> String? {
            switch self {
            case .glassTint(let providerId):
                return appearance.agentThemeColors[providerId]
            case .quotaBase(let providerId):
                return appearance.quotaBaseColors[providerId]
            case .exhaustedTrack:
                return appearance.exhaustedTrackColor
            case .split(let role):
                return appearance.splitQuotaBaseColors[role.rawValue]
            case .signal(let key):
                return appearance.signalColors[key.rawValue]
            }
        }

        func write(_ color: RGBAColor, to appearance: inout GlassAppearance) {
            switch self {
            case .glassTint(let providerId):
                appearance.agentThemeColors[providerId] = color.hexString
            case .quotaBase(let providerId):
                appearance.quotaBaseColors[providerId] = color.hexString
            case .exhaustedTrack:
                appearance.exhaustedTrackColor = color.hexString
            case .split(let role):
                appearance.splitQuotaBaseColors[role.rawValue] = color.hexString
            case .signal(let key):
                appearance.signalColors[key.rawValue] = color.hexString
            }
        }

        func clear(from appearance: inout GlassAppearance) {
            switch self {
            case .glassTint(let providerId):
                appearance.agentThemeColors[providerId] = nil
            case .quotaBase(let providerId):
                appearance.quotaBaseColors[providerId] = nil
            case .exhaustedTrack:
                appearance.exhaustedTrackColor = nil
            case .split(let role):
                appearance.splitQuotaBaseColors[role.rawValue] = nil
            case .signal(let key):
                appearance.signalColors[key.rawValue] = nil
            }
        }
    }

    public enum ValueSource: Sendable, Equatable {
        case personal
        case theme
        case builtIn
        case automatic
        case invalidPersonal

        public var label: String {
            switch self {
            case .personal: return "个人设置"
            case .theme: return "跟随主题"
            case .builtIn: return "内置默认"
            case .automatic: return "自动推导"
            case .invalidPersonal: return "个人值无效，已忽略"
            }
        }
    }

    public static func derivedTheme(
        theme: ThemeDocument?,
        providerId: String,
        appearance: GlassAppearance
    ) -> ResolvedGlassTheme {
        ThemeResolver.glassTheme(
            theme: theme,
            providerId: providerId,
            base: ProviderPalette.for(providerId: providerId),
            appearance: appearance
        )
    }

    public static func fallbackColor(
        for field: ColorField,
        theme: ThemeDocument?,
        providerId: String,
        appearance: GlassAppearance
    ) -> RGBAColor {
        let providerId = field.providerId ?? providerId
        switch field {
        case .glassTint:
            return derivedTheme(theme: theme, providerId: providerId, appearance: appearance)
                .agentThemeColor
        case .quotaBase:
            return derivedTheme(theme: theme, providerId: providerId, appearance: appearance)
                .palette.inner
        case .exhaustedTrack:
            return derivedTheme(theme: theme, providerId: providerId, appearance: appearance)
                .exhaustedTrack
        case .split(let role):
            let palette = derivedTheme(
                theme: theme,
                providerId: providerId,
                appearance: appearance
            ).palette
            return SplitLaneColors.baseColor(
                role: role,
                providerBase: palette.inner,
                overrides: appearance.splitQuotaBaseColors
            )
        case .signal(let key):
            return derivedTheme(theme: theme, providerId: providerId, appearance: appearance)
                .signalLights.color(for: key)
        }
    }

    public static func effectiveColor(
        for field: ColorField,
        theme: ThemeDocument?,
        providerId: String,
        appearance: GlassAppearance
    ) -> RGBAColor {
        if let stored = field.storedHex(in: appearance),
           let color = RGBAColor(hex: stored) {
            return color
        }
        return fallbackColor(
            for: field,
            theme: theme,
            providerId: providerId,
            appearance: appearance
        )
    }

    public static func source(
        for field: ColorField,
        appearance: GlassAppearance,
        theme: ThemeDocument?
    ) -> ValueSource {
        guard let stored = field.storedHex(in: appearance) else {
            if case .split = field {
                return .automatic
            }
            return themeProvides(field, theme: theme) ? .theme : .builtIn
        }
        return RGBAColor(hex: stored) == nil ? .invalidPersonal : .personal
    }

    private static func themeProvides(_ field: ColorField, theme: ThemeDocument?) -> Bool {
        guard let theme else { return false }
        switch field {
        case .glassTint(let providerId):
            return theme.providers?[providerId]?.agentThemeColor != nil
        case .quotaBase(let providerId):
            let provider = theme.providers?[providerId]
            return provider?.quotaBaseColor != nil || !(provider?.quotaLayers?.isEmpty ?? true)
        case .exhaustedTrack:
            return theme.global?.exhaustedTrackColor != nil
        case .split:
            return true
        case .signal(let key):
            let legacy = ThemeResolver.legacySignalLights(from: theme)
            switch key {
            case .running: return theme.signals?.running?.lightColor != nil || legacy.running != nil
            case .error: return theme.signals?.error?.lightColor != nil || legacy.error != nil
            case .waiting: return theme.signals?.waiting?.lightColor != nil || legacy.waiting != nil
            case .unread: return theme.signals?.unread?.lightColor != nil
            }
        }
    }

    public static func write(
        _ color: RGBAColor,
        for field: ColorField,
        to appearance: inout GlassAppearance
    ) {
        field.write(color, to: &appearance)
    }

    public static func clear(
        _ field: ColorField,
        from appearance: inout GlassAppearance
    ) {
        field.clear(from: &appearance)
    }

    public static func material(
        theme: ThemeDocument?,
        appearance: GlassAppearance
    ) -> GlassMaterialParameters {
        GlassMaterialOverrides.resolve(
            base: GlassDefaults.material,
            theme: theme?.material?.overrides,
            user: appearance.material
        )
    }

    public static func source(
        for field: MaterialField,
        theme: ThemeDocument?,
        appearance: GlassAppearance
    ) -> ValueSource {
        if appearance.material?[keyPath: field.materialKeyPath] != nil {
            return .personal
        }
        if theme?.material?.overrides[keyPath: field.materialKeyPath] != nil {
            return .theme
        }
        return .builtIn
    }

    public static func write(
        _ value: Double,
        for field: MaterialField,
        to appearance: inout GlassAppearance
    ) {
        var material = appearance.material ?? GlassMaterialOverrides()
        material[keyPath: field.materialKeyPath] = min(
            max(value, field.range.lowerBound),
            field.range.upperBound
        )
        appearance.material = material
    }

    public static func clear(
        _ field: MaterialField,
        from appearance: inout GlassAppearance
    ) {
        guard var material = appearance.material else { return }
        material[keyPath: field.materialKeyPath] = nil
        appearance.material = material.isEmpty ? nil : material
    }

    public static func overrideCount(in appearance: GlassAppearance) -> Int {
        var count = appearance.agentThemeColors.count
        count += appearance.quotaBaseColors.count
        count += appearance.splitQuotaBaseColors.count
        count += appearance.signalColors.count
        count += appearance.exhaustedTrackColor == nil ? 0 : 1
        count += MaterialField.allCases.reduce(0) {
            $0 + (appearance.material?[keyPath: $1.materialKeyPath] == nil ? 0 : 1)
        }
        return count
    }

    public static func statusAfterMutation(
        success: String,
        persistenceError: String?
    ) -> (text: String, warning: Bool) {
        guard persistenceError != nil else {
            return (success, false)
        }
        return (
            "修改已在本次运行中生效，但尚未保存。请检查磁盘空间或写入权限后重试。",
            true
        )
    }
}

private extension GlassSignalLights {
    func color(for key: SignalColorKey) -> RGBAColor {
        switch key {
        case .running: return running
        case .error: return error
        case .waiting: return waiting
        case .unread: return unread
        }
    }
}
