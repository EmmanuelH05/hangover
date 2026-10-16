import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import OpenIslandApp

@Suite(.serialized) struct NookRecordWriterTests {
    struct FeedTimeout: Error {}

    /// A solid gray frame at `seconds` on the host clock's timescale.
    static func frame(at seconds: Double, width: Int = 64, height: Int = 64) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        let buffer = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0x80, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: try #require(format),
            sampleTiming: &timing, sampleBufferOut: &sample
        )
        return try #require(sample)
    }

    /// A tenth of a second of silence (48 kHz stereo float) starting at `seconds`.
    static func silence(at seconds: Double, frames: Int = 4_800) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        let byteCount = frames * 8
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: try #require(block), offsetIntoDestination: 0, dataLength: byteCount)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: try #require(block), formatDescription: try #require(format),
            sampleCount: frames, presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 48_000),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        return try #require(sample)
    }

    /// Offers a frame once the writer has room for it. The real capture is
    /// paced by the screen, so a full encoder queue just drops a frame there. A
    /// test that feeds frames in a tight loop has to wait for the room instead,
    /// and looks before it offers so that the drop count stays honest.
    func feed(_ writer: NookRecordWriter, frame seconds: Double) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !writer.isReady(for: .video) {
            guard Date() < deadline else { throw FeedTimeout() }
            try await Task.sleep(for: .milliseconds(1))
        }
        while !writer.append(try Self.frame(at: seconds), to: .video) {
            guard Date() < deadline else { throw FeedTimeout() }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    }

    func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    @Test func aPauseLeavesNoGapInTheFile() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        for i in 0..<30 { try await feed(writer, frame: 100 + Double(i) / 30) }
        writer.pause(at: CMTime(seconds: 101, preferredTimescale: 600))
        for i in 0..<60 { writer.append(try Self.frame(at: 101 + Double(i) / 30), to: .video) }
        writer.resume(at: CMTime(seconds: 103, preferredTimescale: 600))
        for i in 0..<30 { try await feed(writer, frame: 103 + Double(i) / 30) }
        try await writer.finish()
        let seconds = try await duration(of: url)
        #expect(seconds > 1.8 && seconds < 2.2)
    }

    @Test func framesDuringAPauseAreNotWritten() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        writer.pause(at: CMTime(seconds: 5, preferredTimescale: 600))
        let accepted = writer.append(try Self.frame(at: 6), to: .video)
        #expect(!accepted)
    }

    @Test func finishingTwiceIsHarmless() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        for i in 0..<10 { try await feed(writer, frame: Double(i) / 30) }
        try await writer.finish()
        try await writer.finish()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aStreamThatStopsMidwayStillLeavesAPlayableFile() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video, .macSound])
        for i in 0..<30 { try await feed(writer, frame: Double(i) / 30) }
        // No audio ever arrived and no stop was asked for: the stream just died.
        try await writer.finish()
        #expect(try await duration(of: url) > 0.9)
        #expect(NookRecordRules.phaseAfterFinish(fileURL: url, cause: .system, finishSucceeded: true, videoFramesWritten: 30) == .finished(url, endedBy: .system))
    }

    @Test func aWriterThatNeverGotAFrameFailsAndLeavesNoFile() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        await #expect(throws: NookRecordWriter.WriterError.noFrames) { try await writer.finish() }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(NookRecordRules.phaseAfterFinish(fileURL: url, cause: .system, finishSucceeded: false, videoFramesWritten: 0) == .failed(.noPicture))
    }

    @Test func soundBeforeTheFirstFrameIsDroppedAndSoundAfterItIsKept() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video, .macSound])
        #expect(!writer.append(try Self.silence(at: 0.9), to: .macSound))
        try await feed(writer, frame: 1)
        for i in 0..<20 {
            let start = 1.1 + Double(i) / 10
            try await feed(writer, frame: 1 + Double(i + 1) / 30)
            let deadline = Date().addingTimeInterval(10)
            while !writer.append(try Self.silence(at: start), to: .macSound) {
                guard Date() < deadline else { throw FeedTimeout() }
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        try await writer.finish()
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        #expect(audio.count == 1)
        #expect(video.count == 1)
    }

    // MARK: A writer that fails midway (R2)

    /// Collects what a writer's failure handler saw, from any thread.
    final class FailureLog: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [NookRecordWriter.Failure] = []
        func add(_ failure: NookRecordWriter.Failure) { lock.withLock { items.append(failure) } }
        var all: [NookRecordWriter.Failure] { lock.withLock { items } }
    }

    /// Seconds of 30 fps pictures, fed as fast as the writer takes them.
    func feedSeconds(_ writer: NookRecordWriter, _ seconds: Int) async throws {
        for index in 0..<(seconds * 30) { try await feed(writer, frame: Double(index) / 30) }
    }

    func isPlayable(_ url: URL) async -> Bool {
        (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false
    }

    @Test func aWriterThatFailsMidwayReportsOnceAndTheFileBeforeTheFailurePlays() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let log = FailureLog()
        let writer = try NookRecordWriter(
            fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video],
            onFailure: { log.add($0) }
        )
        try await feedSeconds(writer, 25)
        #expect(log.all.isEmpty)

        // A picture of another size: the encoder refuses it a moment later, and
        // the writer is failed from then on.
        // Offered until the writer takes it: a full encoder queue turns a sample
        // away, and a turned-away bad picture would prove nothing.
        let offerDeadline = Date().addingTimeInterval(10)
        while !writer.append(try Self.frame(at: 25.05, width: 128, height: 128), to: .video) {
            guard Date() < offerDeadline else { throw FeedTimeout() }
            try await Task.sleep(for: .milliseconds(2))
        }
        var next = 25.1
        let deadline = Date().addingTimeInterval(15)
        while log.all.isEmpty, Date() < deadline {
            _ = writer.append(try Self.frame(at: next), to: .video)
            next += 1.0 / 30
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(log.all.count == 1)

        // Later appends find a failed writer and say nothing more.
        for _ in 0..<30 {
            _ = writer.append(try Self.frame(at: next), to: .video)
            next += 1.0 / 30
        }
        #expect(log.all.count == 1)
        let failure = try #require(log.all.first)
        #expect(failure.atSeconds >= 25)
        #expect(failure.domain == AVFoundationErrorDomain)

        // The file as it stands plays: that is what the fragments are for.
        #expect(await isPlayable(url))
        #expect(try await duration(of: url) > 15)
        await #expect(throws: (any Error).self) { try await writer.finish() }
        #expect(await isPlayable(url))
    }

    @Test func aWriterThatNeverFailsNeverCallsBack() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let log = FailureLog()
        let writer = try NookRecordWriter(
            fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video],
            onFailure: { log.add($0) }
        )
        try await feedSeconds(writer, 2)
        try await writer.finish()
        #expect(log.all.isEmpty)
    }

    /// Copies what is on disk now, the way a crash or a force quit leaves it.
    func copyOfFileOnDisk(_ url: URL, name: String) throws -> URL {
        let copy = url.deletingLastPathComponent().appendingPathComponent(name)
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    @Test func movieFragmentIntervalLeavesAPlayableMP4AfterAnAbandonedWrite() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        try await feedSeconds(writer, 25)

        // Abandoned: the writer is never finished. The fragments the writer
        // thread has flushed are on disk and play, up to the last whole one.
        var copy: URL?
        var seconds = 0.0
        let deadline = Date().addingTimeInterval(10)
        while seconds < 15, Date() < deadline {
            let candidate = try copyOfFileOnDisk(url, name: "abandoned-\(UUID().uuidString).mp4")
            copy = candidate
            seconds = (try? await duration(of: candidate)) ?? 0
            if seconds < 15 { try await Task.sleep(for: .milliseconds(100)) }
        }
        defer { copy.map { try? FileManager.default.removeItem(at: $0) } }
        #expect(seconds > 15, "an abandoned fragmented .mp4 should play; got \(seconds) s")
        #expect(await isPlayable(try #require(copy)))
        try await writer.finish()
    }

    @Test func withoutAFragmentIntervalAnAbandonedMP4DoesNotPlay() async throws {
        // The control for the test above: a plain writer's MP4 has no index
        // until it is finished, so a copy taken mid-write is unreadable.
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var index = 0
        while index < 25 * 30 {
            if input.isReadyForMoreMediaData {
                #expect(input.append(try Self.frame(at: Double(index) / 30)))
                index += 1
            } else {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        try await Task.sleep(for: .milliseconds(500))
        let copy = try copyOfFileOnDisk(url, name: "plain-abandoned-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: copy) }
        #expect(!(await isPlayable(copy)))
        input.markAsFinished()
        await writer.finishWriting()
    }

    @Test func aFragmentedFileStillFinishesAsOneNormalMovie() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video, .macSound])
        // Long enough to cross two fragment boundaries (10 s and 20 s).
        for index in 0..<(25 * 30) {
            try await feed(writer, frame: Double(index) / 30)
            if index % 3 == 0 {
                let deadline = Date().addingTimeInterval(10)
                while !writer.append(try Self.silence(at: Double(index) / 30 + 0.001, frames: 1_600), to: .macSound) {
                    guard Date() < deadline else { throw FeedTimeout() }
                    try await Task.sleep(for: .milliseconds(2))
                }
            }
        }
        try await writer.finish()
        let asset = AVURLAsset(url: url)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await duration(of: url) > 24.5)
        #expect(await isPlayable(url))
    }

    // MARK: Counting what is dropped (R9)

    @Test func everyPictureOfferedIsEitherWrittenOrCountedAsDropped() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        // As fast as they can be offered: some may find the encoder busy.
        for index in 0..<200 { writer.append(try Self.frame(at: Double(index) / 30), to: .video) }
        let stats = writer.stats
        #expect(stats.videoWritten + stats.videoDropped == 200)
        #expect(stats.videoWritten > 0)
        try await writer.finish()
    }

    @Test func aPictureThatDoesNotMoveForwardIsCountedAsDropped() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        try await feed(writer, frame: 1)
        try await feed(writer, frame: 1.2)
        #expect(!writer.append(try Self.frame(at: 1.2), to: .video))
        #expect(!writer.append(try Self.frame(at: 1.1), to: .video))
        let stats = writer.stats
        #expect(stats.videoWritten == 2)
        #expect(stats.videoDropped == 2)
        try await writer.finish()
    }

    @Test func aPauseAndSoundBeforeThePictureAreNotDrops() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video, .macSound])
        // Sound before the first picture, and a picture during a pause: both
        // are on purpose.
        #expect(!writer.append(try Self.silence(at: 0.5), to: .macSound))
        try await feed(writer, frame: 1)
        writer.pause(at: CMTime(seconds: 2, preferredTimescale: 600))
        #expect(!writer.append(try Self.frame(at: 2.5), to: .video))
        let stats = writer.stats
        #expect(stats.videoDropped == 0)
        #expect(stats.macSoundDropped == 0)
        try await writer.finish()
    }

    @Test func eachTrackKeepsItsOwnCount() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video, .macSound, .voice])
        try await feed(writer, frame: 1)
        let deadline = Date().addingTimeInterval(10)
        while !writer.append(try Self.silence(at: 1.1), to: .voice) {
            guard Date() < deadline else { throw FeedTimeout() }
            try await Task.sleep(for: .milliseconds(2))
        }
        writer.noteDropped(.voice)
        writer.noteDropped(.voice)
        let stats = writer.stats
        #expect(stats.written(.voice) == 1)
        #expect(stats.dropped(.voice) == 2)
        #expect(stats.written(.macSound) == 0)
        #expect(stats.dropped(.macSound) == 0)
        #expect(stats.written(.video) == 1)
        try await writer.finish()
    }

    @Test func theFileTimeOfTheNewestSampleIsKept() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        for index in 0..<90 { try await feed(writer, frame: 5 + Double(index) / 30) }
        let seconds = writer.stats.writtenSeconds
        #expect(seconds > 2.9 && seconds < 3.0)
        try await writer.finish()
    }

    // MARK: Junk files (R8)

    @Test func aWriterThatGotNoPictureLeavesNoFileEvenAfterAPause() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        writer.pause(at: CMTime(seconds: 1, preferredTimescale: 600))
        #expect(!writer.append(try Self.frame(at: 2), to: .video))
        await #expect(throws: NookRecordWriter.WriterError.noFrames) { try await writer.finish() }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
