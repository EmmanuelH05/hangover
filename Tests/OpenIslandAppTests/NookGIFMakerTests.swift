import AppKit
import AVFoundation
import ImageIO
import os
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import OpenIslandApp

// MARK: - Fixtures

/// Movies made inside the test, in a folder of their own that goes away
/// with the suite instance. Nothing here touches a screen, a camera or a
/// microphone.
private final class GIFFixtures {
    let folder: URL

    init() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookGIFMakerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func gifURL() -> URL {
        folder.appendingPathComponent("\(UUID().uuidString).gif")
    }

    /// A plain file that is not a movie.
    func notAMovie() throws -> URL {
        let url = folder.appendingPathComponent("notes.mp4")
        try Data("not a movie".utf8).write(to: url)
        return url
    }

    /// An H.264 movie with a frame at each of `frameTimes` (seconds) that
    /// runs to `seconds`. Every frame differs from the one before, so the
    /// GIF has something to squeeze. `turn` is the track's own rotation.
    func movie(
        frameTimes: [Double],
        seconds: Double,
        width: Int = 320,
        height: Int = 180,
        turn: CGAffineTransform = .identity
    ) async throws -> URL {
        let url = folder.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.transform = turn
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for (index, time) in frameTimes.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            let pool = try #require(adaptor.pixelBufferPool)
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            let buffer = try #require(made)
            Self.paint(buffer, width: width, height: height, step: index)
            adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
        await writer.finishWriting()
        try #require(writer.status == .completed, "the fixture movie was not written: \(String(describing: writer.error))")
        return url
    }

    /// A movie at a steady `framesPerSecond`, for `seconds`.
    func movie(seconds: Double, framesPerSecond: Int = 10, width: Int = 320, height: Int = 180) async throws -> URL {
        let count = Int(seconds * Double(framesPerSecond))
        let times = (0..<count).map { Double($0) / Double(framesPerSecond) }
        return try await movie(frameTimes: times, seconds: seconds, width: width, height: height)
    }

    private static func paint(_ buffer: CVPixelBuffer, width: Int, height: Int, step: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                base[offset] = UInt8(truncatingIfNeeded: step * 40)
                base[offset + 1] = UInt8(truncatingIfNeeded: x)
                base[offset + 2] = UInt8(truncatingIfNeeded: y)
                base[offset + 3] = 255
            }
        }
    }
}

/// What a GIF file says about itself.
private struct GIFFacts {
    let frameCount: Int
    let loopCount: Int?
    let delays: [Double]
    let firstFrameSize: CGSize

    init(_ url: URL) throws {
        try self.init(source: try #require(CGImageSourceCreateWithURL(url as CFURL, nil)))
    }

    init(data: Data) throws {
        try self.init(source: try #require(CGImageSourceCreateWithData(data as CFData, nil)))
    }

    private init(source: CGImageSource) throws {
        frameCount = CGImageSourceGetCount(source)
        let fileProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let fileGIF = fileProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        loopCount = fileGIF?[kCGImagePropertyGIFLoopCount] as? Int
        delays = (0..<frameCount).map { index in
            let frame = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
        }
        let first = CGImageSourceCreateImageAtIndex(source, 0, nil)
        firstFrameSize = CGSize(width: first?.width ?? 0, height: first?.height ?? 0)
    }
}

/// A list the progress callback can add to from any thread.
private final class ProgressLog: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [Double]())

    func add(_ value: Double) { lock.withLock { $0.append(value) } }
    var values: [Double] { lock.withLock { $0 } }
}

/// Lets the progress callback reach the task it runs in.
private final class TaskHandle: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<Task<Void, Error>?>(initialState: nil)

    func set(_ task: Task<Void, Error>) { lock.withLock { $0 = task } }
    func cancel() { lock.withLock { $0?.cancel() } }
}

// MARK: - The maker

@Suite(.serialized) struct NookGIFMakerTests {
    private let fixtures = GIFFixtures()

    // MARK: Rules

    @Test func aWideVideoShrinksToTheChosenWidthKeepingShape() {
        let size = NookGIFMaker.outputSize(source: CGSize(width: 1920, height: 1080), width: .medium)
        #expect(size == CGSize(width: 720, height: 404))
    }

    @Test func aSmallVideoIsNeverMadeBigger() {
        let size = NookGIFMaker.outputSize(source: CGSize(width: 400, height: 300), width: .large)
        #expect(size == CGSize(width: 400, height: 300))
    }

    @Test func aTallVideoKeepsItsShapeToo() {
        let size = NookGIFMaker.outputSize(source: CGSize(width: 1080, height: 1920), width: .small)
        #expect(size == CGSize(width: 480, height: 852))
    }

    @Test func bothSidesComeOutEven() {
        let size = NookGIFMaker.outputSize(source: CGSize(width: 401, height: 301), width: .large)
        #expect(size == CGSize(width: 400, height: 300))
    }

    @Test func aSourceWithNoSizeGivesNoSize() {
        #expect(NookGIFMaker.outputSize(source: .zero, width: .small) == .zero)
    }

    @Test func framesAreEvenlySpaced() {
        let times = NookGIFMaker.frameTimes(duration: 1, framesPerSecond: 10)
        #expect(times.count == 10)
        #expect(times[1].seconds == 0.1)
    }

    @Test func aTwoSecondClipAt24FramesIs48Frames() {
        #expect(NookGIFMaker.frameTimes(duration: 2, framesPerSecond: 24).count == 48)
    }

    @Test func aLengthLikeFourPointThreeFiveDoesNotLoseAFrameToRounding() {
        // 4.35 * 20 is 86.99999999999999 in floating point.
        #expect(NookGIFMaker.frameTimes(duration: 4.35, framesPerSecond: 20).count == 87)
    }

    @Test func aClipTooShortForOneFrameStillGetsOne() {
        #expect(NookGIFMaker.frameTimes(duration: 0.05, framesPerSecond: 10).count == 1)
    }

    @Test func aClipWithNoLengthGetsNoFrames() {
        #expect(NookGIFMaker.frameTimes(duration: 0, framesPerSecond: 10).isEmpty)
    }

    @Test func tenFramesASecondIsTenHundredthsEach() {
        for index in 0..<20 {
            #expect(NookGIFMaker.frameDelay(index: index, framesPerSecond: 10) == 0.1)
        }
    }

    @Test(arguments: NookGIFOptions.frameRates)
    func theDelaysAddUpToTheClipsOwnLength(rate: Int) {
        // Rounding every delay on its own would run 15 fps about 5% slow.
        let seconds = 4
        let total = (0..<(seconds * rate)).reduce(0.0) { $0 + NookGIFMaker.frameDelay(index: $1, framesPerSecond: rate) }
        let expected = Double(seconds)
        #expect(abs(total - expected) < 0.0001)
    }

    @Test func fifteenFramesASecondAlternatesSixAndSevenHundredths() {
        let delays = (0..<6).map { NookGIFMaker.frameDelay(index: $0, framesPerSecond: 15) }
        #expect(delays == [0.07, 0.06, 0.07, 0.07, 0.06, 0.07])
    }

    @Test func theEstimateGrowsWithLengthAndSize() {
        let source = CGSize(width: 1920, height: 1080)
        let short = NookGIFMaker.estimatedBytes(duration: 5, sourceSize: source, options: .init(width: .small))
        let long = NookGIFMaker.estimatedBytes(duration: 10, sourceSize: source, options: .init(width: .small))
        let big = NookGIFMaker.estimatedBytes(duration: 5, sourceSize: source, options: .init(width: .large))
        #expect(long > short)
        #expect(big > short)
        #expect(short > 0)
    }

    @Test func theEstimateGrowsWithTheFrameRate() {
        let source = CGSize(width: 1920, height: 1080)
        let slow = NookGIFMaker.estimatedBytes(duration: 5, sourceSize: source, options: .init(width: .medium, framesPerSecond: 10))
        let fast = NookGIFMaker.estimatedBytes(duration: 5, sourceSize: source, options: .init(width: .medium, framesPerSecond: 24))
        #expect(fast > slow)
    }

    @Test func theEstimateIsFramesTimesPixelsTimesTheGuess() {
        let options = NookGIFOptions(width: .small, framesPerSecond: 10)
        let bytes = NookGIFMaker.estimatedBytes(duration: 5, sourceSize: CGSize(width: 1920, height: 1080), options: options)
        // 50 frames of 480 by 270 pixels at 0.3 bytes a pixel.
        let expected: Int64 = 1_944_000
        #expect(bytes == expected)
    }

    @Test func aClipWithNoLengthEstimatesToNothing() {
        let bytes = NookGIFMaker.estimatedBytes(duration: 0, sourceSize: CGSize(width: 1920, height: 1080), options: .init())
        let expected: Int64 = 0
        #expect(bytes == expected)
    }
    // MARK: Decoding

    /// Review focus 5: a 4K clip must not be decoded at 4K.
    @Test func framesAreDecodedAtTheGIFSizeNotTheSourceSize() async throws {
        let asset = AVURLAsset(url: try await fixtures.movie(seconds: 1))
        let generator = NookGIFMaker.makeGenerator(for: asset, options: .init(width: .small), sourceSize: CGSize(width: 3840, height: 2160))
        #expect(generator.maximumSize == CGSize(width: 480, height: 270))
        #expect(generator.appliesPreferredTrackTransform)
    }

    @Test func eachFrameMayComeFromHalfAFrameAway() async throws {
        let asset = AVURLAsset(url: try await fixtures.movie(seconds: 1))
        let generator = NookGIFMaker.makeGenerator(for: asset, options: .init(width: .small, framesPerSecond: 10), sourceSize: CGSize(width: 320, height: 180))
        let half = CMTime(value: 1, timescale: 20)
        #expect(generator.requestedTimeToleranceBefore == half)
        #expect(generator.requestedTimeToleranceAfter == half)
    }

    @Test func inspectReadsTheLengthAndTheSize() async throws {
        let movie = try await fixtures.movie(seconds: 2, width: 320, height: 180)
        let source = try #require(await NookGIFMaker.inspect(movie))
        #expect(abs(source.duration - 2) < 0.05)
        #expect(source.size == CGSize(width: 320, height: 180))
    }

    @Test func aMovieHeldUprightIsTallerThanWide() async throws {
        let turned = try await fixtures.movie(
            frameTimes: [0, 0.1, 0.2], seconds: 0.3, width: 320, height: 180,
            turn: CGAffineTransform(rotationAngle: .pi / 2)
        )
        let source = try #require(await NookGIFMaker.inspect(turned))
        #expect(source.size == CGSize(width: 180, height: 320))
    }

    @Test func aFileThatIsNotAMovieIsNotInspected() async throws {
        #expect(await NookGIFMaker.inspect(try fixtures.notAMovie()) == nil)
    }

    @Test func aTwoSecondMovieBecomesALoopingGIF() async throws {
        let movie = try await fixtures.movie(seconds: 2)
        let out = fixtures.gifURL()
        try await NookGIFMaker.make(from: movie, to: out, options: .init(width: .small, framesPerSecond: 10)) { _ in }
        let gif = try GIFFacts(out)
        #expect(gif.frameCount == 20)
        #expect(gif.loopCount == 0)
    }

    @Test func theGIFRunsAsLongAsTheClip() async throws {
        let movie = try await fixtures.movie(seconds: 2)
        let out = fixtures.gifURL()
        try await NookGIFMaker.make(from: movie, to: out, options: .init(width: .small, framesPerSecond: 15)) { _ in }
        let gif = try GIFFacts(out)
        #expect(gif.frameCount == 30)
        let total = gif.delays.reduce(0, +)
        let expected = 2.0
        #expect(abs(total - expected) < 0.011)
    }

    @Test func framesAreWrittenAtTheChosenWidth() async throws {
        let movie = try await fixtures.movie(seconds: 1, width: 1280, height: 720)
        let out = fixtures.gifURL()
        try await NookGIFMaker.make(from: movie, to: out, options: .init(width: .small, framesPerSecond: 10)) { _ in }
        let size = try GIFFacts(out).firstFrameSize
        #expect(size.width <= 480)
        #expect(size.height <= 270)
        #expect(size.width >= 478)
    }

    @Test func aRecordingWithGapsStillGivesEveryFrame() async throws {
        // A screen recording only holds a frame when the screen changed, so
        // the picture can stand still for seconds. Review focus: those
        // seconds must not become holes in the GIF.
        let movie = try await fixtures.movie(frameTimes: [0, 1.0, 2.5], seconds: 3)
        let out = fixtures.gifURL()
        try await NookGIFMaker.make(from: movie, to: out, options: .init(width: .small, framesPerSecond: 10)) { _ in }
        #expect(try GIFFacts(out).frameCount == 30)
    }

    @Test func progressClimbsToOne() async throws {
        let movie = try await fixtures.movie(seconds: 2)
        let out = fixtures.gifURL()
        let log = ProgressLog()
        try await NookGIFMaker.make(from: movie, to: out, options: .init(width: .small, framesPerSecond: 10)) { log.add($0) }
        let values = log.values
        #expect(!values.isEmpty)
        #expect(values == values.sorted())
        #expect(values.allSatisfy { $0 > 0 && $0 <= 1 })
        let finished = 1.0
        #expect(values.last == finished)
    }

    @Test func aClipOverTwoMinutesIsRefusedBeforeAnyWork() async throws {
        let movie = try await fixtures.movie(seconds: 1)
        let out = fixtures.gifURL()
        // A tiny max proves the check without a two-minute fixture.
        await #expect(throws: NookGIFError.tooLong) {
            try await NookGIFMaker.make(from: movie, to: out, options: .init(), maxDuration: 0.5) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func aRefusalLeavesAFileAlreadyAtTheDestinationAlone() async throws {
        let movie = try await fixtures.movie(seconds: 1)
        let out = fixtures.gifURL()
        try Data("keep me".utf8).write(to: out)
        await #expect(throws: NookGIFError.tooLong) {
            try await NookGIFMaker.make(from: movie, to: out, options: .init(), maxDuration: 0.5) { _ in }
        }
        #expect(try Data(contentsOf: out) == Data("keep me".utf8))
    }

    @Test func theLimitIsTwoMinutesByDefault() {
        let expected: TimeInterval = 120
        #expect(NookGIFMaker.maxDuration == expected)
    }

    @Test func aFileThatIsNotAMovieIsUnreadable() async throws {
        let out = fixtures.gifURL()
        let junk = try fixtures.notAMovie()
        await #expect(throws: NookGIFError.unreadable) {
            try await NookGIFMaker.make(from: junk, to: out, options: .init()) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func aMissingFileIsUnreadable() async throws {
        let out = fixtures.gifURL()
        let missing = fixtures.folder.appendingPathComponent("gone.mp4")
        await #expect(throws: NookGIFError.unreadable) {
            try await NookGIFMaker.make(from: missing, to: out, options: .init()) { _ in }
        }
    }

    @Test func aDestinationThatCannotBeWrittenIsAWriteFailure() async throws {
        let movie = try await fixtures.movie(seconds: 1)
        let out = fixtures.folder.appendingPathComponent("no such folder", isDirectory: true).appendingPathComponent("a.gif")
        await #expect(throws: NookGIFError.writeFailed) {
            try await NookGIFMaker.make(from: movie, to: out, options: .init(width: .small, framesPerSecond: 10)) { _ in }
        }
    }

    @Test func cancellingBeforeTheStartRemovesNothingAndWritesNothing() async throws {
        let movie = try await fixtures.movie(seconds: 3)
        let out = fixtures.gifURL()
        let task = Task { try await NookGIFMaker.make(from: movie, to: out, options: .init(width: .small, framesPerSecond: 24)) { _ in } }
        task.cancel()
        _ = await task.result
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func cancellingMidwayReportsCancelledAndRemovesThePartialFile() async throws {
        let movie = try await fixtures.movie(seconds: 3, framesPerSecond: 24)
        let out = fixtures.gifURL()
        let handle = TaskHandle()
        let log = ProgressLog()
        let task = Task {
            try await NookGIFMaker.make(from: movie, to: out, options: .init(width: .small, framesPerSecond: 24)) { fraction in
                log.add(fraction)
                handle.cancel()
            }
        }
        handle.set(task)
        let result = await task.result
        #expect(!log.values.isEmpty, "the job should have started before it was cancelled")
        #expect(throws: NookGIFError.cancelled) { try result.get() }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}

// MARK: - Pieces

/// GIFs made of flat color frames, so a color that comes out wrong after
/// the pieces are joined is plain to see.
private enum FlatGIF {
    typealias Color = (red: UInt8, green: UInt8, blue: UInt8)

    static func image(_ color: Color, size: Int = 16) -> CGImage {
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    /// A GIF of one frame for each color, written the way the maker writes a piece.
    static func piece(_ colors: [Color], size: Int = 16, delay: Double = 0.1) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, colors.count, nil)!
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for color in colors {
            CGImageDestinationAddImage(destination, image(color, size: size), [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay],
            ] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// The pieces joined the way the maker joins them.
    static func joined(_ pieces: [Data]) throws -> Data {
        var file = Data()
        var screen: NookGIFJoiner.Screen?
        for piece in pieces {
            if let screen {
                file += try NookGIFJoiner.continuation(of: piece, screen: screen)
            } else {
                let opening = try NookGIFJoiner.opening(of: piece)
                screen = opening.screen
                file += opening.body
            }
        }
        return file + NookGIFJoiner.trailer
    }

    /// The color in the middle of frame `index`, as the GIF shows it.
    static func centerColor(of data: Data, frame index: Int) -> [Int]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, index, nil)
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
            return true
        }
        return drawn ? pixel.prefix(3).map(Int.init) : nil
    }
}

@Suite(.serialized) struct NookGIFPieceTests {
    private let fixtures = GIFFixtures()

    private let reds: [FlatGIF.Color] = [(250, 10, 10), (200, 30, 30), (150, 40, 40)]
    private let greens: [FlatGIF.Color] = [(10, 250, 10), (30, 200, 30), (40, 150, 40)]
    private let blues: [FlatGIF.Color] = [(10, 10, 250), (30, 30, 200)]

    @Test func piecesJoinedKeepEveryFrameInOrderWithTheirOwnColors() throws {
        let colors = reds + greens + blues
        let joined = try FlatGIF.joined([FlatGIF.piece(reds), FlatGIF.piece(greens), FlatGIF.piece(blues)])
        let source = try #require(CGImageSourceCreateWithData(joined as CFData, nil))
        #expect(CGImageSourceGetCount(source) == colors.count)
        for (index, color) in colors.enumerated() {
            let seen = try #require(FlatGIF.centerColor(of: joined, frame: index))
            let wanted = [Int(color.red), Int(color.green), Int(color.blue)]
            for (got, want) in zip(seen, wanted) {
                #expect(abs(got - want) <= 12, "frame \(index): saw \(seen), wanted \(wanted)")
            }
        }
    }

    @Test func joinedPiecesStillLoopForever() throws {
        let joined = try FlatGIF.joined([FlatGIF.piece(reds), FlatGIF.piece(greens)])
        let facts = try GIFFacts(data: joined)
        #expect(facts.loopCount == 0)
    }

    @Test func joinedPiecesKeepEachFramesDelay() throws {
        let joined = try FlatGIF.joined([FlatGIF.piece(reds, delay: 0.07), FlatGIF.piece(greens, delay: 0.04)])
        let facts = try GIFFacts(data: joined)
        #expect(facts.delays == [0.07, 0.07, 0.07, 0.04, 0.04, 0.04])
    }

    @Test func aSinglePieceComesOutExactlyAsItWentIn() throws {
        let piece = FlatGIF.piece(reds)
        #expect(try FlatGIF.joined([piece]) == piece)
    }

    @Test func aPieceOfADifferentSizeCannotBeJoined() throws {
        let first = FlatGIF.piece(reds, size: 16)
        let other = FlatGIF.piece(greens, size: 20)
        let screen = try NookGIFJoiner.opening(of: first).screen
        #expect(throws: NookGIFJoiner.JoinError.sizeChanged) {
            try NookGIFJoiner.continuation(of: other, screen: screen)
        }
    }

    @Test func somethingThatIsNotAGIFCannotBeJoined() {
        #expect(throws: NookGIFJoiner.JoinError.malformed) {
            try NookGIFJoiner.opening(of: Data("not a gif at all".utf8))
        }
    }

    @Test func aPieceCutShortCannotBeJoined() throws {
        let whole = FlatGIF.piece(reds)
        let screen = try NookGIFJoiner.opening(of: whole).screen
        let cut = whole.prefix(whole.count / 2)
        #expect(throws: NookGIFJoiner.JoinError.malformed) {
            try NookGIFJoiner.continuation(of: Data(cut), screen: screen)
        }
        #expect(throws: NookGIFJoiner.JoinError.malformed) {
            try NookGIFJoiner.opening(of: Data(cut))
        }
    }

    @Test func aLongClipIsMadeInSeveralPiecesAndStillComesOutWhole() async throws {
        // 12 frames at 10 fps. 200 000 pixels a piece is 3 frames of 480 by 270,
        // so the clip goes through four pieces.
        let movie = try await fixtures.movie(seconds: 1.2, framesPerSecond: 10)
        let out = fixtures.gifURL()
        try await NookGIFMaker.makeBounded(
            from: movie, to: out, options: .init(width: .small, framesPerSecond: 10),
            maxDuration: NookGIFMaker.maxDuration, maxPiecePixels: 200_000
        ) { _ in }
        let gif = try GIFFacts(out)
        #expect(gif.frameCount == 12)
        #expect(gif.loopCount == 0)
        let total = gif.delays.reduce(0, +)
        let expected = 1.2
        #expect(abs(total - expected) < 0.011)
    }

    @Test func everyFrameOfAPiecedGIFHoldsTheSamePictureAsAWholeOne() async throws {
        let movie = try await fixtures.movie(seconds: 1.2, framesPerSecond: 10)
        let options = NookGIFOptions(width: .small, framesPerSecond: 10)
        let whole = fixtures.gifURL()
        let pieced = fixtures.gifURL()
        try await NookGIFMaker.make(from: movie, to: whole, options: options) { _ in }
        try await NookGIFMaker.makeBounded(
            from: movie, to: pieced, options: options, maxDuration: NookGIFMaker.maxDuration, maxPiecePixels: 200_000
        ) { _ in }
        for frame in 0..<12 {
            let a = try #require(FlatGIF.centerColor(of: try Data(contentsOf: whole), frame: frame))
            let b = try #require(FlatGIF.centerColor(of: try Data(contentsOf: pieced), frame: frame))
            for (x, y) in zip(a, b) {
                #expect(abs(x - y) <= 24, "frame \(frame): whole \(a), pieced \(b)")
            }
        }
    }

    @Test func aPieceNeverHoldsLessThanOneFrame() async throws {
        // A piece size far below one frame still makes a GIF, a frame at a time.
        let movie = try await fixtures.movie(seconds: 0.5, framesPerSecond: 10)
        let out = fixtures.gifURL()
        try await NookGIFMaker.makeBounded(
            from: movie, to: out, options: .init(width: .small, framesPerSecond: 10),
            maxDuration: NookGIFMaker.maxDuration, maxPiecePixels: 1
        ) { _ in }
        #expect(try GIFFacts(out).frameCount == 5)
    }

    @Test func aPiecedGIFReportsProgressUpToOne() async throws {
        let movie = try await fixtures.movie(seconds: 1.2, framesPerSecond: 10)
        let out = fixtures.gifURL()
        let log = ProgressLog()
        try await NookGIFMaker.makeBounded(
            from: movie, to: out, options: .init(width: .small, framesPerSecond: 10),
            maxDuration: NookGIFMaker.maxDuration, maxPiecePixels: 200_000
        ) { log.add($0) }
        let values = log.values
        #expect(values == values.sorted())
        let finished = 1.0
        #expect(values.last == finished)
    }

    @Test func cancellingBetweenPiecesRemovesTheFileSoFar() async throws {
        let movie = try await fixtures.movie(seconds: 3, framesPerSecond: 10)
        let out = fixtures.gifURL()
        let handle = TaskHandle()
        let log = ProgressLog()
        let task = Task {
            try await NookGIFMaker.makeBounded(
                from: movie, to: out, options: .init(width: .small, framesPerSecond: 10),
                maxDuration: NookGIFMaker.maxDuration, maxPiecePixels: 200_000
            ) { fraction in
                log.add(fraction)
                // After the first piece is already in the file.
                if fraction >= 3.0 / 30 { handle.cancel() }
            }
        }
        handle.set(task)
        let result = await task.result
        #expect(throws: NookGIFError.cancelled) { try result.get() }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}

// MARK: - The sheet

@MainActor @Suite(.noNewWindows) struct NookGIFSheetTests {
    private let source = URL(fileURLWithPath: "/tmp/never-opened.mp4")

    private func loaded(_ seconds: TimeInterval) -> NookGIFSheetLoad {
        .loaded(NookGIFSource(duration: seconds, size: CGSize(width: 1920, height: 1080)))
    }

    @Test func aClipUnderTheLimitShowsItsEstimate() {
        let options = NookGIFOptions(width: .medium, framesPerSecond: 15)
        let status = NookGIFSheetRules.status(load: loaded(10), options: options)
        let expected = NookGIFMaker.estimatedBytes(duration: 10, sourceSize: CGSize(width: 1920, height: 1080), options: options)
        #expect(status == .ready(estimatedBytes: expected))
        #expect(NookGIFSheetRules.canMake(status))
    }

    @Test func aClipOfExactlyTwoMinutesIsAllowed() {
        let status = NookGIFSheetRules.status(load: loaded(120), options: .init())
        #expect(NookGIFSheetRules.canMake(status))
    }

    @Test func aClipOverTwoMinutesIsTooLongAndCannotBeMade() {
        let status = NookGIFSheetRules.status(load: loaded(120.5), options: .init())
        #expect(status == .tooLong)
        #expect(!NookGIFSheetRules.canMake(status))
    }

    @Test func theLimitComesFromTheCaller() {
        let status = NookGIFSheetRules.status(load: loaded(10), options: .init(), maxDuration: 5)
        #expect(status == .tooLong)
    }

    @Test func nothingCanBeMadeWhileTheVideoIsStillBeingRead() {
        let status = NookGIFSheetRules.status(load: .loading, options: .init())
        #expect(status == .loading)
        #expect(!NookGIFSheetRules.canMake(status))
    }

    @Test func nothingCanBeMadeFromAVideoThatCannotBeRead() {
        let status = NookGIFSheetRules.status(load: .unreadable, options: .init())
        #expect(status == .unreadable)
        #expect(!NookGIFSheetRules.canMake(status))
    }

    @Test func theEstimateFollowsTheOptionsPicked() {
        let small = NookGIFSheetRules.status(load: loaded(10), options: .init(width: .small, framesPerSecond: 10))
        let large = NookGIFSheetRules.status(load: loaded(10), options: .init(width: .large, framesPerSecond: 24))
        guard case let .ready(smallBytes) = small, case let .ready(largeBytes) = large else {
            Issue.record("both should be ready")
            return
        }
        #expect(largeBytes > smallBytes)
    }

    @Test func aSizeReadsLikeFinderWritesIt() {
        let text = NookGIFSheetRules.sizeText(bytes: 4_200_000)
        #expect(text.contains("MB"))
        #expect(text.contains("4"))
    }

    @Test func everyWidthHasAName() {
        let keys = NookGIFOptions.Width.allCases.map(NookGIFSheetRules.titleKey(for:))
        #expect(Set(keys).count == NookGIFOptions.Width.allCases.count)
        #expect(keys.allSatisfy { $0.hasPrefix("nook.gif.width.") })
    }

    /// 74 before the line that says what a GIF is, which adds its 14 points
    /// and one 6 point gap.
    @Test func theSheetNeedsNinetyFourPointsWhenItsControlsSitSideBySide() {
        let expected: CGFloat = 94
        #expect(NookGIFSheetLayout.wideHeight == expected)
    }

    @Test func theSheetDrawsInEachOfItsStates() throws {
        let video = CGSize(width: 1920, height: 1080)
        let ready = try render("gif-sheet-ready", .loaded(NookGIFSource(duration: 10, size: video)))
        let tooLong = try render("gif-sheet-too-long", .loaded(NookGIFSource(duration: 300, size: video)))
        let loading = try render("gif-sheet-loading", .loading)
        let unreadable = try render("gif-sheet-unreadable", .unreadable)
        #expect(ready != tooLong, "the too long sheet should say so")
        #expect(ready != loading, "the sheet should show its estimate once the video is read")
        #expect(loading != unreadable, "a video that cannot be read should say so")
    }

    @Test func theSheetDrawsInACardTooNarrowForTwoControlsInARow() throws {
        let video = CGSize(width: 1920, height: 1080)
        let narrow = try render("gif-sheet-narrow", .loaded(NookGIFSource(duration: 300, size: video)), width: 176, height: 180)
        let wide = try render("gif-sheet-wide-too-long", .loaded(NookGIFSource(duration: 300, size: video)))
        #expect(narrow != wide)
    }

    /// Draws the sheet at the tray card's content width. Set
    /// `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to also write the PNGs to
    /// `output/render/` under the repo root for a visual check.
    private func render(_ name: String, _ load: NookGIFSheetLoad, width: CGFloat = 388, height: CGFloat = 130) throws -> Data {
        let sheet = NookGIFSheet(sourceURL: source, sourceName: "Lecture 5 recording.mov", load: load)
            .frame(width: width, height: height, alignment: .topLeading)
            .padding(14)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image for \(name)")
        let png = try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            "PNG encoding failed for \(name)"
        )
        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let directory = root.appendingPathComponent("output/render", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}

// MARK: - The options say what they make, from what, and where it goes

@MainActor @Suite struct NookGIFSheetWordingTests {
    @Test func theTitleNamesTheVideo() {
        let lang = LanguageManager.shared
        #expect(NookGIFSheetRules.title(sourceName: "lecture.mov") == lang.t("nook.gif.titleFrom", "lecture.mov"))
        #expect(NookGIFSheetRules.title(sourceName: "lecture.mov").contains("lecture.mov"))
        #expect(NookGIFSheetRules.title(sourceName: nil) == lang.t("nook.gif.title"))
    }

    @Test func theSheetSaysWhatAGIFIsAndTheButtonSaysGIF() throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in ["nook.gif.titleFrom", "nook.gif.explain", "nook.gif.make"] {
                let value = try #require(table[key], "\(language) has no \(key)")
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"))
            }
            #expect(table["nook.gif.make"]?.contains("GIF") == true, "\(language): the button names what it makes")
            #expect(table["nook.gif.titleFrom"]?.contains("%@") == true)
        }
    }

    @Test func theSheetMakesRoomForTheLineThatExplainsIt() {
        let layout = NookGIFSheetLayout.self
        #expect(layout.wideHeight == layout.titleHeight + layout.explainHeight + layout.controlHeight
            + layout.buttonHeight + layout.rowSpacing * 3)
    }
}
