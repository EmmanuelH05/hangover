import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// One picture on its way to the strip: what the camera saw, already
/// flipped and cut to its slot's shape, and the decorations that go over
/// it. Core Graphics images do not change once made, which is why this
/// may cross between tasks.
struct NookPhotoBoothPicture: @unchecked Sendable {
    let camera: CGImage
    var decorations: CGImage?
}

/// The picture work between the camera and the strip. Plain functions on
/// images, with no camera and no screen in them.
enum NookPhotoBoothImaging {
    /// Widest a prepared picture is kept. A 4 by 6 inch print at 300 dots
    /// an inch is 1200 across, which this covers.
    static let maxPictureWidth = 1400
    /// Width, in points, the decorations are laid out at before they are
    /// scaled to the picture. Close to the live mirror's width, which
    /// keeps line weights looking the way they did on screen.
    static let decorationLayoutWidth: CGFloat = 600

    /// The largest rectangle of a given shape that sits in the middle of a
    /// picture, in whole pixels. `aspect` is width over height.
    static func cropRect(imageWidth: Int, imageHeight: Int, aspect: CGFloat) -> CGRect {
        guard imageWidth > 0, imageHeight > 0, aspect > 0, aspect.isFinite else { return .zero }
        let imageAspect = CGFloat(imageWidth) / CGFloat(imageHeight)
        var width = CGFloat(imageWidth)
        var height = CGFloat(imageHeight)
        if imageAspect > aspect {
            // Too wide: keep the height, trim the sides.
            width = (height * aspect).rounded(.down)
        } else {
            height = (width / aspect).rounded(.down)
        }
        width = max(1, min(width, CGFloat(imageWidth)))
        height = max(1, min(height, CGFloat(imageHeight)))
        let x = ((CGFloat(imageWidth) - width) / 2).rounded(.down)
        let y = ((CGFloat(imageHeight) - height) / 2).rounded(.down)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// A camera still made ready for a slot: flipped left to right, which
    /// is how the mirror showed it, cut to the slot's shape from the
    /// middle, and scaled down when it is wider than a print needs.
    static func prepared(_ image: CGImage, aspect: CGFloat, maxWidth: Int = maxPictureWidth) -> CGImage? {
        let crop = cropRect(imageWidth: image.width, imageHeight: image.height, aspect: aspect)
        guard crop.width >= 1, crop.height >= 1 else { return nil }
        let scale = min(1, CGFloat(max(1, maxWidth)) / crop.width)
        let width = max(1, Int((crop.width * scale).rounded()))
        let height = max(1, Int((crop.height * scale).rounded()))
        guard let context = bitmapContext(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        // Flip about the vertical middle, then lay the whole picture down
        // with the crop's corner at the origin.
        context.translateBy(x: CGFloat(width), y: 0)
        context.scaleBy(x: -1, y: 1)
        let cropBottom = CGFloat(image.height) - crop.maxY
        context.draw(
            image,
            in: CGRect(
                x: -crop.minX * scale,
                y: -cropBottom * scale,
                width: CGFloat(image.width) * scale,
                height: CGFloat(image.height) * scale
            )
        )
        return context.makeImage()
    }

    /// Develops a picture the way a theme asks. Nil only when Core Image
    /// cannot draw, in which case the caller keeps the picture as it was.
    static func treated(_ image: CGImage, _ treatment: NookStripTreatment) -> CGImage? {
        if treatment.isUntouched { return image }
        let source = CIImage(cgImage: image)
        var picture = source
        switch treatment {
        case let .adjusted(saturation, contrast, brightness, wash):
            picture = filtered(picture, "CIColorControls", [
                kCIInputSaturationKey: saturation,
                kCIInputContrastKey: contrast,
                kCIInputBrightnessKey: brightness,
            ]) ?? picture
            if let wash, wash.alpha > 0 {
                let ink = CIImage(color: CIColor(red: wash.red, green: wash.green, blue: wash.blue, alpha: wash.alpha))
                    .cropped(to: source.extent)
                picture = filtered(ink, "CISoftLightBlendMode", [kCIInputBackgroundImageKey: picture]) ?? picture
            }
        case let .sepia(intensity, vignette):
            picture = filtered(picture, "CISepiaTone", [kCIInputIntensityKey: intensity]) ?? picture
            if vignette > 0 {
                picture = filtered(picture, "CIVignette", [
                    kCIInputIntensityKey: vignette * 2,
                    kCIInputRadiusKey: 1.5,
                ]) ?? picture
            }
        case let .duotone(dark, light, contrast):
            picture = filtered(picture, "CIColorControls", [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: contrast,
            ]) ?? picture
            picture = filtered(picture, "CIFalseColor", [
                "inputColor0": CIColor(red: dark.red, green: dark.green, blue: dark.blue),
                "inputColor1": CIColor(red: light.red, green: light.green, blue: light.blue),
            ]) ?? picture
        }
        return ciContext.createCGImage(picture, from: source.extent)
    }

    /// The part of the camera's picture a slot keeps, as fractions of the
    /// whole picture from its left and from its top.
    static func keptFractions(imageWidth: Int, imageHeight: Int, aspect: CGFloat) -> (x: ClosedRange<Double>, y: ClosedRange<Double>) {
        let crop = cropRect(imageWidth: imageWidth, imageHeight: imageHeight, aspect: aspect)
        guard crop.width >= 1, crop.height >= 1 else { return (0...1, 0...1) }
        let left = Double(crop.minX) / Double(imageWidth)
        let top = Double(crop.minY) / Double(imageHeight)
        return (
            left...(left + Double(crop.width) / Double(imageWidth)),
            top...(top + Double(crop.height) / Double(imageHeight))
        )
    }

    /// The mirror's decorations as they fall on a picture cut from the
    /// middle of the camera's view. A sticker stays on the same spot of
    /// the camera's picture and keeps its real size, and one whose middle
    /// falls outside the cut is left off. The frame is kept as it is: it
    /// is drawn again around the cut picture's own shape.
    static func decorations(
        _ decorations: NookMirrorDecorationSet,
        keptX: ClosedRange<Double>,
        keptY: ClosedRange<Double>
    ) -> NookMirrorDecorationSet {
        let spanX = keptX.upperBound - keptX.lowerBound
        let spanY = keptY.upperBound - keptY.lowerBound
        guard spanX > 0, spanY > 0 else { return decorations }
        var result = decorations
        result.stickers = decorations.stickers.compactMap { sticker in
            let x = (sticker.x - keptX.lowerBound) / spanX
            let y = (sticker.y - keptY.lowerBound) / spanY
            guard (0...1).contains(x), (0...1).contains(y) else { return nil }
            var moved = sticker
            moved.x = x
            moved.y = y
            moved.width = sticker.width / spanX
            return moved
        }
        return result
    }

    /// The same picture carried as JPEG data. A PDF keeps such a picture
    /// as the JPEG it is, which makes a strip a small file.
    static func jpegBacked(_ image: CGImage, quality: Double = 0.9) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data) else {
            return nil
        }
        return CGImage(
            jpegDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// PNG data for a picture, for the samples a test writes out.
    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The mirror's decorations drawn as a see-through picture of the
    /// given pixel size, to lay over a photo. Nil when there is nothing
    /// on the mirror, or nothing came out.
    @MainActor
    static func decorationImage(_ decorations: NookMirrorDecorationSet, pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        guard !decorations.isEmpty, pixelWidth > 0, pixelHeight > 0 else { return nil }
        let layoutHeight = decorationLayoutWidth * CGFloat(pixelHeight) / CGFloat(pixelWidth)
        let content = NookMirrorDecorationOverlay(decorations: decorations)
            .frame(width: decorationLayoutWidth, height: layoutHeight)
        let renderer = ImageRenderer(content: content)
        renderer.scale = CGFloat(pixelWidth) / decorationLayoutWidth
        renderer.isOpaque = false
        return renderer.cgImage
    }

    static func bitmapContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func filtered(_ image: CIImage, _ name: String, _ parameters: [String: Any]) -> CIImage? {
        guard let filter = CIFilter(name: name) else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in parameters { filter.setValue(value, forKey: key) }
        return filter.outputImage
    }
}
