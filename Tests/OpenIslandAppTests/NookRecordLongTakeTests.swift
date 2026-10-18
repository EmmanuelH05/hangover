import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import OpenIslandApp

/// A recording has no time limit. The 1.0.13 writer failed at a fragment
/// boundary about a minute in (AVFoundation -11800 over -16341, logged as "the
/// writer failed at 70 s"), which cut every longer take short. Solid gray
/// frames never showed it: the encoder only reorders frames when the picture
/// moves, and a reordered frame across a boundary is what the fragment writer
/// refuses. These pictures move and carry noise, at a real screen's aspect,
/// with the Mac's sound beside them, for three minutes of file time.
@Suite(.serialized) struct NookRecordLongTakeTests {
    struct FeedTimeout: Error {}

    static let width = 640
    static let height = 360
    static let framesPerSecond = 30

    /// A picture that differs from the one before it: a band that slides down
    /// the frame and noise over the whole of it.
    static func movingFrame(index: Int) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        let buffer = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var seed = UInt32(truncatingIfNeeded: index &* 2_654_435_761)
        for y in 0..<height {
            let band: UInt8 = (y + index * 4) % height < 40 ? 0xF0 : 0x30
            let row = base + y * rowBytes
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = UInt8(truncatingIfNeeded: seed >> 26)
                row[x * 4] = band &+ noise
                row[x * 4 + 1] = UInt8(truncatingIfNeeded: x + index) &+ noise
                row[x * 4 + 2] = band
                row[x * 4 + 3] = 0xFF
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(framesPerSecond)),
            presentationTimeStamp: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(framesPerSecond)),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: try #require(format),
            sampleTiming: &timing, sampleBufferOut: &sample
        )
        return try #require(sample)
    }

    /// Offers a sample until its input has room, as a screen-paced capture
    /// would have had time for.
    func offer(_ writer: NookRecordWriter, _ sample: CMSampleBuffer, to track: NookRecordWriter.Track) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !writer.isReady(for: track) || !writer.append(sample, to: track) {
            guard Date() < deadline else { throw FeedTimeout() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test(.timeLimit(.minutes(5)))
    func threeMinutesOfMovingPictureAndSoundWriteWithoutAFailure() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let failures = NookRecordWriterTests.FailureLog()
        let writer = try NookRecordWriter(
            fileURL: url, width: Self.width, height: Self.height, framesPerSecond: Self.framesPerSecond,
            tracks: [.video, .macSound], onFailure: { failures.add($0) }
        )

        let seconds = 180
        var nextSound = 0.1
        for index in 0..<(seconds * Self.framesPerSecond) {
            try await offer(writer, try Self.movingFrame(index: index), to: .video)
            let now = Double(index) / Double(Self.framesPerSecond)
            while nextSound <= now {
                try await offer(writer, try NookRecordWriterTests.silence(at: nextSound), to: .macSound)
                nextSound += 0.1
            }
            if !failures.all.isEmpty { break }
        }
        try await writer.finish()

        #expect(failures.all.isEmpty, "the writer failed at \(failures.all.first?.atSeconds ?? -1) s")
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(duration > Double(seconds) - 1, "the file is \(duration) s long")
    }
}
