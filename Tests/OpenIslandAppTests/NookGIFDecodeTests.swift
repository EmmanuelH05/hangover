import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import Testing
@testable import OpenIslandApp

/// Movies made inside the test, in a folder of their own that goes away with
/// the suite instance. Nothing here touches a screen, a camera or a
/// microphone.
private final class DecodeFixtures {
    let folder: URL

    init() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookGIFDecodeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func gifURL() -> URL {
        folder.appendingPathComponent("\(UUID().uuidString).gif")
    }

    /// An H.264 movie of `seconds` at `framesPerSecond`, every frame different
    /// and every one a key frame, so each can be decoded alone. The index
    /// sits at the front of the file, which lets the file be cut short and
    /// still be opened: the pictures past the cut cannot be read.
    func movie(seconds: Int, framesPerSecond: Int = 10, width: Int = 160, height: Int = 90) async throws -> URL {
        let url = folder.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 1],
        ])
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
        for index in 0..<(seconds * framesPerSecond) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            let pool = try #require(adaptor.pixelBufferPool)
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            let buffer = try #require(made)
            Self.paint(buffer, width: width, height: height, step: index)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(framesPerSecond)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed, "the fixture movie was not written: \(String(describing: writer.error))")
        return url
    }

    /// A copy of `movie` with everything past `keeping` of its bytes cut off.
    func cut(_ movie: URL, keeping fraction: Double) throws -> URL {
        let data = try Data(contentsOf: movie)
        let cutURL = folder.appendingPathComponent("\(UUID().uuidString).mp4")
        try data.prefix(Int(Double(data.count) * fraction)).write(to: cutURL)
        return cutURL
    }

    private static func paint(_ buffer: CVPixelBuffer, width: Int, height: Int, step: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var generator = SystemRandomNumberGenerator()
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                base[offset] = UInt8.random(in: 0...255, using: &generator)
                base[offset + 1] = UInt8(truncatingIfNeeded: x + step * 9)
                base[offset + 2] = UInt8(truncatingIfNeeded: y)
                base[offset + 3] = 255
            }
        }
    }
}

// MARK: - The count

@Suite struct NookGIFDecodeTallyTests {
    @Test func aFewRepeatedFramesPass() {
        var tally = NookGIFDecodeTally()
        // Three of thirty is a tenth, which is not over it.
        for _ in 0..<3 {
            tally.recordRepeated(cause: "x 1")
            tally.recordDecoded()
        }
        #expect(tally.repeatedCount == 3)
        #expect(!tally.exceedsLimits(total: 30, framesPerSecond: 15))
    }

    @Test func overATenthOfTheFramesFails() {
        var tally = NookGIFDecodeTally()
        for _ in 0..<4 {
            tally.recordRepeated(cause: "x 1")
            tally.recordDecoded()
        }
        #expect(tally.exceedsLimits(total: 30, framesPerSecond: 15))
    }

    @Test func aRunOfExactlyASecondPassesAndOneFrameMoreFails() {
        var tally = NookGIFDecodeTally()
        for _ in 0..<10 { tally.recordRepeated(cause: "x 1") }
        // Ten frames at ten a second is one second, in a clip long enough
        // that ten frames are far under a tenth of it.
        #expect(tally.longestRun == 10)
        #expect(!tally.exceedsLimits(total: 1_000, framesPerSecond: 10))
        tally.recordRepeated(cause: "x 1")
        #expect(tally.exceedsLimits(total: 1_000, framesPerSecond: 10))
    }

    @Test func aDecodedFrameEndsARun() {
        var tally = NookGIFDecodeTally()
        for _ in 0..<8 { tally.recordRepeated(cause: "x 1") }
        tally.recordDecoded()
        for _ in 0..<8 { tally.recordRepeated(cause: "x 1") }
        #expect(tally.longestRun == 8)
        #expect(tally.repeatedCount == 16)
        #expect(!tally.exceedsLimits(total: 1_000, framesPerSecond: 10))
    }

    @Test func theFirstCauseIsKept() {
        var tally = NookGIFDecodeTally()
        tally.recordRepeated(cause: "AVFoundationErrorDomain -11829")
        tally.recordRepeated(cause: "other 2")
        #expect(tally.firstCause == "AVFoundationErrorDomain -11829")
    }

    @Test func aClipWithNoFramesIsNeverOverTheLimit() {
        let tally = NookGIFDecodeTally()
        #expect(!tally.exceedsLimits(total: 0, framesPerSecond: 15))
        #expect(!tally.exceedsLimits(total: 30, framesPerSecond: 0))
    }

    @Test func theGIFHasASentenceForIt() {
        #expect(NookConvertRules.noticeKey(for: NookGIFError.decodeFailed, action: .makeGIF) == "nook.tray.convert.notice.gifDecodeFailed")
    }
}

// MARK: - A video that breaks

@Suite(.serialized) struct NookGIFDecodeFailureTests {
    private let fixtures = DecodeFixtures()

    @Test func aVideoThatDecodesWholeMakesAGIFWithNoRepeats() async throws {
        let movie = try await fixtures.movie(seconds: 2)
        let out = fixtures.gifURL()
        try await NookGIFMaker.make(from: movie, to: out, options: .init(width: .small, framesPerSecond: 10)) { _ in }
        #expect(FileManager.default.fileExists(atPath: out.path))
    }

    @Test func aFewFramesPastTheCutRepeatAndTheGIFIsStillMade() async throws {
        let movie = try await fixtures.movie(seconds: 4)
        let cut = try fixtures.cut(movie, keeping: 0.97)
        let out = fixtures.gifURL()
        try await NookGIFMaker.make(from: cut, to: out, options: .init(width: .small, framesPerSecond: 10)) { _ in }
        let source = try #require(CGImageSourceCreateWithURL(out as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 40, "every frame is there, the last few repeating the one before")
    }

    @Test func aVideoMostlyPastTheCutFailsAndLeavesNoFile() async throws {
        let movie = try await fixtures.movie(seconds: 4)
        let cut = try fixtures.cut(movie, keeping: 0.3)
        let out = fixtures.gifURL()
        await #expect(throws: NookGIFError.decodeFailed) {
            try await NookGIFMaker.make(from: cut, to: out, options: .init(width: .small, framesPerSecond: 10)) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}
