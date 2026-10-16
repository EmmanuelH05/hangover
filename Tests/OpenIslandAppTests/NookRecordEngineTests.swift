import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

// MARK: - A capture that opens no stream

/// What `NookScreenRecorder` gets in place of a screen stream: a real writer
/// on a temp file, and events the test sends by hand. Nothing here touches
/// the screen, the camera or the microphone.
final class RecordFakeCapture: NookLiveCapture, @unchecked Sendable {
    let id: UUID
    let writer: NookRecordWriter
    let fileURL: URL
    let recordsVoice: Bool
    let quality: NookRecordQuality
    private let send: @Sendable (UUID, NookCaptureEvent) -> Void
    private let lock = NSLock()
    private var gate: AsyncStream<Void>?
    private var entered = false
    private var stopCount = 0
    private var abortCount = 0

    init(
        id: UUID, writer: NookRecordWriter, fileURL: URL, recordsVoice: Bool = false, quality: NookRecordQuality = .standard,
        send: @escaping @Sendable (UUID, NookCaptureEvent) -> Void
    ) {
        self.id = id
        self.writer = writer
        self.fileURL = fileURL
        self.recordsVoice = recordsVoice
        self.quality = quality
        self.send = send
    }

    /// Holds `start` open until the stream is finished.
    func holdStart(_ stream: AsyncStream<Void>) { lock.withLock { gate = stream } }
    var hasEnteredStart: Bool { lock.withLock { entered } }
    var stopCaptures: Int { lock.withLock { stopCount } }
    var aborts: Int { lock.withLock { abortCount } }

    func emit(_ event: NookCaptureEvent) { send(id, event) }

    func start() async throws {
        let held = lock.withLock { () -> AsyncStream<Void>? in
            entered = true
            return gate
        }
        if let held {
            for await _ in held { break }
        }
    }

    func stopCapture() async { lock.withLock { stopCount += 1 } }

    func abort() async {
        lock.withLock { abortCount += 1 }
        try? await writer.finish()
    }
}

/// An engine wired to fake captures, with the phases it reported written down.
@MainActor
final class RecordEngineRig {
    let folder: URL
    let fileURL: URL
    private(set) var recorder: NookScreenRecorder!
    private(set) var phases: [NookRecordPhase] = []
    private(set) var capture: RecordFakeCapture?
    private(set) var prepares = 0
    /// Holds the preparer open, the way a permission prompt or the picker does.
    var prepareGate: AsyncStream<Void>.Continuation?
    private var prepareStream: AsyncStream<Void>?
    var prepareError: Error?
    var startGate: AsyncStream<Void>?
    /// Records a voice track too, which the fake capture reports it was asked for.
    var recordsVoice = false
    /// The quality the fake capture reports it was made at.
    var quality: NookRecordQuality = .standard
    /// Opening this ends the first-frame deadline.
    let deadline = AsyncStream<Void>.makeStream()

    init(filePlays: @escaping @Sendable (URL) async -> Bool = NookScreenRecorder.fileLooksPlayable) {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("record-engine-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("Recording.mp4")
        let deadlineStream = deadline.stream
        recorder = NookScreenRecorder(
            prepare: { [unowned self] _, _, url, _, id, send, token in
                try await self.prepare(url: url, id: id, send: send, token: token)
            },
            sleep: { _ in for await _ in deadlineStream { return } },
            filePlays: filePlays
        )
        recorder.onPhaseChange = { [unowned self] phase in phases.append(phase) }
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Makes the preparer wait for `releasePrepare`.
    func holdPrepare() {
        let pair = AsyncStream<Void>.makeStream()
        prepareStream = pair.stream
        prepareGate = pair.continuation
    }

    func releasePrepare() { prepareGate?.finish() }

    private func prepare(
        url: URL, id: UUID, send: @escaping @Sendable (UUID, NookCaptureEvent) -> Void, token: NookStartToken
    ) async throws -> any NookLiveCapture {
        prepares += 1
        if let prepareStream {
            // A Stop closes this wait, the way it closes the window picker.
            token.onCancel = { [weak self] in self?.releasePrepare() }
            for await _ in prepareStream { break }
        }
        if let prepareError { throw prepareError }
        let writer = try NookRecordWriter(
            fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: recordsVoice ? [.video, .voice] : [.video],
            onFailure: { failure in send(id, .writerFailed(failure)) }
        )
        let capture = RecordFakeCapture(id: id, writer: writer, fileURL: url, recordsVoice: recordsVoice, quality: quality, send: send)
        if let startGate { capture.holdStart(startGate) }
        self.capture = capture
        return capture
    }

    func start() async {
        await recorder.start(options: NookRecordOptions(), target: .display(1), fileURL: fileURL, islandWindows: [])
    }

    /// Writes `count` pictures into the file, the way the stream would.
    func feed(_ count: Int) async throws {
        let feeder = NookRecordWriterTests()
        let writer = try #require(capture?.writer)
        for index in 0..<count { try await feeder.feed(writer, frame: Double(index) / 30) }
    }

    /// Waits for the main actor to run what the capture queued.
    func until(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2_000 where !condition() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}

// MARK: - The engine

@MainActor @Suite(.serialized) struct NookRecordEngineTests {
    // MARK: Cancelling a start (R1)

    @Test func aStopWhileTheStartWaitsOnAPromptEndsItWithNoFailure() async {
        let rig = RecordEngineRig()
        rig.holdPrepare()
        let starting = Task { await rig.start() }
        await rig.until { rig.prepares == 1 }

        await rig.recorder.stop()
        rig.releasePrepare()
        await starting.value

        #expect(rig.phases == [.idle])
        #expect(rig.capture?.aborts == 1)
        #expect(!rig.fileExists)
    }

    /// Two tasks made one after the other on the main actor run in that order. The
    /// first calls `start`, which makes the engine's own task and waits on it. The
    /// second is Stop, and it runs before the engine's task has had a turn. The
    /// result is checked after every round: if the order ever differed, `phases`
    /// would not be `[.idle]` and the round would fail instead of passing blind.
    private func stopBeforeTheStartTaskRuns(_ rig: RecordEngineRig) async {
        let starting = Task { await rig.start() }
        let stopping = Task { await rig.recorder.stop() }
        await stopping.value
        await starting.value
    }

    @Test func aStopBeforeTheStartTaskFirstRunsOpensNothingAtAll() async {
        for round in 0..<25 {
            let rig = RecordEngineRig()
            await stopBeforeTheStartTaskRuns(rig)

            #expect(rig.prepares == 0, "round \(round): no prompt, no picker, no stream: the Stop came first")
            #expect(rig.phases == [.idle], "round \(round)")
            #expect(rig.capture == nil, "round \(round)")
            #expect(!rig.fileExists, "round \(round)")
        }
    }

    @Test func aStartAfterThatStopStartsNormally() async {
        let rig = RecordEngineRig()
        await stopBeforeTheStartTaskRuns(rig)

        await rig.start()

        #expect(rig.prepares == 1)
        #expect(rig.capture != nil)
        await rig.recorder.stop()
    }

    @Test func aStartThatFailsBecauseItWasCancelledIsNotAFailure() async {
        let rig = RecordEngineRig()
        rig.holdPrepare()
        rig.prepareError = NookRecordFailure.pickerCancelled
        let starting = Task { await rig.start() }
        await rig.until { rig.prepares == 1 }

        await rig.recorder.stop()
        rig.releasePrepare()
        await starting.value

        #expect(rig.phases == [.idle])
    }

    @Test func aStartThatFailsOnItsOwnStillReportsTheFailure() async {
        let rig = RecordEngineRig()
        rig.prepareError = NookRecordFailure.noDisplay
        await rig.start()
        #expect(rig.phases == [.failed(.noDisplay)])
    }

    @Test func aStopWhileTheStreamIsStartingEndsAfterTheStreamIsUp() async {
        let rig = RecordEngineRig()
        let gate = AsyncStream<Void>.makeStream()
        rig.startGate = gate.stream
        let starting = Task { await rig.start() }
        await rig.until { rig.capture?.hasEnteredStart == true }

        let stopping = Task { await rig.recorder.stop() }
        for _ in 0..<20 { await Task.yield() }
        gate.continuation.finish()
        await stopping.value
        await starting.value

        // No picture ever came: a cancel leaves no failure and no file.
        #expect(rig.phases == [.saving, .idle])
        #expect(rig.capture?.stopCaptures == 1)
        #expect(!rig.fileExists)
    }

    @Test func aStopAfterTheStartButBeforeAnyPictureLeavesNothingBehind() async {
        let rig = RecordEngineRig()
        await rig.start()
        #expect(rig.phases.isEmpty)

        await rig.recorder.stop()

        #expect(rig.phases == [.saving, .idle])
        #expect(!rig.fileExists)
    }

    @Test func aSecondStartWhileOneIsUnderWayIsReportedNotSwallowed() async {
        let rig = RecordEngineRig()
        rig.holdPrepare()
        let starting = Task { await rig.start() }
        await rig.until { rig.prepares == 1 }

        await rig.start()
        #expect(rig.prepares == 1)
        #expect(rig.phases == [.failed(.couldNotStart)])

        await rig.recorder.stop()
        rig.releasePrepare()
        await starting.value
    }

    @Test func aSecondStartDuringALiveRecordingMakesNoSecondStreamAndLeavesItAlone() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        try await rig.feed(10)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        await rig.start()

        #expect(rig.prepares == 1)
        guard case .recording = rig.phases.last else {
            Issue.record("the live recording was knocked off its phase: \(rig.phases)")
            return
        }
        await rig.recorder.stop()
    }

    // MARK: The first-frame watchdog (R1)

    @Test func aStreamThatSendsNoPictureEndsAfterTheDeadlineWithItsOwnFailure() async {
        let rig = RecordEngineRig()
        await rig.start()
        #expect(rig.phases.isEmpty)

        rig.deadline.continuation.yield(())
        await rig.until { rig.phases.contains(.failed(.noPicture)) }

        #expect(rig.phases == [.saving, .failed(.noPicture)])
        #expect(rig.capture?.stopCaptures == 1)
        #expect(!rig.fileExists)
    }

    @Test func aPictureBeforeTheDeadlineKeepsTheRecordingGoing() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        try await rig.feed(15)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        rig.deadline.continuation.yield(())
        for _ in 0..<50 { await Task.yield() }
        #expect(rig.phases.count == 1)
        guard case .recording = rig.phases.first else {
            Issue.record("expected recording, got \(rig.phases)")
            return
        }
        #expect(rig.capture?.stopCaptures == 0)

        await rig.recorder.stop()
        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user))
    }

    @Test func aPictureAlreadyInTheFileBeatsTheDeadlineEvenBeforeItsEventArrives() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        // The stream wrote its first pictures. The `.firstFrame` event that says
        // so is still on its way to the main actor when the deadline passes.
        try await rig.feed(15)
        #expect(rig.phases.isEmpty)

        rig.deadline.continuation.yield(())
        for _ in 0..<50 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))

        #expect(rig.phases.isEmpty, "the watchdog must not close a file that has a picture in it")
        #expect(rig.capture?.stopCaptures == 0)

        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }
        guard case .recording = rig.phases.first else {
            Issue.record("expected recording, got \(rig.phases)")
            return
        }

        await rig.recorder.stop()
        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user))
        #expect(rig.fileExists)
    }

    // MARK: A stream that ends on its own

    @Test func aStreamThatDiesBeforeAnyPictureIsTheSameFailure() async {
        let rig = RecordEngineRig()
        await rig.start()
        rig.capture?.emit(.streamStopped(nil))
        await rig.until { rig.phases.contains(.failed(.noPicture)) }
        #expect(rig.phases == [.saving, .failed(.noPicture)])
        #expect(!rig.fileExists)
    }

    @Test func aStreamThatDiesAfterPicturesKeepsTheFile() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        try await rig.feed(15)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        rig.capture?.emit(.streamStopped(nil))
        await rig.until { rig.phases.count >= 3 }

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .system))
        #expect(rig.fileExists)
    }

    // MARK: A file that stops taking data (R2)

    @Test func aWriterFailureEndsTheRecordingAtOnceAndNamesTheTime() async throws {
        // Nothing that was written plays, as with a clip cut short before its
        // first fragment: a failure, and the file goes (see X5 below).
        let rig = RecordEngineRig(filePlays: { _ in false })
        await rig.start()
        try await rig.feed(90)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        rig.capture?.emit(.writerFailed(NookRecordWriter.Failure(atSeconds: 2, domain: "AVFoundationErrorDomain", code: -11800)))
        await rig.until { rig.phases.count >= 3 }

        // No waiting for a Stop: the stream is closed on the spot.
        #expect(rig.phases.suffix(2) == [.saving, .failed(.writerFailed(atSeconds: 2))])
        #expect(rig.capture?.stopCaptures == 1)
    }

    // MARK: Junk and lost partial files (R8)

    @Test func aPartialFileThatPlaysIsKeptAndHandedOverLikeAFinishedOne() async throws {
        let rig = RecordEngineRig(filePlays: { _ in true })
        await rig.start()
        try await rig.feed(90)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        rig.capture?.emit(.writerFailed(NookRecordWriter.Failure(atSeconds: 2, domain: "AVFoundationErrorDomain", code: -11800)))
        await rig.until { rig.phases.count >= 3 }

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .writeError(atSeconds: 2)))
        #expect(rig.fileExists)
    }

    @Test func aRealWriterFailureLeavesAFileThatPlaysAndIsKept() async throws {
        // The real thing: AVFoundation's own failure, 30 s in, and the real
        // check for whether the partial file plays.
        let rig = RecordEngineRig()
        await rig.start()
        let writer = try #require(rig.capture?.writer)
        let feeder = NookRecordWriterTests()
        for index in 0..<(25 * 30) { try await feeder.feed(writer, frame: Double(index) / 30) }
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }
        // A picture of another size: the encoder refuses it, and the writer is
        // failed from the next fragment on.
        let offerDeadline = Date().addingTimeInterval(10)
        while !writer.append(try NookRecordWriterTests.frame(at: 25.05, width: 128, height: 128), to: .video) {
            guard Date() < offerDeadline else { throw NookRecordWriterTests.FeedTimeout() }
            try await Task.sleep(for: .milliseconds(2))
        }
        var next = 25.1
        let deadline = Date().addingTimeInterval(20)
        while !rig.phases.contains(where: { if case .finished = $0 { true } else { false } }), Date() < deadline {
            _ = writer.append(try NookRecordWriterTests.frame(at: next), to: .video)
            next += 1.0 / 30
            try await Task.sleep(for: .milliseconds(10))
        }

        guard case let .finished(url, endedBy, _)? = rig.phases.last, case let .writeError(seconds) = endedBy else {
            Issue.record("expected a kept partial file, got \(rig.phases)")
            return
        }
        #expect(url == rig.fileURL)
        #expect(seconds >= 25)
        #expect(await NookScreenRecorder.fileLooksPlayable(url))
        #expect(try await AVURLAsset(url: url).load(.duration).seconds > 15)
    }

    // MARK: A partial file that does not play is not left behind (X5)

    @Test func aPartialFileThatDoesNotPlayIsDeletedNotLeftInMovies() async throws {
        let rig = RecordEngineRig(filePlays: { _ in false })
        await rig.start()
        try await rig.feed(90)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }
        #expect(rig.fileExists, "the writer has a file on disk before the failure")

        rig.capture?.emit(.writerFailed(NookRecordWriter.Failure(atSeconds: 2, domain: "AVFoundationErrorDomain", code: -11800)))
        await rig.until { rig.phases.count >= 3 }

        #expect(rig.phases.last == .failed(.writerFailed(atSeconds: 2)))
        #expect(!rig.fileExists)
    }

    // MARK: What counts as a file that plays (X5)

    private func tempFile(_ name: String = "\(UUID().uuidString).mp4") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    @Test func aFileOfGarbageDoesNotPlay() async throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x41, count: 4_096).write(to: url)
        #expect(await !NookScreenRecorder.fileLooksPlayable(url))
    }

    @Test func aFileThatIsNotThereDoesNotPlay() async {
        #expect(await !NookScreenRecorder.fileLooksPlayable(tempFile()))
    }

    @Test func aFileWithSoundAndNoPictureDoesNotPlay() async throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<20 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            #expect(input.append(try NookRecordWriterTests.silence(at: Double(index) / 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()

        // It is a real, playable, two second file. It is not a screen recording.
        let asset = AVURLAsset(url: url)
        #expect(try await asset.load(.isPlayable))
        #expect(try await asset.load(.duration).seconds > 1)
        #expect(await !NookScreenRecorder.fileLooksPlayable(url))
    }

    @Test func aFinishedRecordingPlays() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        try await rig.feed(60)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }
        await rig.recorder.stop()

        #expect(await NookScreenRecorder.fileLooksPlayable(rig.fileURL))
    }

    @Test func aFileCutShortBeforeItsFirstFragmentDoesNotPlay() async throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let writer = try NookRecordWriter(fileURL: url, width: 64, height: 64, framesPerSecond: 30, tracks: [.video])
        let feeder = NookRecordWriterTests()
        for index in 0..<(3 * 30) { try await feeder.feed(writer, frame: Double(index) / 30) }
        try await Task.sleep(for: .milliseconds(300))

        // What a crash would leave: the bytes on disk now, copied.
        let cut = tempFile(); defer { try? FileManager.default.removeItem(at: cut) }
        try FileManager.default.copyItem(at: url, to: cut)
        #expect(await !NookScreenRecorder.fileLooksPlayable(cut))
        try await writer.finish()
    }

    // MARK: Dropped frames (R9)

    /// Pictures that do not move forward are turned away by the writer.
    func feedWithDrops(_ rig: RecordEngineRig, kept: Int, repeated: Int) async throws {
        try await rig.feed(kept)
        let writer = try #require(rig.capture?.writer)
        for _ in 0..<repeated { writer.append(try NookRecordWriterTests.frame(at: 0.0), to: .video) }
    }

    @Test func aShareOfDroppedPicturesIsSaidInTheSavedNotice() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        try await feedWithDrops(rig, kept: 90, repeated: 30)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        await rig.recorder.stop()

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user, notes: [.droppedFrames]))
    }

    @Test func aShareOfDroppedPicturesAtHighQualityAlsoSuggestsStandard() async throws {
        let rig = RecordEngineRig()
        rig.quality = .high
        await rig.start()
        try await feedWithDrops(rig, kept: 90, repeated: 30)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        await rig.recorder.stop()

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user, notes: [.droppedFrames, .suggestStandard]))
    }

    @Test func highQualityWithFewDropsSaysNothing() async throws {
        let rig = RecordEngineRig()
        rig.quality = .high
        await rig.start()
        try await feedWithDrops(rig, kept: 90, repeated: 2)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        await rig.recorder.stop()

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user))
    }

    @Test func aFewDroppedPicturesAreNotWorthAWord() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        try await feedWithDrops(rig, kept: 90, repeated: 2)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        await rig.recorder.stop()

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user))
    }

    // MARK: Sentences that point at the right fix (R4, R5)

    @Test func eachStartProblemReportsItsOwnFailure() async {
        let cases: [(any Error, NookRecordFailure)] = [
            (NookRecordFailure.pickerFailed, .pickerFailed),
            (NookRecordFailure.noMicrophone, .noMicrophone),
            (NookRecordFailure.lowDisk, .lowDisk),
            (NSError(domain: "SomeOtherDomain", code: 9), .couldNotStart),
        ]
        for (error, expected) in cases {
            let rig = RecordEngineRig()
            rig.prepareError = error
            await rig.start()
            #expect(rig.phases == [.failed(expected)])
        }
    }

    @Test func aRecordingThatRanOutOfSpaceEndsAsLowDiskAndKeepsTheFile() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        try await rig.feed(15)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        rig.capture?.emit(.lowDisk)
        await rig.until { rig.phases.count >= 3 }

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .lowDisk))
        #expect(rig.fileExists)
    }

    @Test func aPlainStopEndsAsUser() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        try await rig.feed(15)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        await rig.recorder.stop()

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user))
    }

    // MARK: Voice (R6)

    /// Writes pictures and, when asked, a voice buffer with each of every
    /// third picture, the way the stream and the microphone would.
    func feedPicturesWithVoice(_ rig: RecordEngineRig, seconds: Int, withVoice: Bool) async throws {
        let writer = try #require(rig.capture?.writer)
        let feeder = NookRecordWriterTests()
        for index in 0..<(seconds * 30) {
            try await feeder.feed(writer, frame: Double(index) / 30)
            guard withVoice, index % 3 == 0 else { continue }
            let deadline = Date().addingTimeInterval(10)
            while !writer.append(try NookRecordWriterTests.silence(at: Double(index) / 30 + 0.001, frames: 1_600), to: .voice) {
                guard Date() < deadline else { throw NookRecordWriterTests.FeedTimeout() }
                try await Task.sleep(for: .milliseconds(2))
            }
        }
    }

    @Test func aWarningFromTheCaptureReachesTheModelWithoutEndingTheRecording() async throws {
        let rig = RecordEngineRig()
        var warnings: [NookRecordWarning] = []
        rig.recorder.onWarning = { warnings.append($0) }
        await rig.start()
        try await rig.feed(15)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        rig.capture?.emit(.warning(.voiceLost))
        await rig.until { !warnings.isEmpty }

        #expect(warnings == [.voiceLost])
        #expect(rig.phases.count == 1)
        await rig.recorder.stop()
    }

    @Test func voiceThatWasOnAndWroteNothingIsSaidInTheSavedNotice() async throws {
        let rig = RecordEngineRig()
        rig.recordsVoice = true
        await rig.start()
        try await feedPicturesWithVoice(rig, seconds: 1, withVoice: false)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        await rig.recorder.stop()

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user, notes: [.noVoice]))
    }

    @Test func voiceThatWasWrittenAddsNothing() async throws {
        let rig = RecordEngineRig()
        rig.recordsVoice = true
        await rig.start()
        try await feedPicturesWithVoice(rig, seconds: 1, withVoice: true)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }

        await rig.recorder.stop()

        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user))
    }

    @Test func noVoiceIsNeverSaidWhenVoiceWasOff() async throws {
        let rig = RecordEngineRig()
        await rig.start()
        try await rig.feed(15)
        rig.capture?.emit(.firstFrame)
        await rig.until { !rig.phases.isEmpty }
        await rig.recorder.stop()
        #expect(rig.phases.last == .finished(rig.fileURL, endedBy: .user))
    }
}
