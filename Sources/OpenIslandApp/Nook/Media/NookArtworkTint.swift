import CoreGraphics
import Foundation
import ImageIO
import Observation

/// The dominant color of the current album art, for the music halo.
///
/// Watches the model's current artwork. A new track is looked up in a small
/// cache; on a miss the artwork bytes go to a utility-priority task that
/// shrinks them with ImageIO and runs `NookArtworkPalette`, so the main
/// thread never decodes an image.
@MainActor
@Observable
final class NookArtworkTintService {
    private(set) var tint: IslandHaloRGB?

    @ObservationIgnored private weak var nook: NookModel?
    @ObservationIgnored private var currentKey: String?
    @ObservationIgnored private var cache = NookArtworkTintCache(capacity: 8)
    @ObservationIgnored private var extraction: Task<Void, Never>?

    func start(nook: NookModel) {
        guard self.nook == nil else { return }
        self.nook = nook
        observeArtwork()
    }

    /// Re-registers observation on every change: `withObservationTracking`
    /// fires its `onChange` once per registration.
    private func observeArtwork() {
        let source = withObservationTracking {
            currentSource()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeArtwork()
            }
        }
        apply(source)
    }

    /// The same key `NookModel.artwork` caches its decoded image under.
    private func currentSource() -> NookArtworkSource? {
        guard let state = nook?.media.state, let data = state.artworkData else { return nil }
        return NookArtworkSource(key: "\(state.itemIdentifier ?? state.title)#\(data.count)", data: data)
    }

    private func apply(_ source: NookArtworkSource?) {
        guard source?.key != currentKey else { return }
        currentKey = source?.key
        extraction?.cancel()
        extraction = nil

        guard let source else {
            tint = nil
            return
        }
        if let cached = cache.value(for: source.key) {
            tint = cached.tint
            return
        }
        // Keep the old color until the new one is ready; a halo that fades
        // to nothing between tracks looks like a glitch.
        extraction = Task.detached(priority: .utility) { [weak self] in
            let color = NookArtworkPalette.glowTint(fromImageData: source.data)
            guard !Task.isCancelled else { return }
            await self?.finishExtraction(key: source.key, tint: color)
        }
    }

    private func finishExtraction(key: String, tint color: IslandHaloRGB?) {
        cache.insert(key: key, tint: color)
        guard key == currentKey else { return }
        tint = color
    }
}

/// Album art bytes plus the key that identifies the track. `Data` is
/// `Sendable`, so this crosses to the extraction task without copying.
private struct NookArtworkSource: Sendable {
    let key: String
    let data: Data
}

/// The last few extraction results, newest last. A nil tint is a result too
/// (gray art), so it is cached like any other.
struct NookArtworkTintCache {
    struct Entry: Equatable {
        let key: String
        let tint: IslandHaloRGB?
    }

    let capacity: Int
    private(set) var entries: [Entry] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// A hit moves the entry to the newest slot.
    mutating func value(for key: String) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry
    }

    mutating func insert(key: String, tint: IslandHaloRGB?) {
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, tint: tint))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }
}

/// Pure color math for album art.
enum NookArtworkPalette {
    /// Side of the square bitmap the art is reduced to before counting.
    static let sampleSide = 24
    /// Pixels brighter than this and more saturated than `minimumSaturation`
    /// count as colorful.
    static let minimumBrightness = 0.18
    static let minimumSaturation = 0.2
    static let minimumAlpha = 0.5
    static let hueBinCount = 18
    /// Share of the sample that must be colorful before the art has a hue.
    static let minimumColorfulShare = 0.03
    /// Longest side of the thumbnail the service decodes.
    static let thumbnailMaxPixelSize = 48

    /// Saturation and brightness range that glows well on black.
    static let glowSaturation = 0.35...0.85
    static let glowBrightness = 0.8...1.0

    /// The most prominent saturated hue, or nil for gray or very dark art.
    static func dominantColor(in image: CGImage) -> IslandHaloRGB? {
        let side = sampleSide
        let totalPixels = side * side
        guard let pixels = sampledPixels(of: image, side: side) else { return nil }

        var binWeight = [Double](repeating: 0, count: hueBinCount)
        var binRed = binWeight
        var binGreen = binWeight
        var binBlue = binWeight
        var colorfulPixels = 0

        for index in 0..<totalPixels {
            let offset = index * 4
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha >= minimumAlpha else { continue }
            // The bitmap is premultiplied; undo it so edges keep their color.
            let red = min(1, Double(pixels[offset]) / 255 / alpha)
            let green = min(1, Double(pixels[offset + 1]) / 255 / alpha)
            let blue = min(1, Double(pixels[offset + 2]) / 255 / alpha)

            let hsb = hsb(red: red, green: green, blue: blue)
            guard hsb.brightness >= minimumBrightness, hsb.saturation >= minimumSaturation else { continue }

            colorfulPixels += 1
            let bin = min(hueBinCount - 1, Int(hsb.hue * Double(hueBinCount)))
            let weight = hsb.saturation * hsb.brightness
            binWeight[bin] += weight
            binRed[bin] += red * weight
            binGreen[bin] += green * weight
            binBlue[bin] += blue * weight
        }

        guard Double(colorfulPixels) / Double(totalPixels) >= minimumColorfulShare else { return nil }

        var best = 0
        for bin in 1..<hueBinCount where binWeight[bin] > binWeight[best] {
            best = bin
        }
        let weight = binWeight[best]
        guard weight > 0 else { return nil }
        return IslandHaloRGB(red: binRed[best] / weight, green: binGreen[best] / weight, blue: binBlue[best] / weight)
    }

    /// Clamps a color into a range that glows well on black.
    static func glowSafe(_ color: IslandHaloRGB) -> IslandHaloRGB {
        let hsb = hsb(of: color)
        return rgb(
            hue: hsb.hue,
            saturation: min(max(hsb.saturation, glowSaturation.lowerBound), glowSaturation.upperBound),
            brightness: min(max(hsb.brightness, glowBrightness.lowerBound), glowBrightness.upperBound)
        )
    }

    /// The halo color for encoded art (PNG, JPEG, ...): a thumbnail of at
    /// most `thumbnailMaxPixelSize`, then `dominantColor`, then `glowSafe`.
    /// Does the decoding, so call it off the main thread.
    static func glowTint(fromImageData data: Data) -> IslandHaloRGB? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let dominant = dominantColor(in: thumbnail) else { return nil }
        return glowSafe(dominant)
    }

    // MARK: - Sampling

    /// `side` x `side` sRGB RGBA8 premultiplied pixels, row by row.
    private static func sampledPixels(of image: CGImage, side: Int) -> [UInt8]? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }

    // MARK: - HSB

    static func hsb(of color: IslandHaloRGB) -> (hue: Double, saturation: Double, brightness: Double) {
        hsb(red: color.red, green: color.green, blue: color.blue)
    }

    /// Hue in 0..<1.
    static func hsb(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let delta = high - low
        guard high > 0, delta > 0 else { return (0, 0, high) }

        let sector: Double
        if high == red {
            sector = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if high == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        var hue = sector / 6
        if hue < 0 { hue += 1 }
        return (min(hue, 1 - .ulpOfOne), delta / high, high)
    }

    static func rgb(hue: Double, saturation: Double, brightness: Double) -> IslandHaloRGB {
        let scaled = (hue - hue.rounded(.down)) * 6
        let sector = Int(scaled)
        let fraction = scaled - Double(sector)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        switch sector {
        case 0: return IslandHaloRGB(red: brightness, green: rising, blue: low)
        case 1: return IslandHaloRGB(red: falling, green: brightness, blue: low)
        case 2: return IslandHaloRGB(red: low, green: brightness, blue: rising)
        case 3: return IslandHaloRGB(red: low, green: falling, blue: brightness)
        case 4: return IslandHaloRGB(red: rising, green: low, blue: brightness)
        default: return IslandHaloRGB(red: brightness, green: low, blue: falling)
        }
    }
}
