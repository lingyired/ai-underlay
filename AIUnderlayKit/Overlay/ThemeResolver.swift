import CoreGraphics
import Foundation

/// The appearance a theme contributes to one provider's agent effects.
///
/// Only colors and stroke widths live here. Which state wins — Error, then
/// Waiting, then Normal — is decided by the state machine in `AgentEffectStyle`,
/// never by a theme file.
public struct AgentEffectTheme: Equatable, Sendable {
    public var runningColor: RGBAColor?
    public var waitingOverlay: RGBAColor?
    public var waitingBorder: RGBAColor?
    public var waitingBorderWidth: CGFloat?
    public var errorOverlay: RGBAColor?
    public var errorBorder: RGBAColor?
    public var errorBorderWidth: CGFloat?

    public init(
        runningColor: RGBAColor? = nil,
        waitingOverlay: RGBAColor? = nil,
        waitingBorder: RGBAColor? = nil,
        waitingBorderWidth: CGFloat? = nil,
        errorOverlay: RGBAColor? = nil,
        errorBorder: RGBAColor? = nil,
        errorBorderWidth: CGFloat? = nil
    ) {
        self.runningColor = runningColor
        self.waitingOverlay = waitingOverlay
        self.waitingBorder = waitingBorder
        self.waitingBorderWidth = waitingBorderWidth
        self.errorOverlay = errorOverlay
        self.errorBorder = errorBorder
        self.errorBorderWidth = errorBorderWidth
    }

    /// True when the theme supplied nothing — the renderer then keeps its
    /// built-in state colors.
    public var isEmpty: Bool {
        runningColor == nil && waitingOverlay == nil && waitingBorder == nil
            && waitingBorderWidth == nil && errorOverlay == nil
            && errorBorder == nil && errorBorderWidth == nil
    }
}

/// Turns a theme document into renderer inputs. Every field is optional: a
/// theme only overrides what it names, so an unchanged theme file cannot
/// silently blank out a provider.
public enum ThemeResolver {
    /// Full-size alpha used when a color is given without an opacity token.
    public static let defaultTrackAlpha: Double = 0.38
    public static let defaultBaselineAlpha: Double = 0.9
    public static let defaultOverlayAlpha: Double = 0.9
    public static let defaultSpectrumAlpha: Double = 0.9

    public static func palette(
        theme: ThemeDocument?,
        providerId: String,
        base: ProviderPalette
    ) -> ProviderPalette {
        guard let theme else { return base }

        var palette = base
        if let layers = theme.providers?[providerId]?.quotaLayers, !layers.isEmpty {
            let colors = layers.compactMap { ThemeColor(hex: $0).map { RGBAColor($0) } }
            if !colors.isEmpty {
                palette.outer = colors[0]
                palette.middle = colors.count > 1 ? colors[1] : colors[0]
                palette.inner = colors.count > 2 ? colors[2] : palette.middle
            }
        }
        if let track = theme.global?.trackColor.flatMap({ ThemeColor(hex: $0) }) {
            palette.track = RGBAColor(track, alpha: theme.global?.trackOpacity ?? defaultTrackAlpha)
        }
        if let baseline = theme.global?.baselineColor.flatMap({ ThemeColor(hex: $0) }) {
            palette.baseline = RGBAColor(baseline, alpha: theme.global?.baselineOpacity ?? defaultBaselineAlpha)
        }
        return palette
    }

    public static func effects(theme: ThemeDocument?, providerId: String) -> AgentEffectTheme? {
        guard let theme else { return nil }

        let provider = theme.providers?[providerId]
        let waiting = theme.states?["waiting"]
        let error = theme.states?["error"]

        let resolved = AgentEffectTheme(
            runningColor: provider?.spectrumColor
                .flatMap { ThemeColor(hex: $0) }
                .map { RGBAColor($0, alpha: provider?.spectrumOpacity ?? defaultSpectrumAlpha) },
            waitingOverlay: waiting?.overlayColor
                .flatMap { ThemeColor(hex: $0) }
                .map { RGBAColor($0, alpha: waiting?.overlayOpacity ?? defaultOverlayAlpha) },
            waitingBorder: waiting?.borderColor.flatMap { ThemeColor(hex: $0).map { RGBAColor($0) } },
            waitingBorderWidth: waiting?.borderWidth.map { CGFloat($0) },
            errorOverlay: error?.overlayColor
                .flatMap { ThemeColor(hex: $0) }
                .map { RGBAColor($0, alpha: error?.overlayOpacity ?? defaultOverlayAlpha) },
            errorBorder: error?.borderColor.flatMap { ThemeColor(hex: $0).map { RGBAColor($0) } },
            errorBorderWidth: error?.borderWidth.map { CGFloat($0) }
        )
        return resolved.isEmpty ? nil : resolved
    }
}

public extension RGBAColor {
    /// A theme color, with an explicit alpha when the theme supplies one.
    init(_ color: ThemeColor, alpha: Double? = nil) {
        self.init(red: color.red, green: color.green, blue: color.blue,
                  alpha: alpha ?? color.alpha)
    }
}
