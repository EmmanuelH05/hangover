import AppKit
import ImageIO
import QuartzCore
import SwiftUI

/// The frames of a GIF, decoded once and small, which Core Animation then
/// plays without asking the app again. `NSImageView` decoded every frame of
/// every loop on the main thread, at the file's full size: about a tenth of
/// a core for as long as music played with a GIF on the closed island.
struct GIFFrames: @unchecked Sendable {
    var images: [CGImage]
    /// How long each frame stays, in seconds. One for each image.
    var delays: [Double]

    var duration: Double { delays.reduce(0, +) }

    /// What the decoded frames take in memory, in bytes: the cost the cache
    /// counts for this GIF.
    var decodedBytes: Int { images.reduce(0) { $0 + $1.bytesPerRow * $1.height } }

    /// What a frame gets when the file gives it no time, or one too short
    /// to be meant: the tenth of a second browsers use.
    static let defaultDelay = 0.1
    /// A delay under this is read as "no delay given".
    static let shortestDelay = 0.02
    /// The longest side of a decoded frame, in pixels. The closed island
    /// shows the GIF small, even scaled up.
    static let largestSide = 192
    /// The smallest side the memory budget may bring a long GIF down to.
    static let smallestSide = 48
    /// What all the decoded frames of one GIF may take, in bytes.
    static let memoryBudget = 24 * 1024 * 1024

    /// A frame's delay from the two the file may carry.
    static func delay(unclamped: Double?, clamped: Double?) -> Double {
        let given = unclamped ?? clamped ?? 0
        return given < shortestDelay ? defaultDelay : given
    }

    /// Where each frame starts in the loop, from 0 to 1, with the end
    /// added: a discrete keyframe animation asks for one more time than it
    /// has values.
    static func keyTimes(for delays: [Double]) -> [Double] {
        let total = delays.reduce(0, +)
        guard total > 0 else { return [] }
        var elapsed = 0.0
        var times = [0.0]
        for delay in delays {
            elapsed += delay
            times.append(min(1, elapsed / total))
        }
        times[times.count - 1] = 1
        return times
    }

    /// The longest side to decode to, which keeps a GIF of many frames
    /// inside the memory budget. A count the budget cannot hold even at the
    /// smallest side is cut down first (`keptIndices`).
    static func side(frameCount: Int, budget: Int = memoryBudget) -> Int {
        guard frameCount > 0 else { return largestSide }
        let pixels = Double(budget) / Double(4 * frameCount)
        return max(smallestSide, min(largestSide, Int(pixels.squareRoot())))
    }

    /// Which frames to decode. All of them while the budget holds them at
    /// the smallest side, otherwise an evenly spread subset that does.
    static func keptIndices(frameCount: Int, budget: Int = memoryBudget) -> [Int] {
        let capacity = max(1, budget / (4 * smallestSide * smallestSide))
        guard frameCount > capacity else { return Array(0..<max(0, frameCount)) }
        return (0..<capacity).map { $0 * frameCount / capacity }
    }

    /// The delay of each kept frame: its own plus those of the frames
    /// dropped after it, which keeps the length of the loop.
    static func keptDelays(_ delays: [Double], kept: [Int]) -> [Double] {
        kept.enumerated().map { position, index in
            let end = position + 1 < kept.count ? kept[position + 1] : delays.count
            return delays[index..<end].reduce(0, +)
        }
    }

    /// The size a frame is drawn at: it fits `side` and is never enlarged.
    static func fitted(width: Int, height: Int, side: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > side, longest > 0 else { return (max(1, width), max(1, height)) }
        let scale = Double(side) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// Decodes every frame into a bitmap of its own. Nil for data that is
    /// not an image. Safe off the main thread.
    static func decode(_ data: Data, budget: Int = memoryBudget) -> GIFFrames? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        // More frames than the budget holds at the smallest side: keep an
        // evenly spread few, each showing as long as its dropped followers did.
        let kept = keptIndices(frameCount: count, budget: budget)
        let allDelays = (0..<count).map { delay(of: source, at: $0) }
        let shownFor = keptDelays(allDelays, kept: kept)
        let side = side(frameCount: kept.count, budget: budget)
        var images: [CGImage] = []
        var delays: [Double] = []
        for (position, index) in kept.enumerated() {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil),
                  let bitmap = bitmap(of: frame, side: side) else { continue }
            images.append(bitmap)
            delays.append(shownFor[position])
        }
        return images.isEmpty ? nil : GIFFrames(images: images, delays: delays)
    }

    /// Draws a frame small into memory, which is what makes it cost
    /// nothing later: the image Core Animation gets is already decoded.
    private static func bitmap(of frame: CGImage, side: Int) -> CGImage? {
        let size = fitted(width: frame.width, height: frame.height, side: side)
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(frame, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }

    private static func delay(of source: CGImageSource, at index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        return delay(
            unclamped: gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double,
            clamped: gif?[kCGImagePropertyGIFDelayTime] as? Double
        )
    }
}

/// The decoded GIFs kept, oldest first. Exact, unlike `NSCache`, which may
/// drop an entry whenever it likes: a GIF dropped behind the island's back
/// is decoded again, and a test of "decoded once" failed one run in four.
@MainActor
final class GIFFrameStore {
    let countLimit: Int
    let totalCostLimit: Int
    private var entries: [(url: URL, frames: GIFFrames)] = []

    init(countLimit: Int, totalCostLimit: Int) {
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
    }

    func frames(for url: URL) -> GIFFrames? {
        entries.first { $0.url == url }?.frames
    }

    /// Adds or replaces, then drops the oldest until both limits hold. The
    /// newest stays even when it alone is over the cost limit.
    func store(_ frames: GIFFrames, for url: URL) {
        entries.removeAll { $0.url == url }
        entries.append((url, frames))
        while entries.count > 1, entries.count > countLimit || totalCost > totalCostLimit {
            entries.removeFirst()
        }
    }

    private var totalCost: Int {
        entries.reduce(0) { $0 + $1.frames.decodedBytes }
    }
}

/// Decoded GIFs by file URL, so the same file is never decoded twice (the
/// island and the Settings preview show the same one). The file is read
/// and decoded off the main thread.
@MainActor
enum GIFFrameCache {
    /// Two GIFs at most, and no more decoded bytes than one GIF may take
    /// (`GIFFrames.memoryBudget`): the closed island shows one at a time.
    static let entryLimit = 2

    private static let cache = makeCache()

    static func makeCache() -> GIFFrameStore {
        GIFFrameStore(countLimit: entryLimit, totalCostLimit: GIFFrames.memoryBudget)
    }

    /// Puts `frames` in `cache` with its decoded size as the cost.
    static func store(_ frames: GIFFrames, for url: URL, in cache: GIFFrameStore) {
        cache.store(frames, for: url)
    }

    static func storedFrames(for url: URL, in cache: GIFFrameStore) -> GIFFrames? {
        cache.frames(for: url)
    }

    static func cachedFrames(for url: URL, in cache: GIFFrameStore = cache) -> GIFFrames? {
        storedFrames(for: url, in: cache)
    }

    /// The frames for `url`: from the cache, or read and decoded once. Nil
    /// when the file cannot be read or is not an image. The cache and the
    /// decoder are the app's own unless a test hands in others.
    static func frames(
        for url: URL,
        in cache: GIFFrameStore = cache,
        decode: @escaping @Sendable (Data) -> GIFFrames? = { GIFFrames.decode($0) }
    ) async -> GIFFrames? {
        if let cached = cachedFrames(for: url, in: cache) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            (try? Data(contentsOf: url)).flatMap(decode)
        }.value
        // A second request for the same file may have finished while this one read.
        if let cached = cachedFrames(for: url, in: cache) { return cached }
        guard let decoded else { return nil }
        store(decoded, for: url, in: cache)
        return decoded
    }
}

/// Plays an animated GIF as one Core Animation loop over frames that are
/// already decoded. SwiftUI's `Image` only ever shows the first frame. A new
/// URL keeps the old picture on screen until the new one has loaded.
struct AnimatedGIFView: NSViewRepresentable {
    let url: URL
    var isAnimating: Bool

    func makeNSView(context: Context) -> GIFLayerView {
        let view = GIFLayerView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setAnimating(isAnimating)
        context.coordinator.show(url, in: view)
        return view
    }

    func updateNSView(_ view: GIFLayerView, context: Context) {
        context.coordinator.show(url, in: view)
        view.setAnimating(isAnimating)
    }

    static func dismantleNSView(_ view: GIFLayerView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var url: URL?
        private var loadTask: Task<Void, Never>?
        /// Reads and decodes a file. A test hands in one it can hold back.
        private let load: (URL) async -> GIFFrames?

        init(load: @escaping (URL) async -> GIFFrames? = { await GIFFrameCache.frames(for: $0) }) {
            self.load = load
        }

        /// Shows `url` in `view`: at once when it is cached, otherwise after
        /// it has loaded. Does nothing when `url` is already the one shown.
        func show(_ url: URL, in view: GIFLayerView) {
            guard self.url != url else { return }
            self.url = url
            loadTask?.cancel()
            loadTask = nil

            if let cached = GIFFrameCache.cachedFrames(for: url) {
                view.show(cached)
                return
            }
            loadTask = Task { [weak self, weak view, load] in
                let frames = await load(url)
                guard !Task.isCancelled, let self, let view, self.url == url, let frames else { return }
                view.show(frames)
            }
        }

        func cancel() {
            loadTask?.cancel()
            loadTask = nil
        }
    }
}

/// The layer the GIF plays in. The loop is one keyframe animation of the
/// layer's contents, which the system steps through by itself: the app is
/// not woken for a frame.
final class GIFLayerView: NSView {
    private static let loopKey = "gif.loop"

    private var frames: GIFFrames?
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        layer.masksToBounds = true
        self.layer = layer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ frames: GIFFrames) {
        self.frames = frames
        apply()
    }

    /// Same value, nothing happens: a redraw never restarts the loop. Off
    /// freezes the frame on screen and on picks up from it.
    func setAnimating(_ isAnimating: Bool) {
        guard self.isAnimating != isAnimating else { return }
        self.isAnimating = isAnimating
        if isAnimating { resume() } else { pause() }
    }

    /// A layer taken off a window loses its animations.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, layer?.animation(forKey: Self.loopKey) == nil { apply() }
    }

    /// Whether the loop is stopped on a frame. For tests.
    var isPaused: Bool { layer?.speed == 0 }

    /// A layer taken off a window loses its animations; the loop is put
    /// back, from the first frame, only when it is gone.
    private func apply() {
        guard let layer else { return }
        layer.removeAnimation(forKey: Self.loopKey)
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        guard let frames, let first = frames.images.first else {
            layer.contents = nil
            return
        }
        layer.contents = first
        guard frames.images.count > 1, frames.duration > 0 else { return }

        let loop = CAKeyframeAnimation(keyPath: "contents")
        loop.values = frames.images
        loop.keyTimes = GIFFrames.keyTimes(for: frames.delays).map { NSNumber(value: $0) }
        loop.calculationMode = .discrete
        loop.duration = frames.duration
        loop.repeatCount = .infinity
        loop.isRemovedOnCompletion = false
        layer.add(loop, forKey: Self.loopKey)
        if !isAnimating { pause() }
    }

    /// Freezes the loop where it is: the layer's clock stops and keeps its
    /// reading, and the frame on screen stays.
    private func pause() {
        guard let layer, layer.speed != 0 else { return }
        layer.timeOffset = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
    }

    /// Starts the clock again from the reading it stopped at.
    private func resume() {
        guard let layer, layer.speed == 0 else { return }
        let pausedAt = layer.timeOffset
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.speed = 1
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
    }
}
