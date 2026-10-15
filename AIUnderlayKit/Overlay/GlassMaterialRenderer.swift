import CoreGraphics
import Foundation

/// The rendered-glass softening used by the quota lane.
///
/// AIUnderlay deliberately never samples the desktop behind the menu bar (see
/// `docs/architecture.md`, "Glass = rendered, not sampled"), so
/// `blurRadiusTarget` is **not** a system backdrop-blur radius and this type
/// does not pretend to be one. It maps the token onto a real, measurable
/// softening of the *painted* glass material:
///
/// * `kernelRadiusPixels = softnessPoints × backingScale × kernelScale`
///   (`kernelScale = 0.5`, unit: device pixels). 0 stays crisp, the V5 default
///   17 softens over 8.5pt, and 32 over 16pt of material.
/// * A three-pass box blur approximates a Gaussian. It is applied to the
///   halo/reflection alpha only: quota edges, end caps, ray cores and attention
///   lines keep their crisp geometry, and the caller clips the texture so the
///   softened halo can never bleed into the black used-up bed.
/// * The bitmap is cached per (pixel size, backing scale, softness, tint), so a
///   quota poll or a colour-identical repaint reuses it; only a real parameter
///   change rasterises a new one.
@MainActor
public enum GlassMaterialRenderer {
    // MARK: - Tunables

    /// Legal range of the stored token, mirroring `GlassMaterialParameters`.
    public nonisolated static let maxSoftnessPoints: Double = 32
    /// Fraction of the softness token used as the kernel radius, at 1x.
    /// Named so the 0/17/32 → kernel mapping stays auditable.
    public nonisolated static let kernelScale: Double = 0.5
    /// The bitmap never exceeds these device-pixel bounds; wider lanes and
    /// taller bars stretch the texture instead of allocating a screen-sized one.
    public nonisolated static let maxTextureWidthPixels = 512
    public nonisolated static let maxTextureHeightPixels = 128
    /// Bounded cache. At the 512×128 maximum an entry is 256 KiB.
    public nonisolated static let maxCacheEntries = 16
    public nonisolated static let maxCacheBytes = 4 * 1024 * 1024
    /// Number of box passes; three passes read as a smooth Gaussian without a
    /// per-pixel falloff table.
    public nonisolated static let blurPasses = 3

    // MARK: - Softness math (pure; pinned by tests)

    /// Pure and `nonisolated`: the kernel math carries no state, so the
    /// `TextureKey` value type can compute its radii without hopping actors.
    public nonisolated static func clampedSoftness(_ points: Double) -> Double {
        min(max(points, 0), maxSoftnessPoints)
    }

    /// Kernel radius on the real device-pixel grid:
    /// `softnessPoints × backingScale × kernelScale`.
    ///
    /// The token is in **points**, so a 17pt target at 2x is a 17px kernel and
    /// at 1x an 8.5px kernel — never "17 device pixels" regardless of scale.
    public nonisolated static func kernelRadiusPixels(softnessPoints: Double, scale: CGFloat) -> Double {
        clampedSoftness(softnessPoints) * Double(max(scale, 0)) * kernelScale
    }

    /// 1D step response: how many pixels an edge needs to travel from 10% to
    /// 90% coverage once the material kernel is applied. 0 is a hard pixel
    /// edge; 17 and 32 widen it monotonically.
    public nonisolated static func edgeTransitionSpanPixels(softnessPoints: Double, scale: CGFloat) -> Double {
        let length = 512
        let radius = kernelRadiusPixels(softnessPoints: softnessPoints, scale: scale)
        guard radius > 0.05 else { return 0 }
        let step = (0..<length).map { $0 < length / 2 ? 0.0 : 1.0 }
        let profile = blurredAlpha(step, radius: radius, passes: blurPasses)
        guard let low = profile.firstIndex(where: { $0 >= 0.1 }),
              let high = profile.firstIndex(where: { $0 >= 0.9 })
        else { return 0 }
        return Double(high - low)
    }

    /// A three-pass box blur. Pixels outside the array contribute zero, so a
    /// softened edge brightens inward and cannot bleed past the caller's bounds.
    public nonisolated static func blurredAlpha(_ alpha: [Double], radius: Double, passes: Int = blurPasses) -> [Double] {
        guard !alpha.isEmpty, radius > 0.05, passes > 0 else { return alpha }
        var current = alpha
        for _ in 0..<passes {
            current = boxBlur(current, radius: radius)
        }
        return current
    }

    nonisolated static func boxBlur(_ values: [Double], radius: Double) -> [Double] {
        let count = values.count
        guard count > 0, radius > 0.05 else { return values }

        var prefix = [Double](repeating: 0, count: count + 1)
        for index in 0..<count {
            prefix[index + 1] = prefix[index] + values[index]
        }
        /// Inclusive sum of the in-range part of `range`; out-of-range reads as 0.
        func sum(_ from: Int, _ to: Int) -> Double {
            let low = max(0, from)
            let high = min(count - 1, to)
            guard low <= high else { return 0 }
            return prefix[high + 1] - prefix[low]
        }

        let wholeRadius = Int(radius.rounded(.down))
        let fraction = radius - Double(wholeRadius)
        var result = [Double](repeating: 0, count: count)
        for index in 0..<count {
            var total = sum(index - wholeRadius, index + wholeRadius)
            var weight = Double(2 * wholeRadius + 1)
            if fraction > 0 {
                total += fraction * (sum(index - wholeRadius - 1, index - wholeRadius - 1)
                                     + sum(index + wholeRadius + 1, index + wholeRadius + 1))
                weight += 2 * fraction
            }
            result[index] = weight > 0 ? total / weight : values[index]
        }
        return result
    }

    // MARK: - Texture keys and geometry

    /// Everything that changes the material bitmap. Softness and scale are
    /// quantized so a slider drag cannot thrash the cache between frames, and
    /// the *raw* device-pixel size is part of the key: two lanes wider than the
    /// texture cap must not share a bitmap whose stretch, and therefore whose
    /// kernel, differ. Rasterisation always reads the quantized values back out
    /// of the key, so a cache hit and a cache miss produce the same texture.
    public struct TextureKey: Hashable, Sendable {
        /// The lane's real device-pixel size, before the texture cap.
        public var rawPixelWidth: Int
        public var rawPixelHeight: Int
        /// Softness in 0.5pt steps.
        public var softnessStep: Int
        /// Backing scale in 0.01 steps.
        public var scaleStep: Int
        public var tintHex: String

        public init(
            rawPixelWidth: Int,
            rawPixelHeight: Int,
            softnessStep: Int,
            scaleStep: Int,
            tintHex: String
        ) {
            self.rawPixelWidth = rawPixelWidth
            self.rawPixelHeight = rawPixelHeight
            self.softnessStep = softnessStep
            self.scaleStep = scaleStep
            self.tintHex = tintHex
        }

        /// The bitmap size actually rasterised, both axes capped.
        public var pixelWidth: Int {
            min(max(rawPixelWidth, 2), GlassMaterialRenderer.maxTextureWidthPixels)
        }

        public var pixelHeight: Int {
            min(max(rawPixelHeight, 2), GlassMaterialRenderer.maxTextureHeightPixels)
        }

        /// The quantized softness this key stands for, in points.
        public var softnessPoints: Double { Double(softnessStep) * 0.5 }

        /// The quantized backing scale this key stands for.
        public var scale: CGFloat { CGFloat(Double(scaleStep) / 100) }

        /// Shrink factors applied by the texture cap, one per axis.
        public var horizontalStretch: Double {
            Double(pixelWidth) / Double(max(rawPixelWidth, 2))
        }

        public var verticalStretch: Double {
            Double(pixelHeight) / Double(max(rawPixelHeight, 2))
        }

        /// Kernel radius per axis, in the rasterised bitmap's own pixels, so a
        /// stretched texture still softens by the same number of *points* on
        /// screen.
        public var kernelRadiusX: Double {
            GlassMaterialRenderer.kernelRadiusPixels(softnessPoints: softnessPoints, scale: scale)
                * horizontalStretch
        }

        public var kernelRadiusY: Double {
            GlassMaterialRenderer.kernelRadiusPixels(softnessPoints: softnessPoints, scale: scale)
                * verticalStretch
        }
    }

    public nonisolated static func texturePixelSize(laneSize: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        let safeScale = Double(max(scale, 0))
        let width = min(max(Int((Double(laneSize.width) * safeScale).rounded()), 2), maxTextureWidthPixels)
        let height = min(max(Int((Double(laneSize.height) * safeScale).rounded()), 2), maxTextureHeightPixels)
        return (width, height)
    }

    public nonisolated static func textureKey(
        tint: RGBAColor,
        laneSize: CGSize,
        scale: CGFloat,
        softnessPoints: Double
    ) -> TextureKey {
        let safeScale = max(scale, 0)
        return TextureKey(
            rawPixelWidth: Int((Double(laneSize.width) * Double(safeScale)).rounded()),
            rawPixelHeight: Int((Double(laneSize.height) * Double(safeScale)).rounded()),
            softnessStep: Int((clampedSoftness(softnessPoints) / 0.5).rounded()),
            scaleStep: Int((Double(safeScale) * 100).rounded()),
            tintHex: tint.hexString
        )
    }

    // MARK: - Texture cache

    private struct CacheEntry {
        let image: CGImage
        let bytes: Int
        var lastUsed: UInt64
    }

    private static var cache: [TextureKey: CacheEntry] = [:]
    private static var clock: UInt64 = 0
    private static var rasterised = 0
    private static var reused = 0

    public static var cacheEntryCount: Int { cache.count }
    public static var cacheByteCount: Int { cache.values.reduce(0) { $0 + $1.bytes } }
    /// How many textures were actually rasterised since the last reset. A cache
    /// hit leaves it untouched — that is the "only a parameter change
    /// regenerates" contract.
    public static var textureGenerationCount: Int { rasterised }
    public static var cacheHitCount: Int { reused }

    public static func resetCache() {
        cache.removeAll()
        clock = 0
        rasterised = 0
        reused = 0
    }

    /// The pre-blurred halo/reflection for one lane. `laneSize` is the tint's
    /// own bounds in points; the returned texture is stretched across them.
    public static func haloImage(
        tint: RGBAColor,
        laneSize: CGSize,
        scale: CGFloat,
        softnessPoints: Double
    ) -> CGImage? {
        let key = textureKey(tint: tint, laneSize: laneSize, scale: scale, softnessPoints: softnessPoints)
        if let entry = cache[key] {
            clock &+= 1
            cache[key]?.lastUsed = clock
            reused &+= 1
            return entry.image
        }

        // Everything below reads the *quantized* key, never the raw call
        // arguments: two calls that share a key must also share a texture.
        // The per-axis radii absorb the cap's shrink, so a stretched bitmap
        // still softens by the same number of points on screen.
        guard let image = makeHaloImage(
            tint: tint,
            pixelWidth: key.pixelWidth,
            pixelHeight: key.pixelHeight,
            radiusX: key.kernelRadiusX,
            radiusY: key.kernelRadiusY
        ) else { return nil }

        store(key: key, image: image)
        return image
    }

    private static func store(key: TextureKey, image: CGImage) {
        clock &+= 1
        rasterised &+= 1
        cache[key] = CacheEntry(
            image: image,
            bytes: key.pixelWidth * key.pixelHeight * 4,
            lastUsed: clock
        )
        while cache.count > maxCacheEntries || cacheByteCount > maxCacheBytes,
              let oldest = cache.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            cache.removeValue(forKey: oldest)
        }
    }

    // MARK: - Rasterisation

    private static func makeHaloImage(
        tint: RGBAColor,
        pixelWidth: Int,
        pixelHeight: Int,
        radiusX: Double,
        radiusY: Double
    ) -> CGImage? {
        let width = max(2, pixelWidth)
        let height = max(2, pixelHeight)

        var field = radialBloomField(width: width, height: height)
        if radiusX > 0.05 || radiusY > 0.05 {
            field = blur2D(field, width: width, height: height, radiusX: radiusX, radiusY: radiusY)
        }
        // Normalise so softness spreads the reflection instead of dimming it:
        // the peak stays fully visible, only its width changes.
        let peak = field.max() ?? 0
        guard peak > 0 else { return nil }

        let tintAlpha = min(max(tint.alpha, 0), 1)
        let red = min(max(tint.red, 0), 1)
        let green = min(max(tint.green, 0), 1)
        let blue = min(max(tint.blue, 0), 1)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            let coverage = min(max(field[index] / peak, 0), 1) * tintAlpha
            let alpha = UInt8((coverage * 255).rounded())
            // Premultiplied so the bitmap is valid for Core Animation and for
            // an offscreen `CGContext.draw` in tests.
            bytes[index * 4 + 0] = UInt8((red * coverage * 255).rounded())
            bytes[index * 4 + 1] = UInt8((green * coverage * 255).rounded())
            bytes[index * 4 + 2] = UInt8((blue * coverage * 255).rounded())
            bytes[index * 4 + 3] = alpha
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// A soft reflection anchored slightly above centre, matching the V5
    /// `glass-tint` bloom's radial geometry.
    private static func radialBloomField(width: Int, height: Int) -> [Double] {
        var field = [Double](repeating: 0, count: width * height)
        let centerX = Double(width) * 0.5
        let centerY = Double(height) * 0.42
        let radiusX = max(1, Double(width) * 0.42)
        let radiusY = max(1, Double(height) * 0.62)
        for y in 0..<height {
            for x in 0..<width {
                let dx = (Double(x) + 0.5 - centerX) / radiusX
                let dy = (Double(y) + 0.5 - centerY) / radiusY
                let distance = (dx * dx + dy * dy).squareRoot()
                let falloff = max(0, 1 - distance)
                field[y * width + x] = falloff * falloff
            }
        }
        return field
    }

    private static func blur2D(
        _ values: [Double],
        width: Int,
        height: Int,
        radiusX: Double,
        radiusY: Double
    ) -> [Double] {
        guard (radiusX > 0.05 || radiusY > 0.05), width > 1, height > 1 else { return values }
        var current = values

        var line = [Double](repeating: 0, count: max(width, height))
        // Separable Gaussian approximation: the same three box passes along
        // each axis, so the 2D kernel matches the 1D profile the tests pin. The
        // two axes get their own radius because the texture cap shrinks the
        // width and the height by different factors.
        for y in 0..<height {
            for x in 0..<width { line[x] = current[y * width + x] }
            let blurred = blurredAlpha(Array(line[0..<width]), radius: radiusX, passes: blurPasses)
            for x in 0..<width { current[y * width + x] = blurred[x] }
        }
        for x in 0..<width {
            for y in 0..<height { line[y] = current[y * width + x] }
            let blurred = blurredAlpha(Array(line[0..<height]), radius: radiusY, passes: blurPasses)
            for y in 0..<height { current[y * width + x] = blurred[y] }
        }
        return current
    }
}
