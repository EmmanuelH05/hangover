import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

/// A GIF on the closed island is decoded once, small, and then played by
/// Core Animation. These are the rules of that one decode.
struct NookGIFFramesTests {
    @Test func aFrameWithNoDelayOrOneTooShortGetsATenthOfASecond() {
        #expect(GIFFrames.delay(unclamped: nil, clamped: nil) == 0.1)
        #expect(GIFFrames.delay(unclamped: 0.005, clamped: 0.1) == 0.1)
        #expect(GIFFrames.delay(unclamped: 0.05, clamped: 0.1) == 0.05)
        #expect(GIFFrames.delay(unclamped: nil, clamped: 0.2) == 0.2)
    }

    @Test func keyTimesRunFromZeroToOneWithOneMoreThanTheFrames() {
        #expect(GIFFrames.keyTimes(for: [0.1, 0.3]) == [0, 0.25, 1])
        #expect(GIFFrames.keyTimes(for: [0.2]) == [0, 1])
        #expect(GIFFrames.keyTimes(for: []).isEmpty)
    }

    @Test func aLongGIFIsDecodedSmallerToStayInsideTheBudget() {
        #expect(GIFFrames.side(frameCount: 1) == GIFFrames.largestSide)
        #expect(GIFFrames.side(frameCount: 60) == GIFFrames.largestSide)

        let long = GIFFrames.side(frameCount: 600)
        #expect(long < GIFFrames.largestSide)
        #expect(long >= GIFFrames.smallestSide)
        #expect(4 * long * long * 600 <= GIFFrames.memoryBudget)

        #expect(GIFFrames.side(frameCount: 100_000) == GIFFrames.smallestSide)
    }

    @Test func aFrameFitsTheSideAndIsNeverEnlarged() {
        let wide = GIFFrames.fitted(width: 400, height: 200, side: 192)
        #expect(wide.width == 192)
        #expect(wide.height == 96)

        let small = GIFFrames.fitted(width: 40, height: 30, side: 192)
        #expect(small.width == 40)
        #expect(small.height == 30)
    }

    @Test func everyFrameIsDecodedOnceAtTheSmallSize() throws {
        let data = try Self.gif(frames: 3, width: 400, height: 200, delay: 0.05)
        let frames = try #require(GIFFrames.decode(data))

        #expect(frames.images.count == 3)
        #expect(frames.delays.count == 3)
        #expect(frames.images.allSatisfy { $0.width == 192 && $0.height == 96 })
        #expect(frames.delays.allSatisfy { abs($0 - 0.05) < 0.001 })
        #expect(abs(frames.duration - 0.15) < 0.001)
    }

    @Test func dataThatIsNotAnImageDecodesToNothing() {
        #expect(GIFFrames.decode(Data("not a gif".utf8)) == nil)
        #expect(GIFFrames.decode(Data()) == nil)
    }

    /// A GIF of plain colored frames, made in memory.
    private static func gif(frames: Int, width: Int, height: Int, delay: Double) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames, nil)
        )
        let properties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ],
        ] as CFDictionary
        for index in 0..<frames {
            let context = try #require(CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(CGColor(red: CGFloat(index) / CGFloat(frames), green: 0.4, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// The swipe is a setting that starts off (D46). Off, no scroll event is
/// followed, wherever the pointer is.
struct IslandSwipeSettingTests {
    @Test func aScrollIsFollowedOnlyWhileTheSwipeIsOnAndThePointerIsOnTheIsland() {
        #expect(IslandPointerRules.swipeListens(isEnabled: true, isInClosedSurface: true, isInExpandedArea: false))
        #expect(IslandPointerRules.swipeListens(isEnabled: true, isInClosedSurface: false, isInExpandedArea: true))
        #expect(!IslandPointerRules.swipeListens(isEnabled: true, isInClosedSurface: false, isInExpandedArea: false))
        #expect(!IslandPointerRules.swipeListens(isEnabled: false, isInClosedSurface: true, isInExpandedArea: true))
    }

    @Test func theSettingHasOneKeyAndStartsOff() {
        #expect(IslandSwipeSetting.defaultsKey == "app.swipeGesturesEnabled")
        // Nothing has ever written the key in a test run.
        #expect(!IslandSwipeSetting.isEnabled)
    }
}
