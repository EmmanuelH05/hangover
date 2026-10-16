import AVFoundation
import CoreMedia
import Foundation
import OSLog

private let writerLog = Logger(subsystem: "app.openisland", category: "record")

/// Writes captured frames and audio to an MP4 while the capture is still
/// running. The capture threads call `append` directly. Every call lands on
/// the writer's own serial queue, which guards all of its state.
final class NookRecordWriter: @unchecked Sendable {
    enum Track: Sendable, Hashable { case video, macSound, voice }

    enum WriterError: Error, Equatable {
        /// Finishing found no picture at all, so there is no file to keep.
        case noFrames
        case failed
    }

    /// What has gone into the file and what was turned away, per track. A
    /// sample is "dropped" when it was meant for the file and could not go
    /// in: its input was not ready, it could not be retimed, or a picture
    /// did not move forward. Samples held back by a pause, or sound from
    /// before the first picture, are not drops.
    struct Stats: Equatable, Sendable {
        var videoWritten = 0
        var videoDropped = 0
        var macSoundWritten = 0
        var macSoundDropped = 0
        var voiceWritten = 0
        var voiceDropped = 0
        /// File time of the newest sample written, in seconds.
        var writtenSeconds: Double = 0

        func written(_ track: Track) -> Int {
            switch track {
            case .video: videoWritten
            case .macSound: macSoundWritten
            case .voice: voiceWritten
            }
        }

        func dropped(_ track: Track) -> Int {
            switch track {
            case .video: videoDropped
            case .macSound: macSoundDropped
            case .voice: voiceDropped
            }
        }

        mutating func countWritten(_ track: Track) {
            switch track {
            case .video: videoWritten += 1
            case .macSound: macSoundWritten += 1
            case .voice: voiceWritten += 1
            }
        }

        mutating func countDropped(_ track: Track) {
            switch track {
            case .video: videoDropped += 1
            case .macSound: macSoundDropped += 1
            case .voice: voiceDropped += 1
            }
        }
    }

    /// The first time the writer found itself failed, reported once.
    struct Failure: Equatable, Sendable {
        /// How far into the recording the file got, in whole seconds.
        var atSeconds: Int
        /// The underlying error, for the log.
        var domain: String
        var code: Int
    }

    /// The file is cut into fragments this far apart. A fragmented MP4 plays
    /// up to its last whole fragment even if the app crashes, is force quit
    /// or the writer fails midway, which a plain MP4 (its index is written at
    /// the end) never does. A real writer shows that `.mp4` honors it (see
    /// the writer tests), so the file stays an MP4. A clip that is cut short
    /// before its first fragment (10 s) is lost. `initialMovieFragmentInterval`
    /// would cover that, and with it a real writer fails at the second fragment
    /// (AVFoundation -11800), so it is not used.
    static let fragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

    private let queue = DispatchQueue(label: "app.openisland.record.writer")
    private let writer: AVAssetWriter
    private let fileURL: URL
    private let onFailure: (@Sendable (Failure) -> Void)?
    private var inputs: [Track: AVAssetWriterInput] = [:]
    private var timeline = NookRecordTimeline()
    /// The file time of the first video frame. Nil until a frame arrives.
    private var sessionStart: CMTime?
    private var lastVideoTime: CMTime?
    private var counts = Stats()
    private var isClosed = false
    private var hasReportedFailure = false
    private var finishTask: Task<Void, Error>?

    /// The picture track is always written. `tracks` adds the sound tracks.
    /// `onFailure` runs once, from the thread that appended, the first time
    /// the writer is found failed.
    init(
        fileURL: URL, width: Int, height: Int, framesPerSecond: Int, tracks: Set<Track>,
        onFailure: (@Sendable (Failure) -> Void)? = nil
    ) throws {
        self.fileURL = fileURL
        self.onFailure = onFailure
        writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
        writer.movieFragmentInterval = Self.fragmentInterval

        let bitRate = max(4_000_000, width * height * framesPerSecond / 10)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoMaxKeyFrameIntervalKey: framesPerSecond * 2,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        try Self.add(video, to: writer)
        inputs[.video] = video

        for track in [Track.macSound, .voice] where tracks.contains(track) {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ])
            audio.expectsMediaDataInRealTime = true
            try Self.add(audio, to: writer)
            inputs[track] = audio
        }

        guard writer.startWriting() else { throw writer.error ?? WriterError.failed }
    }

    private static func add(_ input: AVAssetWriterInput, to writer: AVAssetWriter) throws {
        guard writer.canAdd(input) else { throw WriterError.failed }
        writer.add(input)
    }

    /// Drops samples while paused, shifts the rest, starts the session on
    /// the first video frame, drops audio that comes before it, and drops
    /// a sample its input is not ready for. Returns true when the sample
    /// was written.
    @discardableResult
    func append(_ buffer: CMSampleBuffer, to track: Track) -> Bool {
        let (written, failure) = queue.sync { () -> (Bool, Failure?) in
            let written = appendLocked(buffer, to: track)
            return (written, failureToReportLocked())
        }
        // Outside the queue, so a handler may call back into the writer.
        if let failure { onFailure?(failure) }
        return written
    }

    /// The failure to report, once: after the writer's status turns to failed.
    /// A failed writer answers every later append with false and no word, and
    /// the failure often shows itself a second or two after the sample that
    /// caused it, so every append looks.
    private func failureToReportLocked() -> Failure? {
        guard !hasReportedFailure, writer.status == .failed else { return nil }
        hasReportedFailure = true
        let error = writer.error as NSError?
        let failure = Failure(
            atSeconds: Int(counts.writtenSeconds),
            domain: error?.domain ?? "unknown",
            code: error?.code ?? 0
        )
        writerLog.error("record: the writer failed at \(failure.atSeconds, privacy: .public) s: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")
        return failure
    }

    /// What has been written and dropped so far.
    var stats: Stats {
        queue.sync { counts }
    }

    /// Whether the track's input can take a sample right now. The capture is
    /// paced by the screen and just drops a sample the input is not ready for
    /// (counted in `stats`). A caller that can wait, such as a test that feeds
    /// frames in a tight loop, looks first.
    func isReady(for track: Track) -> Bool {
        queue.sync { inputs[track]?.isReadyForMoreMediaData ?? false }
    }

    /// Counts a sample the capture side could not even hand over, such as a
    /// voice buffer that could not be moved onto the host clock.
    func noteDropped(_ track: Track) {
        queue.sync { counts.countDropped(track) }
    }

    func pause(at hostTime: CMTime) {
        queue.sync { timeline.pause(at: hostTime) }
    }

    func resume(at hostTime: CMTime) {
        queue.sync { timeline.resume(at: hostTime) }
    }

    /// Marks every input finished and closes the file. Safe to call twice,
    /// and a second call waits for the first.
    func finish() async throws {
        let task: Task<Void, Error> = queue.sync {
            if let finishTask { return finishTask }
            let created = Task<Void, Error> { try await self.closeFile() }
            finishTask = created
            return created
        }
        try await task.value
    }

    // MARK: - Appending

    private func appendLocked(_ buffer: CMSampleBuffer, to track: Track) -> Bool {
        guard !isClosed, writer.status == .writing, let input = inputs[track] else { return false }
        guard buffer.isValid, CMSampleBufferGetNumSamples(buffer) > 0 else { return false }
        let time = buffer.presentationTimeStamp
        guard time.isValid, let adjusted = timeline.adjusted(time) else { return false }

        if let start = sessionStart {
            // Sound from before the first frame has no place in the file.
            guard adjusted >= start else { return false }
        } else {
            guard track == .video else { return false }
            writer.startSession(atSourceTime: adjusted)
            sessionStart = adjusted
        }
        // A frame that does not move forward would fail the whole file.
        if track == .video, let last = lastVideoTime, adjusted <= last {
            counts.countDropped(track)
            return false
        }
        guard input.isReadyForMoreMediaData else {
            counts.countDropped(track)
            return false
        }

        let shift = time - adjusted
        let sample: CMSampleBuffer
        if CMTimeCompare(shift, .zero) == 0 {
            sample = buffer
        } else if let moved = Self.retimed(buffer, shiftedBy: shift) {
            sample = moved
        } else {
            counts.countDropped(track)
            return false
        }
        guard input.append(sample) else {
            writerLog.error("record: append failed: \(self.writer.error.map(NookRecordRules.describe) ?? "unknown", privacy: .public)")
            return false
        }
        if track == .video { lastVideoTime = adjusted }
        counts.countWritten(track)
        if let start = sessionStart {
            counts.writtenSeconds = max(counts.writtenSeconds, (adjusted - start).seconds)
        }
        return true
    }

    /// A copy of `buffer` that sits `shift` earlier. Every timing entry keeps
    /// its duration.
    static func retimed(_ buffer: CMSampleBuffer, shiftedBy shift: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(
            buffer, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count
        ) == noErr else { return nil }
        for index in timings.indices {
            timings[index].presentationTimeStamp = timings[index].presentationTimeStamp - shift
            if timings[index].decodeTimeStamp.isValid {
                timings[index].decodeTimeStamp = timings[index].decodeTimeStamp - shift
            }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: count,
            sampleTimingArray: &timings, sampleBufferOut: &copy
        )
        return status == noErr ? copy : nil
    }

    // MARK: - Finishing

    private enum CloseStep {
        case noFrames
        case alreadyFailed(Error)
        case close
    }

    private func closeFile() async throws {
        let step: CloseStep = queue.sync {
            isClosed = true
            guard counts.videoWritten > 0 else {
                // No picture ever went in, whether none arrived or the first
                // one was refused. Cancelling deletes the empty file, and a
                // writer that already failed leaves it, so it is removed here.
                if writer.status == .writing { writer.cancelWriting() }
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                    } catch {
                        writerLog.error("record: could not remove the empty file: \(NookRecordRules.describe(error), privacy: .public)")
                    }
                }
                return .noFrames
            }
            guard writer.status == .writing else {
                return .alreadyFailed(writer.error ?? WriterError.failed)
            }
            for input in inputs.values { input.markAsFinished() }
            return .close
        }
        switch step {
        case .noFrames:
            throw WriterError.noFrames
        case let .alreadyFailed(error):
            throw error
        case .close:
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? WriterError.failed }
        }
    }
}
