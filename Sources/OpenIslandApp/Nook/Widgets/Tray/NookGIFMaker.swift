import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the GIF sheet asks for (D68).
struct NookGIFOptions: Equatable, Sendable {
    enum Width: Int, CaseIterable, Identifiable, Sendable {
        case small = 480
        case medium = 720
        case large = 1080
        var id: Int { rawValue }
    }

    static let frameRates = [10, 15, 24]

    var width: Width = .medium
    var framesPerSecond = 15
}

enum NookGIFError: Error, Equatable, Sendable {
    case unreadable
    case tooLong
    case writeFailed
    /// Too much of the video would not decode. The GIF would have frozen on
    /// one picture for a stretch, so none is made.
    case decodeFailed
    case cancelled
}

/// Counts the frames a GIF repeated because the video would not give them
/// up, and says when that is too many to call the result a copy of the video.
struct NookGIFDecodeTally: Equatable, Sendable {
    /// More than this share of the frames, in percent, fails the GIF.
    static let maxRepeatedPercent = 10

    private(set) var repeatedCount = 0
    private(set) var longestRun = 0
    /// Domain and code of the first error that made a frame repeat.
    private(set) var firstCause: String?
    private var run = 0

    mutating func recordDecoded() {
        run = 0
    }

    mutating func recordRepeated(cause: String) {
        repeatedCount += 1
        run += 1
        longestRun = max(longestRun, run)
        if firstCause == nil { firstCause = cause }
    }

    /// True when the repeats are over a tenth of the `total` frames, or one
    /// unbroken run of them lasts over a second at `framesPerSecond`.
    func exceedsLimits(total: Int, framesPerSecond: Int) -> Bool {
        guard total > 0, framesPerSecond > 0 else { return false }
        return repeatedCount * 100 > total * Self.maxRepeatedPercent || longestRun > framesPerSecond
    }
}

/// What the maker and the sheet need to know about a video: how long it
/// runs and how big it looks on screen (the track's own turn already
/// applied, so a phone video held upright is taller than wide).
struct NookGIFSource: Equatable, Sendable {
    var duration: TimeInterval
    var size: CGSize
}

/// Makes a looping GIF from a video (D68). Frames come from
/// `AVAssetImageGenerator`, decoded at the GIF's size, and ImageIO writes
/// them. The video is only read: the GIF is always a new file.
enum NookGIFMaker {
    /// Clips longer than this are refused.
    static let maxDuration: TimeInterval = 120

    /// A rough guess for screen content: a GIF frame costs about this many
    /// bytes a pixel once ImageIO has squeezed it into a 256 color palette
    /// and LZW. A photo costs more and a flat screen far less, which is why
    /// the sheet says "about".
    static let estimatedBytesPerPixel = 0.3

    /// The most pixels, over all the frames, that go to ImageIO at once.
    /// ImageIO builds one palette for the frames it is given and holds
    /// every one of them, at about ten bytes a pixel, until it is told to
    /// finish. A two minute clip in one piece would ask for gigabytes, so
    /// frames go in pieces of about this many pixels (about 120 MB), and
    /// the pieces are joined into one file as they are made.
    static let maxPiecePixels = 12_000_000

    static func make(
        from source: URL,
        to destination: URL,
        options: NookGIFOptions,
        maxDuration: TimeInterval = NookGIFMaker.maxDuration,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await makeBounded(
            from: source, to: destination, options: options, maxDuration: maxDuration,
            maxPiecePixels: maxPiecePixels, progress: progress
        )
    }

    /// `make` with the size of a piece (see `maxPiecePixels`) as a
    /// parameter, which lets a test split a short clip into several.
    static func makeBounded(
        from source: URL,
        to destination: URL,
        options: NookGIFOptions,
        maxDuration: TimeInterval,
        maxPiecePixels: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // Set just before the destination is opened. A refusal that comes
        // earlier must never remove a file this call did not write.
        var hasOpenedDestination = false
        do {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: source)
            let info = try await readSource(of: asset)
            guard info.duration <= maxDuration else { throw NookGIFError.tooLong }
            let times = frameTimes(duration: info.duration, framesPerSecond: options.framesPerSecond)
            guard !times.isEmpty else { throw NookGIFError.unreadable }
            hasOpenedDestination = true
            try await writeFrames(
                of: asset, info: info, times: times, to: destination,
                options: options, maxPiecePixels: maxPiecePixels, progress: progress
            )
        } catch {
            if hasOpenedDestination { try? FileManager.default.removeItem(at: destination) }
            throw failure(from: error)
        }
    }

    /// About how many bytes the GIF will be. Shown before making it.
    static func estimatedBytes(duration: TimeInterval, sourceSize: CGSize, options: NookGIFOptions) -> Int64 {
        let size = outputSize(source: sourceSize, width: options.width)
        let frames = frameCount(duration: duration, framesPerSecond: options.framesPerSecond)
        return Int64((Double(frames) * Double(size.width * size.height) * estimatedBytesPerPixel).rounded())
    }

    // MARK: Rules

    /// The GIF's size: the source scaled down to the chosen width and never
    /// up, both sides rounded and made even. Zero for a source with no size.
    static func outputSize(source: CGSize, width: NookGIFOptions.Width) -> CGSize {
        guard source.width > 0, source.height > 0 else { return .zero }
        let scale = min(1, CGFloat(width.rawValue) / source.width)
        func even(_ value: CGFloat) -> CGFloat {
            let rounded = Int((value * scale).rounded())
            return CGFloat(max(2, rounded - rounded % 2))
        }
        return CGSize(width: even(source.width), height: even(source.height))
    }

    /// How many frames a clip becomes. A clip too short for one frame still
    /// gets one. The nudge keeps a length like 4.35 s at 20 fps from losing
    /// a frame to floating point.
    static func frameCount(duration: TimeInterval, framesPerSecond: Int) -> Int {
        guard duration > 0, framesPerSecond > 0 else { return 0 }
        return max(1, Int(duration * Double(framesPerSecond) + 1e-6))
    }

    /// Where each frame is taken from, evenly spaced from the start.
    static func frameTimes(duration: TimeInterval, framesPerSecond: Int) -> [CMTime] {
        (0..<frameCount(duration: duration, framesPerSecond: framesPerSecond)).map {
            CMTime(value: Int64($0), timescale: Int32(framesPerSecond))
        }
    }

    /// How long frame `index` stays on screen, in seconds. A GIF keeps time
    /// in hundredths, so 15 fps cannot be 0.0667 for every frame: that
    /// would round to 0.07 and run 5% slow. Each frame gets the difference
    /// between the rounded end of this frame and the rounded end of the
    /// last one, which makes the delays add up to the clip's own length.
    static func frameDelay(index: Int, framesPerSecond: Int) -> Double {
        guard framesPerSecond > 0 else { return 0.1 }
        func hundredths(after frames: Int) -> Int {
            Int((Double(frames) * 100 / Double(framesPerSecond)).rounded())
        }
        return Double(hundredths(after: index + 1) - hundredths(after: index)) / 100
    }

    /// The frame source. Frames are decoded at the GIF's size and not the
    /// source's, which is what keeps a 4K clip from filling memory. Each
    /// frame may come from up to half a frame away, which lets the decoder
    /// take the cheaper one.
    static func makeGenerator(for asset: AVAsset, options: NookGIFOptions, sourceSize: CGSize) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = outputSize(source: sourceSize, width: options.width)
        generator.appliesPreferredTrackTransform = true
        let halfFrame = CMTime(value: 1, timescale: Int32(max(1, options.framesPerSecond) * 2))
        generator.requestedTimeToleranceBefore = halfFrame
        generator.requestedTimeToleranceAfter = halfFrame
        return generator
    }

    // MARK: Reading

    /// The length and shown size of the video in `url`, or nil when it is
    /// not a readable video. The sheet calls this to size its estimate.
    static func inspect(_ url: URL) async -> NookGIFSource? {
        do {
            return try await readSource(of: AVURLAsset(url: url))
        } catch {
            // `readSource` has logged what went wrong. A sheet that closed
            // before the answer came is not worth a line.
            if !(error is CancellationError) {
                NookTrayLog.logger.error("GIF: the options could not read the video")
            }
            return nil
        }
    }

    private static func readSource(of asset: AVAsset) async throws -> NookGIFSource {
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                NookTrayLog.logger.error("GIF: the file has no video track")
                throw NookGIFError.unreadable
            }
            let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
            let duration = try await asset.load(.duration)
            let shown = naturalSize.applying(transform)
            let size = CGSize(width: abs(shown.width), height: abs(shown.height))
            guard duration.isNumeric, duration.seconds > 0, size.width > 0, size.height > 0 else {
                NookTrayLog.logger.error("GIF: the video states no usable length or size")
                throw NookGIFError.unreadable
            }
            return NookGIFSource(duration: duration.seconds, size: size)
        } catch is CancellationError {
            throw CancellationError()
        } catch let known as NookGIFError {
            throw known
        } catch {
            NookTrayLog.logger.error("GIF: reading the video failed (\(NookTrayLog.cause(error), privacy: .public))")
            throw NookGIFError.unreadable
        }
    }

    // MARK: Writing

    private static func writeFrames(
        of asset: AVAsset,
        info: NookGIFSource,
        times: [CMTime],
        to destination: URL,
        options: NookGIFOptions,
        maxPiecePixels: Int,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let size = outputSize(source: info.size, width: options.width)
        let framesPerPiece = max(1, maxPiecePixels / max(1, Int(size.width * size.height)))
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let file = try? FileHandle(forWritingTo: destination)
        else {
            throw NookGIFError.writeFailed
        }
        defer { try? file.close() }

        let generator = makeGenerator(for: asset, options: options, sourceSize: info.size)
        let single = makeGenerator(for: asset, options: options, sourceSize: info.size)
        let canceller = GeneratorCanceller(generators: [generator, single])
        let total = Double(times.count)
        var writer = NookGIFPieceWriter(file: file)
        var piece = try GIFPiece(frames: min(framesPerPiece, times.count))
        var previous: CGImage?
        var written = 0
        var tally = NookGIFDecodeTally()

        try await withTaskCancellationHandler {
            for await result in generator.images(for: times) {
                try Task.checkCancellation()
                let image: CGImage
                switch result {
                case let .success(_, decoded, _):
                    image = decoded
                    tally.recordDecoded()
                case let .failure(requestedTime, _):
                    // The batch decoder can refuse a time that falls in a
                    // gap between two frames, which a screen recording
                    // has wherever the screen stood still. One frame at a
                    // time returns the frame that was showing then.
                    guard let recovered = try await singleFrame(from: single, at: requestedTime, fallback: previous) else {
                        throw NookGIFError.unreadable
                    }
                    switch recovered {
                    case .decoded(let frame):
                        image = frame
                        tally.recordDecoded()
                    case .repeated(let frame, let cause):
                        // Not even one frame at a time would give this one
                        // up, so it shows the picture before it. A few of
                        // those pass for a stutter. Many, or a long run of
                        // them, is a GIF frozen on one picture, which is
                        // worse than no GIF.
                        image = frame
                        tally.recordRepeated(cause: cause)
                        if tally.exceedsLimits(total: times.count, framesPerSecond: options.framesPerSecond) {
                            logRepeated(tally, total: times.count, gaveUp: true)
                            throw NookGIFError.decodeFailed
                        }
                    }
                }
                piece.add(image, delay: frameDelay(index: written, framesPerSecond: options.framesPerSecond))
                previous = image
                written += 1
                // A frame counts as half done once it is added and done once
                // its piece is encoded, which keeps the bar moving through
                // the slow part at the end of each piece.
                if piece.isFull {
                    try writer.append(try piece.finish())
                    progress(Double(written) / total)
                    if written < times.count {
                        piece = try GIFPiece(frames: min(framesPerPiece, times.count - written))
                    }
                } else {
                    progress((Double(written - piece.count) + Double(piece.count) / 2) / total)
                }
            }
        } onCancel: {
            canceller.cancel()
        }

        try Task.checkCancellation()
        // The batch ended early, so the file would be short of the frames
        // it promised.
        guard written == times.count else { throw NookGIFError.unreadable }
        if tally.repeatedCount > 0 { logRepeated(tally, total: times.count, gaveUp: false) }
        try writer.finish()
    }

    /// A frame decoded by itself, or the one before it standing in.
    private enum RecoveredFrame {
        case decoded(CGImage)
        /// `cause` is the domain and code of what stopped the decoder.
        case repeated(CGImage, cause: String)
    }

    /// One frame at `time`, or `fallback` (the frame before) when even that
    /// cannot be decoded. Nil when there is nothing to show.
    private static func singleFrame(
        from generator: AVAssetImageGenerator,
        at time: CMTime,
        fallback: CGImage?
    ) async throws -> RecoveredFrame? {
        do {
            return .decoded(try await generator.image(at: time).image)
        } catch {
            try Task.checkCancellation()
            guard let fallback else { return nil }
            return .repeated(fallback, cause: NookTrayLog.cause(error))
        }
    }

    /// Writes down how many frames stood in for ones that would not decode,
    /// whether the GIF was made or given up on.
    private static func logRepeated(_ tally: NookGIFDecodeTally, total: Int, gaveUp: Bool) {
        NookTrayLog.logger.error(
            """
            GIF: \(tally.repeatedCount, privacy: .public) of \(total, privacy: .public) frames repeated the one before, \
            longest run \(tally.longestRun, privacy: .public), first cause \(tally.firstCause ?? "none", privacy: .public), \
            gave up: \(gaveUp, privacy: .public)
            """
        )
    }

    /// Turns whatever stopped the work into the error the caller sees.
    private static func failure(from error: Error) -> NookGIFError {
        if let known = error as? NookGIFError { return known }
        if error is CancellationError || Task.isCancelled { return .cancelled }
        return .unreadable
    }
}

/// Lets a cancelled task stop the decoders at once, from the cancellation
/// handler, which runs on any thread. `cancelAllCGImageGeneration` is the
/// call Apple documents for this.
private final class GeneratorCanceller: @unchecked Sendable {
    private let generators: [AVAssetImageGenerator]

    init(generators: [AVAssetImageGenerator]) {
        self.generators = generators
    }

    func cancel() {
        for generator in generators { generator.cancelAllCGImageGeneration() }
    }
}

// MARK: - Pieces

/// A run of frames on their way to being a small GIF of their own.
private final class GIFPiece {
    private let bytes = NSMutableData()
    private let destination: CGImageDestination
    private(set) var count = 0
    private let capacity: Int

    init(frames: Int) throws {
        capacity = frames
        guard let destination = CGImageDestinationCreateWithData(
            bytes, UTType.gif.identifier as CFString, frames, nil
        ) else {
            throw NookGIFError.writeFailed
        }
        // Zero loops means forever. Only the first piece's notice is kept.
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        self.destination = destination
    }

    var isFull: Bool { count == capacity }

    func add(_ image: CGImage, delay: Double) {
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay],
        ] as CFDictionary)
        count += 1
    }

    func finish() throws -> Data {
        guard CGImageDestinationFinalize(destination) else { throw NookGIFError.writeFailed }
        return bytes as Data
    }
}

/// Writes the pieces to the file one after the other, so only one is in
/// memory at a time.
private struct NookGIFPieceWriter {
    let file: FileHandle
    private var screen: NookGIFJoiner.Screen?

    init(file: FileHandle) {
        self.file = file
    }

    mutating func append(_ piece: Data) throws {
        do {
            if let screen {
                try file.write(contentsOf: NookGIFJoiner.continuation(of: piece, screen: screen))
            } else {
                let opening = try NookGIFJoiner.opening(of: piece)
                screen = opening.screen
                try file.write(contentsOf: opening.body)
            }
        } catch {
            throw NookGIFError.writeFailed
        }
    }

    /// Closes the animation.
    func finish() throws {
        do {
            try file.write(contentsOf: NookGIFJoiner.trailer)
            try file.close()
        } catch {
            throw NookGIFError.writeFailed
        }
    }
}

// MARK: - Joining

/// Joins GIFs written one after another into one animation.
///
/// ImageIO writes a GIF with one palette for all its frames, in a table at
/// the top, and most frames only hold the part of the picture that
/// changed. So a piece cannot be laid after another as it is: its frames
/// would be read with the first piece's colors. Each frame of a later
/// piece gets its piece's palette written in front of its data as a local
/// color table, which makes it stand alone. A piece's first frame is a
/// whole picture, so it covers whatever came before it.
enum NookGIFJoiner {
    struct Screen: Equatable, Sendable {
        var width: Int
        var height: Int
    }

    enum JoinError: Error, Equatable {
        case malformed
        case sizeChanged
    }

    /// The byte that ends a GIF.
    static let trailer = Data([0x3B])

    private static let imageSeparator: UInt8 = 0x2C
    private static let extensionIntroducer: UInt8 = 0x21
    private static let trailerByte: UInt8 = 0x3B
    private static let graphicControlLabel: UInt8 = 0xF9
    private static let hasColorTable: UInt8 = 0x80
    private static let tableSizeBits: UInt8 = 0x07

    /// The first piece without its last byte, and its screen's size. The
    /// loop notice, the palette and the first frames stay as they are.
    static func opening(of piece: Data) throws -> (body: Data, screen: Screen) {
        let bytes = [UInt8](piece)
        guard let screen = screenSize(of: bytes), bytes.last == trailerByte else {
            throw JoinError.malformed
        }
        return (Data(bytes.dropLast()), screen)
    }

    /// The frames of a later piece, ready to be written after the ones
    /// before. The piece's header, loop notice and last byte are left out.
    static func continuation(of piece: Data, screen: Screen) throws -> Data {
        let bytes = [UInt8](piece)
        guard let pieceScreen = screenSize(of: bytes) else { throw JoinError.malformed }
        guard pieceScreen == screen else { throw JoinError.sizeChanged }

        var reader = Reader(bytes: bytes, position: 13)
        var palette: [UInt8]?
        var paletteBits: UInt8 = 0
        let screenFlags = bytes[10]
        if screenFlags & hasColorTable != 0 {
            paletteBits = screenFlags & tableSizeBits
            palette = try reader.take(tableLength(bits: paletteBits))
        }

        var joined = [UInt8]()
        while true {
            switch try reader.byte() {
            case trailerByte:
                return Data(joined)
            case extensionIntroducer:
                let start = reader.position - 1
                let label = try reader.byte()
                try reader.skipSubBlocks()
                // Frame timing stays. The loop notice and comments go.
                if label == graphicControlLabel { joined += bytes[start..<reader.position] }
            case imageSeparator:
                var descriptor = [imageSeparator] + (try reader.take(9))
                let flags = descriptor[9]
                if flags & hasColorTable != 0 {
                    joined += descriptor
                    joined += try reader.take(tableLength(bits: flags & tableSizeBits))
                } else {
                    guard let palette else { throw JoinError.malformed }
                    // Keep the interlace and sort flags, add the palette.
                    descriptor[9] = (flags & 0x78) | hasColorTable | paletteBits
                    joined += descriptor
                    joined += palette
                }
                joined.append(try reader.byte())   // the code size LZW starts with
                let dataStart = reader.position
                try reader.skipSubBlocks()
                joined += bytes[dataStart..<reader.position]
            default:
                throw JoinError.malformed
            }
        }
    }

    /// The width and height in the screen descriptor, or nil when `bytes`
    /// does not start like a GIF.
    private static func screenSize(of bytes: [UInt8]) -> Screen? {
        guard bytes.count >= 13, bytes[0...2] == [0x47, 0x49, 0x46] else { return nil }
        return Screen(
            width: Int(bytes[6]) | Int(bytes[7]) << 8,
            height: Int(bytes[8]) | Int(bytes[9]) << 8
        )
    }

    /// Bytes in a color table whose size bits are `bits`: 3 for each of
    /// 2 to the power of `bits` plus 1 colors.
    private static func tableLength(bits: UInt8) -> Int {
        3 * (2 << Int(bits))
    }

    /// A cursor over a GIF's bytes that fails, and does not trap, when the
    /// file ends where a block should not.
    private struct Reader {
        let bytes: [UInt8]
        var position: Int

        mutating func byte() throws -> UInt8 {
            guard position < bytes.count else { throw JoinError.malformed }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, position + count <= bytes.count else { throw JoinError.malformed }
            defer { position += count }
            return Array(bytes[position..<position + count])
        }

        /// Moves past a run of data blocks, each led by its length, up to
        /// and including the empty block that ends the run.
        mutating func skipSubBlocks() throws {
            while true {
                let length = Int(try byte())
                if length == 0 { return }
                _ = try take(length)
            }
        }
    }
}
