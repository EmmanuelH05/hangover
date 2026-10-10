import AppKit
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
    }

    @Test func noFrameCountEverDecodesPastTheBudget() {
        let counts = [1, 2, 59, 60, 61, 600, 2_729, 2_730, 2_731, 5_000, 100_000, 1_000_000]
        for count in counts {
            let kept = GIFFrames.keptIndices(frameCount: count).count
            let side = GIFFrames.side(frameCount: kept)
            #expect(kept <= count, "\(count) frames")
            #expect(side >= GIFFrames.smallestSide && side <= GIFFrames.largestSide, "\(count) frames")
            #expect(4 * side * side * kept <= GIFFrames.memoryBudget, "\(count) frames kept \(kept) at \(side)")
        }
        // A count the budget holds is kept whole, and a count it cannot hold
        // is cut down to what fits at the smallest side.
        #expect(GIFFrames.keptIndices(frameCount: 2_730).count == 2_730)
        #expect(GIFFrames.keptIndices(frameCount: 100_000).count == 2_730)
        #expect(GIFFrames.keptIndices(frameCount: 0).isEmpty)
    }

    @Test func aGIFTooLongForTheBudgetKeepsAnEvenSpreadStartingAtTheFirstFrame() {
        let kept = GIFFrames.keptIndices(frameCount: 10, budget: 4 * 48 * 48 * 4)
        #expect(kept.count == 4)
        #expect(kept.first == 0)
        #expect(kept == kept.sorted() && Set(kept).count == kept.count)
        #expect(kept.last.map { $0 < 10 } == true)
        // The gaps differ by at most one frame.
        let gaps = zip(kept, kept.dropFirst()).map { $1 - $0 }
        #expect((gaps.max() ?? 0) - (gaps.min() ?? 0) <= 1)

        let huge = GIFFrames.keptIndices(frameCount: 100_000)
        let hugeGaps = zip(huge, huge.dropFirst()).map { $1 - $0 }
        #expect(huge.first == 0)
        #expect((hugeGaps.max() ?? 0) - (hugeGaps.min() ?? 0) <= 1)
    }

    @Test func eachKeptFrameShowsForTheFramesDroppedAfterItSoTheLoopKeepsItsLength() {
        // Ten frames of different lengths, four kept.
        let delays = (0..<10).map { 0.02 * Double($0 + 1) }
        let kept = GIFFrames.keptIndices(frameCount: 10, budget: 4 * 48 * 48 * 4)
        let shown = GIFFrames.keptDelays(delays, kept: kept)

        #expect(shown.count == kept.count)
        for (position, index) in kept.enumerated() {
            let end = position + 1 < kept.count ? kept[position + 1] : delays.count
            #expect(abs(shown[position] - delays[index..<end].reduce(0, +)) < 1e-9)
        }
        #expect(abs(shown.reduce(0, +) - delays.reduce(0, +)) < 1e-9)

        // And at the size the budget really cuts.
        let many = (0..<100_000).map { 0.02 * Double($0 % 7 + 1) }
        let manyKept = GIFFrames.keptIndices(frameCount: many.count)
        let manyShown = GIFFrames.keptDelays(many, kept: manyKept)
        #expect(manyShown.count == manyKept.count)
        #expect(abs(manyShown.reduce(0, +) - many.reduce(0, +)) < 1e-6)
    }

    @Test func aDecodedGIFTooLongForItsBudgetStaysInsideItAndKeepsItsDuration() throws {
        // Room for three frames at the smallest side, for a GIF of twelve.
        let budget = 3 * 4 * GIFFrames.smallestSide * GIFFrames.smallestSide
        let data = try Self.gif(frames: 12, width: 100, height: 100, delay: 0.05)
        let frames = try #require(GIFFrames.decode(data, budget: budget))

        #expect(frames.images.count == 3)
        #expect(frames.decodedBytes <= budget)
        #expect(abs(frames.duration - 12 * 0.05) < 0.001)
        #expect(frames.delays.allSatisfy { abs($0 - 4 * 0.05) < 0.001 })
        // The frames kept are the first of each four: three different colors, in order.
        let reds = frames.images.map { Self.color(of: $0).red }
        #expect(reds[0] < reds[1] && reds[1] < reds[2])
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

        // Three copies of the first frame would pass all of that. The frames
        // are the file's own three, with the red the file gave each, in order.
        let reds = frames.images.map { Self.color(of: $0).red }
        #expect(reds[1] - reds[0] > 40)
        #expect(reds[2] - reds[1] > 40)
        let blues = frames.images.map { Self.color(of: $0).blue }
        #expect(blues.allSatisfy { abs($0 - blues[0]) < 12 }, "the blue is the same in every frame")
    }

    @Test func dataThatIsNotAnImageDecodesToNothing() {
        #expect(GIFFrames.decode(Data("not a gif".utf8)) == nil)
        #expect(GIFFrames.decode(Data()) == nil)
    }

    /// The color a plain frame has, from the whole picture drawn into one
    /// pixel. Each channel is 0 to 255.
    fileprivate static func color(of image: CGImage) -> (red: Int, green: Int, blue: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    /// A GIF of plain colored frames, made in memory.
    fileprivate static func gif(frames: Int, width: Int, height: Int, delay: Double) throws -> Data {
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

    @Test func theSettingHasOneKey() {
        #expect(IslandSwipeSetting.defaultsKey == "app.swipeGesturesEnabled")
    }

    /// The scroll monitors are separate from the mouse ones: they come and go
    /// with the setting, and a scroll costs the app nothing while none exist.
    @MainActor
    @Test func theScrollMonitorsComeAndGoOnTheirOwn() {
        let monitors = NotchEventMonitors()
        #expect(monitors.hasScrollMonitors == false)
        monitors.startScroll { _, _, _, _, _ in false }
        #expect(monitors.hasScrollMonitors)
        #expect(monitors.isActive == false)
        monitors.stopScroll()
        #expect(monitors.hasScrollMonitors == false)
    }

    /// With no mouse monitors running there is nothing to add to, and the
    /// controller installs no scroll monitor either.
    @MainActor
    @Test func theControllerInstallsNoScrollMonitorBeforeTheMouseOnes() {
        let controller = OverlayPanelController()
        controller.setSwipeMonitoring(enabled: true)
        #expect(controller.hasScrollMonitors == false)
        controller.setSwipeMonitoring(enabled: false)
        #expect(controller.hasScrollMonitors == false)
    }
}

/// Pausing the GIF keeps the frame on screen, and a cache of decoded GIFs
/// holds what the island can afford (D48).
@MainActor
struct GIFPlaybackTests {
    private static func frames() throws -> GIFFrames {
        try #require(GIFFrames.decode(NookGIFFramesTests.gif(frames: 4, width: 40, height: 40, delay: 0.5)))
    }

    private static func loaded(animating: Bool) throws -> GIFLayerView {
        let view = GIFLayerView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        view.setAnimating(animating)
        view.show(try frames())
        return view
    }

    @Test func pausingFreezesTheLoopWhereItIsAndKeepsIt() throws {
        let view = try Self.loaded(animating: true)
        let layer = try #require(view.layer)
        #expect(layer.speed == 1)
        #expect(layer.animationKeys()?.isEmpty == false)

        view.setAnimating(false)

        // The loop is still on the layer and its clock stopped at a reading.
        #expect(layer.animationKeys()?.isEmpty == false)
        #expect(layer.speed == 0)
        #expect(layer.timeOffset > 0)
        let frozenAt = layer.timeOffset
        Thread.sleep(forTimeInterval: 0.05)
        #expect(layer.timeOffset == frozenAt)
    }

    @Test func resumingPicksUpFromTheFrozenReading() throws {
        let view = try Self.loaded(animating: true)
        let layer = try #require(view.layer)
        view.setAnimating(false)
        let frozenAt = layer.timeOffset

        view.setAnimating(true)

        #expect(layer.speed == 1)
        #expect(layer.timeOffset == 0)
        // The layer's own time, as the loop sees it, starts at the reading it froze at.
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        #expect(abs(now - layer.beginTime - frozenAt) < 0.05)
        #expect(layer.beginTime != 0)
        #expect(layer.animationKeys()?.isEmpty == false)
    }

    @Test func aGIFShownWhilePausedStaysOnItsFirstFrame() throws {
        let view = try Self.loaded(animating: false)
        let layer = try #require(view.layer)
        #expect(view.isPaused)
        #expect(layer.animationKeys()?.isEmpty == false)
        #expect(layer.contents != nil)
    }

    @Test func aNewGIFStartsFromItsFirstFrame() throws {
        let view = try Self.loaded(animating: true)
        let layer = try #require(view.layer)
        view.setAnimating(false)
        view.setAnimating(true)
        #expect(layer.beginTime != 0)

        view.show(try Self.frames())

        #expect(layer.beginTime == 0)
        #expect(layer.timeOffset == 0)
        #expect(layer.speed == 1)
    }

    @Test func theCacheKeepsTwoGIFsAndCountsDecodedBytes() throws {
        let cache = GIFFrameCache.makeCache()
        #expect(cache.countLimit == 2)
        #expect(GIFFrameCache.entryLimit == 2)
        #expect(cache.totalCostLimit == GIFFrames.memoryBudget)

        let frames = try Self.frames()
        // 4 frames of 40 by 40 pixels at 4 bytes each, rows padded at most.
        #expect(frames.decodedBytes >= 4 * 40 * 40 * 4)
        let url = URL(fileURLWithPath: "/tmp/one.gif")
        GIFFrameCache.store(frames, for: url, in: cache)
        #expect(GIFFrameCache.storedFrames(for: url, in: cache)?.images.count == 4)
    }

    // MARK: The cache and changing the GIF

    /// A folder of its own under the temporary directory, with GIF files in it.
    private static func folder(_ names: [String: (frames: Int, side: Int)]) throws -> (folder: URL, urls: [String: URL]) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("gif-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [String: URL] = [:]
        for (name, shape) in names {
            let url = folder.appendingPathComponent(name)
            try NookGIFFramesTests.gif(frames: shape.frames, width: shape.side, height: shape.side, delay: 0.1).write(to: url)
            urls[name] = url
        }
        return (folder, urls)
    }

    private final class DecodeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func decode(_ data: Data) -> GIFFrames? {
            lock.withLock { value += 1 }
            return GIFFrames.decode(data)
        }
    }

    @Test func aSecondRequestForTheSameFileDoesNotDecodeItAgain() async throws {
        let (folder, urls) = try Self.folder(["a.gif": (3, 40)])
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try #require(urls["a.gif"])
        let cache = GIFFrameCache.makeCache()
        let counter = DecodeCounter()

        let first = await GIFFrameCache.frames(for: url, in: cache, decode: counter.decode)
        let second = await GIFFrameCache.frames(for: url, in: cache, decode: counter.decode)

        #expect(first?.images.count == 3)
        #expect(second?.images.count == 3)
        #expect(counter.count == 1)
        #expect(GIFFrameCache.cachedFrames(for: url, in: cache)?.images.count == 3)
    }

    @Test func aMissingFileGivesNothingAndIsNotCached() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).gif")
        let cache = GIFFrameCache.makeCache()
        let counter = DecodeCounter()

        let frames = await GIFFrameCache.frames(for: url, in: cache, decode: counter.decode)

        #expect(frames == nil)
        #expect(counter.count == 0, "nothing was read, nothing was decoded")
        #expect(GIFFrameCache.cachedFrames(for: url, in: cache) == nil)
    }

    @Test func aFileThatIsNotAnImageGivesNothing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gif-cache-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("text.gif")
        try Data("not a gif".utf8).write(to: url)
        let cache = GIFFrameCache.makeCache()

        #expect(await GIFFrameCache.frames(for: url, in: cache) == nil)
        #expect(GIFFrameCache.cachedFrames(for: url, in: cache) == nil)
    }

    /// Holds a load until the test lets it go.
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }

    /// The width of the picture the view shows, nil with none.
    private static func shownWidth(_ view: GIFLayerView) -> Int? {
        guard let contents = view.layer?.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return nil }
        return (contents as! CGImage).width
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func theLateLoadOfAnEarlierGIFNeverReplacesTheOneShownAfterIt() async throws {
        let a = FileManager.default.temporaryDirectory.appendingPathComponent("gif-a.gif")
        let b = FileManager.default.temporaryDirectory.appendingPathComponent("gif-b.gif")
        let framesA = try #require(GIFFrames.decode(NookGIFFramesTests.gif(frames: 2, width: 40, height: 40, delay: 0.5)))
        let framesB = try #require(GIFFrames.decode(NookGIFFramesTests.gif(frames: 2, width: 30, height: 30, delay: 0.5)))
        let gate = Gate()
        var aFinished = false
        let coordinator = AnimatedGIFView.Coordinator { url in
            if url == a {
                await gate.wait()
                aFinished = true
                return framesA
            }
            return framesB
        }
        let view = GIFLayerView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))

        coordinator.show(a, in: view)
        coordinator.show(b, in: view)
        try await Self.waitUntil { Self.shownWidth(view) == 30 }
        #expect(Self.shownWidth(view) == 30, "b is on screen")

        // a's read finishes now, after b was shown.
        await gate.open()
        try await Self.waitUntil { aFinished }
        try await Task.sleep(for: .milliseconds(50))

        #expect(aFinished)
        #expect(Self.shownWidth(view) == 30, "a did not replace b")
    }

    @Test func showingTheSameGIFAgainDoesNotLoadItAgain() async throws {
        let a = FileManager.default.temporaryDirectory.appendingPathComponent("gif-a.gif")
        let framesA = try Self.frames()
        var loads = 0
        let coordinator = AnimatedGIFView.Coordinator { _ in
            loads += 1
            return framesA
        }
        let view = GIFLayerView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))

        coordinator.show(a, in: view)
        coordinator.show(a, in: view)
        try await Self.waitUntil { view.layer?.contents != nil }

        #expect(loads == 1)
    }
}

/// The store behind the decoded GIFs is exact: what it keeps and what it
/// drops never depends on the system's mood.
@MainActor
struct GIFFrameStoreTests {
    private static func frames(side: Int, count: Int) -> GIFFrames {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        return GIFFrames(images: Array(repeating: image, count: count), delays: Array(repeating: 0.1, count: count))
    }

    @Test func theOldestGoesWhenAThirdArrives() {
        let store = GIFFrameStore(countLimit: 2, totalCostLimit: 1_000_000)
        let urls = ["a", "b", "c"].map { URL(fileURLWithPath: "/tmp/\($0).gif") }
        for url in urls { store.store(Self.frames(side: 8, count: 2), for: url) }

        #expect(store.frames(for: urls[0]) == nil)
        #expect(store.frames(for: urls[1])?.images.count == 2)
        #expect(store.frames(for: urls[2])?.images.count == 2)
    }

    @Test func theOldestGoesWhenTheCostPassesTheLimit() {
        let one = Self.frames(side: 16, count: 4)
        let store = GIFFrameStore(countLimit: 5, totalCostLimit: one.decodedBytes + 1)
        let first = URL(fileURLWithPath: "/tmp/first.gif")
        let second = URL(fileURLWithPath: "/tmp/second.gif")
        store.store(one, for: first)
        store.store(one, for: second)

        #expect(store.frames(for: first) == nil)
        #expect(store.frames(for: second)?.images.count == 4)
    }

    @Test func theNewestStaysEvenWhenItAloneIsOverTheLimit() {
        let big = Self.frames(side: 32, count: 4)
        let store = GIFFrameStore(countLimit: 2, totalCostLimit: 10)
        let url = URL(fileURLWithPath: "/tmp/big.gif")
        store.store(big, for: url)

        #expect(store.frames(for: url)?.images.count == 4)
    }

    @Test func storingTheSameFileAgainReplacesIt() {
        let store = GIFFrameStore(countLimit: 2, totalCostLimit: 1_000_000)
        let url = URL(fileURLWithPath: "/tmp/same.gif")
        store.store(Self.frames(side: 8, count: 2), for: url)
        store.store(Self.frames(side: 8, count: 5), for: url)

        #expect(store.frames(for: url)?.images.count == 5)
    }
}
