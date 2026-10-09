import CoreGraphics
import Foundation
@testable import OpenIslandApp

/// Pictures made in code for the photo booth tests. No test takes one
/// from a camera.
enum PhotoBoothTestPictures {
    /// A camera-shaped picture whose left half is red and right half blue,
    /// with a green band along the top. Lopsided on purpose: a flip or an
    /// upside-down draw shows at once.
    static func lopsided(width: Int = 1280, height: Int = 720) -> CGImage {
        let context = NookPhotoBoothImaging.bitmapContext(width: width, height: height)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        // Core Graphics counts up from the bottom, which puts the top band here.
        context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height - height / 6, width: width, height: height / 6))
        return context.makeImage()!
    }

    /// A stand-in for a person at a desk: a wall, a head and shoulders, and
    /// a lamp on one side. `pose` moves the head a little, which makes four
    /// shots look like four shots.
    static func portrait(pose: Int, width: Int = 1280, height: Int = 720) -> CGImage {
        let context = NookPhotoBoothImaging.bitmapContext(width: width, height: height)!
        let w = CGFloat(width)
        let h = CGFloat(height)
        let walls: [(CGFloat, CGFloat, CGFloat)] = [(0.36, 0.52, 0.70), (0.70, 0.52, 0.42), (0.42, 0.62, 0.50), (0.60, 0.46, 0.66)]
        let wall = walls[pose % walls.count]
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(srgbRed: wall.0, green: wall.1, blue: wall.2, alpha: 1),
                CGColor(srgbRed: wall.0 * 0.55, green: wall.1 * 0.55, blue: wall.2 * 0.6, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])

        // A lamp on the left of the room.
        context.setFillColor(CGColor(srgbRed: 1, green: 0.86, blue: 0.5, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: w * 0.08, y: h * 0.62, width: w * 0.09, height: w * 0.09))

        let lean = CGFloat((pose % 4) - 1) * w * 0.035
        let bob = CGFloat(pose % 2) * h * 0.03
        // Shoulders.
        context.setFillColor(CGColor(srgbRed: 0.16, green: 0.18, blue: 0.26, alpha: 1))
        context.fillEllipse(in: CGRect(x: w * 0.30 + lean, y: -h * 0.42, width: w * 0.40, height: h * 0.78))
        // Head.
        let head = CGRect(x: w * 0.41 + lean, y: h * 0.36 + bob, width: w * 0.18, height: w * 0.20)
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.76, blue: 0.62, alpha: 1))
        context.fillEllipse(in: head)
        // Hair.
        context.setFillColor(CGColor(srgbRed: 0.20, green: 0.13, blue: 0.10, alpha: 1))
        context.fillEllipse(in: CGRect(x: head.minX - w * 0.005, y: head.midY + head.height * 0.12, width: head.width * 1.05, height: head.height * 0.48))
        // Eyes.
        context.setFillColor(CGColor(srgbRed: 0.12, green: 0.10, blue: 0.10, alpha: 1))
        for side in [CGFloat(0.32), 0.68] {
            context.fillEllipse(in: CGRect(x: head.minX + head.width * side - w * 0.008, y: head.midY - h * 0.01, width: w * 0.016, height: w * 0.016))
        }
        // A smile, wider on some poses.
        context.setStrokeColor(CGColor(srgbRed: 0.55, green: 0.20, blue: 0.22, alpha: 1))
        context.setLineWidth(w * 0.006)
        context.setLineCap(.round)
        let smile = head.width * (pose % 2 == 0 ? 0.20 : 0.28)
        context.move(to: CGPoint(x: head.midX - smile, y: head.minY + head.height * 0.30))
        context.addQuadCurve(
            to: CGPoint(x: head.midX + smile, y: head.minY + head.height * 0.30),
            control: CGPoint(x: head.midX, y: head.minY + head.height * 0.14)
        )
        context.strokePath()
        return context.makeImage()!
    }

    /// The color of one pixel, each part from 0 to 255. `x` and `y` count
    /// from the top left, the way the picture is looked at.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (red: Int, green: Int, blue: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Slide the picture until the wanted pixel sits on the one drawn.
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }
}
