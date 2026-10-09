import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

@Suite struct NookArtworkTintTests {
    private typealias Pixel = (red: UInt8, green: UInt8, blue: UInt8)

    private static let red: Pixel = (255, 0, 0)
    private static let green: Pixel = (0, 255, 0)
    private static let blue: Pixel = (0, 0, 255)
    private static let black: Pixel = (0, 0, 0)

    /// An opaque sRGB image, `side` pixels square, one color per pixel.
    /// 24 matches the palette's sample size, so nothing is resampled.
    private static func makeImage(side: Int = 24, alpha: UInt8 = 255, _ pixel: (Int, Int) -> Pixel) -> CGImage {
        var bytes = [UInt8]()
        bytes.reserveCapacity(side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let color = pixel(x, y)
                // Premultiplied RGBA.
                let scale = Double(alpha) / 255
                bytes.append(UInt8((Double(color.red) * scale).rounded()))
                bytes.append(UInt8((Double(color.green) * scale).rounded()))
                bytes.append(UInt8((Double(color.blue) * scale).rounded()))
                bytes.append(alpha)
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private static func solid(_ color: Pixel, side: Int = 24) -> CGImage {
        makeImage(side: side) { _, _ in color }
    }

    /// `patch` pixels wide and tall in the corner, black everywhere else.
    private static func patch(_ color: Pixel, width: Int, height: Int) -> CGImage {
        makeImage { x, y in x < width && y < height ? color : black }
    }

    private static func pngData(of image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func isClose(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.02) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    // MARK: dominantColor

    @Test func solidRedGivesRed() {
        let color = NookArtworkPalette.dominantColor(in: Self.solid(Self.red))

        #expect(color != nil)
        #expect((color?.red ?? 0) > 0.95)
        #expect((color?.green ?? 1) < 0.05)
        #expect((color?.blue ?? 1) < 0.05)
    }

    @Test func halfRedHalfBlackGivesRed() {
        let image = Self.makeImage { x, _ in x < 12 ? Self.red : Self.black }

        let color = NookArtworkPalette.dominantColor(in: image)

        #expect(color != nil)
        #expect((color?.red ?? 0) > 0.95)
        #expect((color?.green ?? 1) < 0.05)
    }

    @Test func theLargerHueWins() {
        // Two thirds green, one third blue.
        let image = Self.makeImage { x, _ in x < 16 ? Self.green : Self.blue }

        let color = NookArtworkPalette.dominantColor(in: image)

        #expect((color?.green ?? 0) > 0.95)
        #expect((color?.blue ?? 1) < 0.05)
    }

    @Test func grayscaleGradientHasNoColor() {
        let image = Self.makeImage { x, _ in
            let level = UInt8(x * 255 / 23)
            return (level, level, level)
        }

        #expect(NookArtworkPalette.dominantColor(in: image) == nil)
    }

    @Test func veryDarkColorIsIgnored() {
        // Saturated but brightness 40/255 is under the 0.18 floor.
        #expect(NookArtworkPalette.dominantColor(in: Self.solid((40, 0, 0))) == nil)
    }

    @Test func fadedColorIsIgnored() {
        // Saturation (255 - 220) / 255 is under the 0.2 floor.
        #expect(NookArtworkPalette.dominantColor(in: Self.solid((255, 220, 220))) == nil)
    }

    @Test func transparentArtHasNoColor() {
        #expect(NookArtworkPalette.dominantColor(in: Self.makeImage(alpha: 0) { _, _ in Self.red }) == nil)
    }

    @Test func colorfulPatchUnderThreePercentGivesNil() {
        // 4 x 4 is 16 of 576 pixels, 2.8 percent.
        #expect(NookArtworkPalette.dominantColor(in: Self.patch(Self.red, width: 4, height: 4)) == nil)
    }

    @Test func colorfulPatchAtThreePercentGivesColor() {
        // 6 x 3 is 18 of 576 pixels, 3.1 percent.
        let color = NookArtworkPalette.dominantColor(in: Self.patch(Self.red, width: 6, height: 3))

        #expect((color?.red ?? 0) > 0.95)
    }

    // MARK: glowSafe

    @Test func glowSafeLiftsDarkMutedColors() {
        let result = NookArtworkPalette.glowSafe(IslandHaloRGB(red: 0.2, green: 0.1, blue: 0.1))
        let hsb = NookArtworkPalette.hsb(of: result)

        #expect(isClose(hsb.brightness, 0.8, tolerance: 0.001))
        #expect(isClose(hsb.saturation, 0.5, tolerance: 0.001))
        #expect(isClose(hsb.hue, 0, tolerance: 0.001))
    }

    @Test func glowSafeSoftensFullSaturation() {
        let result = NookArtworkPalette.glowSafe(IslandHaloRGB(red: 0, green: 0, blue: 1))
        let hsb = NookArtworkPalette.hsb(of: result)

        #expect(isClose(hsb.saturation, 0.85, tolerance: 0.001))
        #expect(isClose(hsb.brightness, 1, tolerance: 0.001))
        #expect(isClose(hsb.hue, 2.0 / 3.0, tolerance: 0.001))
    }

    @Test func glowSafeAddsColorToGray() {
        let hsb = NookArtworkPalette.hsb(of: NookArtworkPalette.glowSafe(IslandHaloRGB(red: 0.5, green: 0.5, blue: 0.5)))

        #expect(hsb.saturation >= 0.35 - 0.001)
        #expect(hsb.brightness >= 0.8 - 0.001)
    }

    @Test func glowSafeLeavesColorsInRangeAlone() {
        let color = IslandHaloRGB(red: 0.9, green: 0.5, blue: 0.4)

        let result = NookArtworkPalette.glowSafe(color)

        #expect(isClose(result.red, color.red, tolerance: 0.0001))
        #expect(isClose(result.green, color.green, tolerance: 0.0001))
        #expect(isClose(result.blue, color.blue, tolerance: 0.0001))
    }

    @Test func hsbRoundTripsThroughRGB() {
        let colors = [
            IslandHaloRGB(red: 0.9, green: 0.2, blue: 0.1),
            IslandHaloRGB(red: 0.1, green: 0.8, blue: 0.3),
            IslandHaloRGB(red: 0.3, green: 0.2, blue: 0.95),
            IslandHaloRGB(red: 0.7, green: 0.7, blue: 0.2),
        ]
        for color in colors {
            let hsb = NookArtworkPalette.hsb(of: color)
            let back = NookArtworkPalette.rgb(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)

            #expect(isClose(back.red, color.red, tolerance: 0.0001))
            #expect(isClose(back.green, color.green, tolerance: 0.0001))
            #expect(isClose(back.blue, color.blue, tolerance: 0.0001))
        }
    }

    // MARK: Encoded art

    @Test func encodedRedArtGlowsRedWithinTheSafeRange() {
        let data = Self.pngData(of: Self.solid(Self.red, side: 200))

        let tint = NookArtworkPalette.glowTint(fromImageData: data)

        #expect(tint != nil)
        let hsb = tint.map(NookArtworkPalette.hsb(of:))
        #expect(isClose(hsb?.hue ?? 0.5, 0, tolerance: 0.01))
        #expect((hsb?.saturation ?? 0) <= 0.85 + 0.001)
        #expect((hsb?.brightness ?? 0) >= 0.8 - 0.001)
    }

    @Test func dataThatIsNotAnImageHasNoTint() {
        #expect(NookArtworkPalette.glowTint(fromImageData: Data("not an image".utf8)) == nil)
    }

    // MARK: Cache

    @Test func cacheKeepsOnlyTheNewestEntries() {
        var cache = NookArtworkTintCache(capacity: 8)
        for number in 0..<10 {
            cache.insert(key: "track\(number)", tint: nil)
        }

        #expect(cache.entries.count == 8)
        #expect(cache.value(for: "track0") == nil)
        #expect(cache.value(for: "track1") == nil)
        #expect(cache.value(for: "track9") != nil)
    }

    @Test func cacheHitKeepsTheEntryFromBeingEvicted() {
        var cache = NookArtworkTintCache(capacity: 2)
        cache.insert(key: "a", tint: .running)
        cache.insert(key: "b", tint: nil)

        let hit = cache.value(for: "a")
        cache.insert(key: "c", tint: nil)

        #expect(hit?.tint == .running)
        #expect(cache.value(for: "a") != nil)
        #expect(cache.value(for: "b") == nil)
    }

    @Test func cacheRemembersThatArtHadNoColor() {
        var cache = NookArtworkTintCache(capacity: 8)
        cache.insert(key: "gray", tint: nil)

        let hit = cache.value(for: "gray")

        #expect(hit != nil)
        #expect(hit?.tint == nil)
    }
}
