import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

private let recordLog = Logger(subsystem: "app.openisland", category: "record")

/// Carries a value that is not `Sendable` across one hop that is safe by
/// construction: the value is made on one side and only read on the other.
private struct Handoff<Value>: @unchecked Sendable {
    let value: Value
}

/// What a running capture tells the engine. Sent from private queues.
enum NookCaptureEvent: Sendable {
    case firstFrame
    case lowDisk
    case streamStopped(Error?)
    /// The file stopped taking data. Reported once, as soon as the writer knows.
    case writerFailed(NookRecordWriter.Failure)
    /// Something went wrong that the recording goes on through.
    case warning(NookRecordWarning)
}

/// What the engine needs from one running capture. `LiveCapture` is the real
/// one. A test hands the engine a fake that opens no stream, which is how the
/// start, the cancel and the finish paths are tested without a screen.
protocol NookLiveCapture: AnyObject, Sendable {
    var id: UUID { get }
    var writer: NookRecordWriter { get }
    var fileURL: URL { get }
    /// True when the voice track was asked for.
    var recordsVoice: Bool { get }
    /// The quality the recording was made at.
    var quality: NookRecordQuality { get }
    /// Brings the stream (and the microphone) up.
    func start() async throws
    /// Stops the stream and the microphone.
    func stopCapture() async
    /// Undoes a start that produced no recording.
    func abort() async
}

/// A Stop that arrives while the engine is still starting. The permission
/// check, the mic prompt, the picker and `startCapture` all look at it after
/// they return, and give up when it is set.
@MainActor
final class NookStartToken {
    private(set) var isCancelled = false
    /// Closes whatever the start is waiting on, such as the window picker.
    var onCancel: (@MainActor () -> Void)?

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel?()
    }

    func throwIfCancelled() throws {
        if isCancelled { throw NookStartCancelled() }
    }
}

/// Thrown inside a start that was cancelled. Never shown to anyone.
struct NookStartCancelled: Error {}

/// Builds the capture for one recording: permissions, the picker, the writer
/// and the stream. The first four arguments are `start`'s, then the id the
/// capture's events carry, where they go, and the cancel token.
typealias NookCapturePreparer = @MainActor (
    NookRecordOptions, NookRecordTarget, URL, [CGWindowID], UUID,
    @escaping @Sendable (UUID, NookCaptureEvent) -> Void, NookStartToken
) async throws -> any NookLiveCapture

/// The real recording engine (D67): a ScreenCaptureKit stream feeds a
/// `NookRecordWriter`. Everything the stream and the microphone produce is
/// handled on private queues. Only the phase changes reach the main actor.
@MainActor
final class NookScreenRecorder: NookRecording {
    var onPhaseChange: ((NookRecordPhase) -> Void)?
    var onWarning: ((NookRecordWarning) -> Void)?

    private var phase: NookRecordPhase = .idle
    private var capture: (any NookLiveCapture)?
    /// The start that is under way, from the first check to `startCapture`
    /// returning. Stop reaches it through its token.
    private var startTask: Task<Void, Never>?
    private var startToken: NookStartToken?
    /// The one finish that is under way. Stop, a dead stream and a full disk
    /// all join it, so the file is closed once.
    private var finishing: Task<Void, Never>?
    /// Ends a start whose stream never sends a picture.
    private var watchdog: Task<Void, Never>?
    private var hasFirstFrame = false

    private let prepareCapture: NookCapturePreparer
    private let sleep: @Sendable (Duration) async throws -> Void
    private let filePlays: @Sendable (URL) async -> Bool

    /// The app passes nothing. A test passes a fake capture, a `sleep` that
    /// waits on its own signal, and what it takes a file to count as playable.
    init(
        prepare: NookCapturePreparer? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        filePlays: @escaping @Sendable (URL) async -> Bool = NookScreenRecorder.fileLooksPlayable
    ) {
        self.filePlays = filePlays
        prepareCapture = prepare ?? { options, target, fileURL, windows, id, send, token in
            try await Self.prepareLive(
                options: options, target: target, fileURL: fileURL, islandWindows: windows,
                id: id, send: send, token: token
            )
        }
        self.sleep = sleep
    }

    // MARK: - NookRecording

    func start(options: NookRecordOptions, target: NookRecordTarget, fileURL: URL, islandWindows: [CGWindowID]) async {
        // Never two streams, whatever the caller does. A caller that is told
        // nothing would wait on a card that says "Starting" for good, so the
        // refusal is reported, unless a recording is live and must not be
        // knocked off its own phase.
        guard startTask == nil, capture == nil, finishing == nil else {
            recordLog.error("record: a start was refused, a recording is already under way")
            if capture == nil { report(.failed(.couldNotStart)) }
            return
        }
        let token = NookStartToken()
        startToken = token
        let task = Task { @MainActor [self] in
            await runStart(options: options, target: target, fileURL: fileURL, islandWindows: islandWindows, token: token)
        }
        startTask = task
        await task.value
    }

    func pause() {
        guard let capture, case .recording = phase else { return }
        capture.writer.pause(at: CMClockGetTime(CMClockGetHostTimeClock()))
        report(phase.pausing(at: Date()))
    }

    func resume() {
        guard let capture, case .paused = phase else { return }
        capture.writer.resume(at: CMClockGetTime(CMClockGetHostTimeClock()))
        report(phase.resuming(at: Date()))
    }

    func stop() async {
        if let finishing {
            await finishing.value
            return
        }
        // A start still asking for permission, waiting on the picker or on
        // the stream is cancelled. It unwinds on its own and reports `.idle`,
        // or closes the file when a picture got in.
        if let startTask {
            startToken?.cancel()
            await startTask.value
            if let finishing { await finishing.value }
            return
        }
        guard let capture else { return }
        await beginFinish(capture, cause: .user).value
    }

    // MARK: - Starting

    private func runStart(
        options: NookRecordOptions, target: NookRecordTarget, fileURL: URL, islandWindows: [CGWindowID],
        token: NookStartToken
    ) async {
        defer {
            startTask = nil
            startToken = nil
        }
        do {
            try await begin(options: options, target: target, fileURL: fileURL, islandWindows: islandWindows, token: token)
        } catch {
            // A person who pressed Stop gets no failure, whatever the start
            // was stopped by.
            if token.isCancelled {
                report(.idle)
            } else {
                report(.failed(Self.failure(for: error)))
            }
        }
    }

    private func begin(
        options: NookRecordOptions, target: NookRecordTarget, fileURL: URL, islandWindows: [CGWindowID],
        token: NookStartToken
    ) async throws {
        // A Stop can land between `start` making the task and the task first
        // running. The token is already cancelled then, and nothing below has
        // had the chance to close what it opens, so nothing below opens.
        try token.throwIfCancelled()
        let id = UUID()
        let capture = try await prepareCapture(
            options, target, fileURL, islandWindows, id,
            { [weak self] id, event in
                Task { @MainActor in self?.handle(event, from: id) }
            },
            token
        )
        if token.isCancelled {
            await capture.abort()
            throw NookStartCancelled()
        }
        // The stream can send its first frame before `start` returns, so the
        // capture is known to the recorder before the stream runs.
        hasFirstFrame = false
        self.capture = capture
        do {
            try await capture.start()
        } catch {
            await capture.abort()
            if self.capture === capture { self.capture = nil }
            throw error
        }
        if token.isCancelled {
            // Stop came while the stream was starting. Close it like any
            // stop: a file with a picture in it is kept, an empty one goes.
            await beginFinish(capture, cause: .user).value
            return
        }
        armWatchdog(for: capture)
    }

    /// A stream that starts and never sends a picture would leave the card on
    /// "Starting" with the menu bar indicator lit. After the deadline it is
    /// closed and the failure says what happened.
    private func armWatchdog(for capture: any NookLiveCapture) {
        guard !hasFirstFrame else { return }
        let wait = sleep
        watchdog = Task { @MainActor [self] in
            do {
                try await wait(NookRecordRules.firstFrameDeadline)
            } catch {
                return
            }
            guard !Task.isCancelled, self.capture === capture, !hasFirstFrame, finishing == nil else { return }
            // The first picture can be in the file while the event that says so
            // is still on its way to this actor. That is a picture that arrived.
            guard capture.writer.stats.videoWritten == 0 else {
                recordLog.info("record: the first picture was written as the deadline passed, the recording goes on")
                return
            }
            recordLog.error("record: no picture arrived within the deadline")
            _ = beginFinish(capture, cause: .noPicture)
        }
    }

    // MARK: - Building the live capture

    private static func prepareLive(
        options: NookRecordOptions, target: NookRecordTarget, fileURL: URL, islandWindows: [CGWindowID],
        id: UUID, send: @escaping @Sendable (UUID, NookCaptureEvent) -> Void, token: NookStartToken
    ) async throws -> any NookLiveCapture {
        // Before the permission prompt and before the window picker can open.
        try token.throwIfCancelled()
        // A window goes through Apple's picker, which needs no Screen Recording
        // permission. Full screen and area ask once.
        if target != .pickedWindow { try requireScreenAccess() }
        if options.voice {
            let allowed = await microphoneAllowed()
            try token.throwIfCancelled()
            if !allowed { throw NookRecordFailure.micPermissionDenied }
        }

        let folder = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            // The writer below fails on its own if the folder is really missing.
            recordLog.error("record: could not make the recordings folder: \(NookRecordRules.describe(error), privacy: .public)")
        }
        var spaceWatch = NookRecordSpaceWatch()
        switch spaceWatch.check(freeBytes: NookRecordRules.freeBytes(near: fileURL)) {
        case .stop: throw NookRecordFailure.lowDisk
        case let .unreadable(isFirst): if isFirst { logSpaceUnreadable() }
        case .fine: break
        }

        let source = try await resolve(target: target, options: options, islandWindows: islandWindows, token: token)
        try token.throwIfCancelled()
        let size = NookRecordRules.outputSize(source: source.pixelSize, quality: options.quality)
        let streamConfiguration = configuration(
            options: options, width: size.width, height: size.height, sourceRect: source.sourceRect
        )

        let writer: NookRecordWriter
        do {
            writer = try NookRecordWriter(
                fileURL: fileURL, width: size.width, height: size.height,
                framesPerSecond: options.quality.framesPerSecond,
                tracks: tracks(for: options),
                onFailure: { failure in send(id, .writerFailed(failure)) }
            )
        } catch {
            recordLog.error("record: writer failed: \(NookRecordRules.describe(error), privacy: .public)")
            throw NookRecordFailure.writeFailed
        }

        return LiveCapture(
            id: id, writer: writer, fileURL: fileURL,
            filter: Handoff(value: source.filter), configuration: Handoff(value: streamConfiguration),
            macSound: options.macSound, voice: options.voice, quality: options.quality, spaceWatch: spaceWatch, send: send
        )
    }

    /// What is recorded: the filter, the source's pixel size and, for an area,
    /// the part of the display in points.
    private struct Source {
        let filter: SCContentFilter
        let pixelSize: CGSize
        let sourceRect: CGRect?
    }

    private static func resolve(
        target: NookRecordTarget, options: NookRecordOptions, islandWindows: [CGWindowID], token: NookStartToken
    ) async throws -> Source {
        if case .pickedWindow = target {
            let request = WindowPickRequest()
            token.onCancel = { request.cancel() }
            defer { token.onCancel = nil }
            let filter: SCContentFilter
            switch await request.run() {
            case let .picked(handoff): filter = handoff.value
            case .cancelled: throw NookRecordFailure.pickerCancelled
            case .failed: throw NookRecordFailure.pickerFailed
            }
            try token.throwIfCancelled()
            let scale = CGFloat(filter.pointPixelScale)
            let pixels = CGSize(width: filter.contentRect.width * max(scale, 1), height: filter.contentRect.height * max(scale, 1))
            return Source(filter: filter, pixelSize: pixels, sourceRect: nil)
        }

        let displayID: CGDirectDisplayID
        switch target {
        case let .display(id), let .area(id, _): displayID = id
        case .pickedWindow: throw NookRecordFailure.noDisplay
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try token.throwIfCancelled()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NookRecordFailure.noDisplay
        }
        let left = Set(NookRecordRules.excludedWindows(island: islandWindows, includeIsland: options.includeIsland))
        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { left.contains($0.windowID) })

        let scale = pixelScale(of: displayID)
        let displayPoints = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        var area = displayPoints
        if case let .area(_, requested) = target {
            area = requested.intersection(displayPoints)
            guard !area.isNull, area.width >= 1, area.height >= 1 else { throw NookRecordFailure.noDisplay }
        }
        let pixels = CGSize(width: area.width * scale, height: area.height * scale)
        return Source(filter: filter, pixelSize: pixels, sourceRect: area == displayPoints ? nil : area)
    }

    private static func configuration(options: NookRecordOptions, width: Int, height: Int, sourceRect: CGRect?) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        if let sourceRect { configuration.sourceRect = sourceRect }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.quality.framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.queueDepth = 6
        configuration.capturesAudio = options.macSound
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        return configuration
    }

    private static func tracks(for options: NookRecordOptions) -> Set<NookRecordWriter.Track> {
        var tracks: Set<NookRecordWriter.Track> = [.video]
        if options.macSound { tracks.insert(.macSound) }
        if options.voice { tracks.insert(.voice) }
        return tracks
    }

    /// Pixels per point of a display, from its current mode.
    private static func pixelScale(of displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 2 }
        return max(1, CGFloat(mode.pixelWidth) / CGFloat(mode.width))
    }

    // MARK: - Permissions

    private static func requireScreenAccess() throws {
        if CGPreflightScreenCaptureAccess() { return }
        // The first call shows the system prompt and still answers false.
        if CGRequestScreenCaptureAccess() { return }
        throw NookRecordFailure.screenPermissionDenied
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    /// The sentence behind an error. Raw errors are logged and never shown.
    private static func failure(for error: Error) -> NookRecordFailure {
        if let failure = error as? NookRecordFailure { return failure }
        let nsError = error as NSError
        recordLog.error("record: start failed: \(NookRecordRules.describe(error), privacy: .public)")
        return NookRecordRules.startFailure(domain: nsError.domain, code: nsError.code)
    }

    // MARK: - Events and finishing

    /// What went into the file and what was turned away, per track. A drop is
    /// otherwise invisible until the video stutters.
    private static func logTotals(_ stats: NookRecordWriter.Stats) {
        recordLog.info("record: written video \(stats.videoWritten, privacy: .public) macSound \(stats.macSoundWritten, privacy: .public) voice \(stats.voiceWritten, privacy: .public); dropped video \(stats.videoDropped, privacy: .public) macSound \(stats.macSoundDropped, privacy: .public) voice \(stats.voiceDropped, privacy: .public)")
    }

    /// Whether what is on disk plays: AVFoundation can read it, it has a length
    /// and a picture track that loads. A fragmented file cut short passes; one
    /// with no index, or with no picture in it, does not. The reason it does not
    /// is logged.
    static let fileLooksPlayable: @Sendable (URL) async -> Bool = { url in
        let asset = AVURLAsset(url: url)
        do {
            guard try await asset.load(.isPlayable) else {
                recordLog.info("record: the partial file is not playable")
                return false
            }
            guard try await asset.load(.duration).seconds > 0 else {
                recordLog.info("record: the partial file has no length")
                return false
            }
            guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
                recordLog.info("record: the partial file has no picture track")
                return false
            }
            return true
        } catch {
            recordLog.error("record: the partial file could not be read: \(NookRecordRules.describe(error), privacy: .public)")
            return false
        }
    }

    /// A file that holds pictures and does not play is no recording. It is not
    /// left in Movies/Hangover for someone to find and fail to open.
    private static func removeUnplayableFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            recordLog.info("record: the partial file does not play, so it was removed")
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            recordLog.error("record: could not remove the partial file that does not play: \(NookRecordRules.describe(error), privacy: .public)")
        }
    }

    private func report(_ new: NookRecordPhase) {
        phase = new
        onPhaseChange?(new)
    }

    private func handle(_ event: NookCaptureEvent, from id: UUID) {
        guard let capture, capture.id == id else { return }
        switch event {
        case .firstFrame:
            hasFirstFrame = true
            watchdog?.cancel()
            watchdog = nil
            guard finishing == nil else { return }
            report(.recording(startedAt: Date(), pausedTotal: 0))
        case .lowDisk:
            _ = beginFinish(capture, cause: .lowDisk)
        case let .streamStopped(error):
            // The display went away, the lid closed, the screen locked, or the
            // person ended the share from the menu bar. Keep what we have.
            recordLog.error("record: stream stopped: \(error.map(NookRecordRules.describe) ?? "no error", privacy: .public)")
            _ = beginFinish(capture, cause: .system)
        case let .warning(warning):
            onWarning?(warning)
        case .writerFailed:
            // The clock would keep ticking over a file that takes nothing, so
            // it ends now and the failure names the time.
            _ = beginFinish(capture, cause: .writeError)
        }
    }

    /// The one path out of a recording: stop, a dead stream, a full disk and
    /// a stream that never sent a picture all come through here.
    private func beginFinish(_ capture: any NookLiveCapture, cause: NookRecordStopCause) -> Task<Void, Never> {
        if let finishing { return finishing }
        watchdog?.cancel()
        watchdog = nil
        let task = Task { @MainActor [self] in
            report(.saving)
            await capture.stopCapture()
            var finished = true
            do {
                try await capture.writer.finish()
            } catch NookRecordWriter.WriterError.noFrames {
                finished = false
                recordLog.info("record: nothing was recorded, the empty file is gone")
            } catch {
                finished = false
                recordLog.error("record: finish failed: \(NookRecordRules.describe(error), privacy: .public)")
            }
            let stats = capture.writer.stats
            Self.logTotals(stats)
            // A file that could not be closed properly may still play, up to the
            // last fragment. What plays is kept.
            let hasPartialFile = (cause == .writeError || !finished) && stats.videoWritten > 0
            let partialPlays = hasPartialFile ? await filePlays(capture.fileURL) : false
            if hasPartialFile, !partialPlays { Self.removeUnplayableFile(at: capture.fileURL) }
            if self.capture === capture { self.capture = nil }
            finishing = nil
            let notes = NookRecordRules.notes(
                voiceWasOn: capture.recordsVoice, voiceBuffersWritten: stats.voiceWritten,
                videoWritten: stats.videoWritten, videoDropped: stats.videoDropped, quality: capture.quality
            )
            report(NookRecordRules.phaseAfterFinish(
                fileURL: capture.fileURL, cause: cause, finishSucceeded: finished,
                videoFramesWritten: stats.videoWritten, secondsWritten: Int(stats.writtenSeconds),
                notes: notes, partialPlays: partialPlays
            ))
        }
        finishing = task
        return task
    }
}

/// Said once per recording: with the free space unreadable, nothing stops a
/// recording that fills the disk.
private func logSpaceUnreadable() {
    recordLog.error("record: the free space on the disk could not be read, the low-disk stop is off")
}

// MARK: - The running capture

/// One stream, its microphone and its writer. The stream's callbacks arrive on
/// `sampleQueue`, which is the only place the per-frame state is touched.
private final class LiveCapture: NSObject, NookLiveCapture, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let id: UUID
    let writer: NookRecordWriter
    let fileURL: URL

    private let sampleQueue = DispatchQueue(label: "app.openisland.record.samples")
    private let send: @Sendable (UUID, NookCaptureEvent) -> Void
    private let filter: Handoff<SCContentFilter>
    private let configuration: Handoff<SCStreamConfiguration>
    private let macSound: Bool
    private let voice: Bool
    var recordsVoice: Bool { voice }
    let quality: NookRecordQuality
    private var stream: SCStream?
    private var microphone: MicrophoneCapture?
    // Touched on `sampleQueue` only.
    private var sentFirstFrame = false
    private var sentLowDisk = false
    private var lastSpaceCheck: TimeInterval = 0
    private var spaceWatch: NookRecordSpaceWatch

    init(
        id: UUID, writer: NookRecordWriter, fileURL: URL,
        filter: Handoff<SCContentFilter>, configuration: Handoff<SCStreamConfiguration>,
        macSound: Bool, voice: Bool, quality: NookRecordQuality, spaceWatch: NookRecordSpaceWatch,
        send: @escaping @Sendable (UUID, NookCaptureEvent) -> Void
    ) {
        self.spaceWatch = spaceWatch
        self.id = id
        self.writer = writer
        self.fileURL = fileURL
        self.filter = filter
        self.configuration = configuration
        self.macSound = macSound
        self.voice = voice
        self.quality = quality
        self.send = send
        super.init()
    }

    /// Starts the microphone, then the stream. Sound that arrives before the
    /// first picture is dropped by the writer.
    func start() async throws {
        if voice {
            let microphone = try MicrophoneCapture(writer: writer) { [id, send] warning in
                send(id, .warning(warning))
            }
            self.microphone = microphone
            microphone.start()
        }
        let stream = SCStream(filter: filter.value, configuration: configuration.value, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if macSound { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue) }
        self.stream = stream
        try await stream.startCapture()
    }

    /// Stops the stream and the microphone. A stream that already died throws
    /// here, which is fine.
    func stopCapture() async {
        if let stream { try? await stream.stopCapture() }
        await microphone?.stop()
        stream = nil
        microphone = nil
    }

    /// Undoes a start that failed. Nothing was recorded, so the empty file goes.
    func abort() async {
        await stopCapture()
        try? await writer.finish()
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            if writer.append(sampleBuffer, to: .video), !sentFirstFrame {
                sentFirstFrame = true
                send(id, .firstFrame)
            }
            checkSpace()
        case .audio:
            writer.append(sampleBuffer, to: .macSound)
        default:
            break
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        send(id, .streamStopped(error))
    }

    // MARK: Frames

    /// Idle and blank frames carry no picture, the same filter `record.swift` uses.
    private static func isCompleteFrame(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int else { return false }
        return SCFrameStatus(rawValue: raw) == .complete
    }

    /// Once a second, stop for space when the disk is nearly full.
    private func checkSpace() {
        let now = ProcessInfo.processInfo.systemUptime
        guard !sentLowDisk, now - lastSpaceCheck >= 1 else { return }
        lastSpaceCheck = now
        switch spaceWatch.check(freeBytes: NookRecordRules.freeBytes(near: fileURL)) {
        case .stop:
            sentLowDisk = true
            send(id, .lowDisk)
        case let .unreadable(isFirst):
            if isFirst { logSpaceUnreadable() }
        case .fine:
            break
        }
    }
}

// MARK: - The microphone

/// Voice, on every macOS version: an `AVCaptureSession` with the default
/// audio input. Its buffers go to the writer's voice track on the host clock,
/// which is the clock the stream stamps its frames with.
///
/// The session can die without a word: AirPods disconnect, another app takes
/// the device, `startRunning` returns with nothing running. Each of those
/// sends one warning, so the person hears about it while they are recording.
private final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.openisland.record.voice")
    private let writer: NookRecordWriter
    private let warn: @Sendable (NookRecordWarning) -> Void
    private let lock = NSLock()
    private var hasWarned = false
    private var watch: NookCaptureSessionWatch?

    init(writer: NookRecordWriter, warn: @escaping @Sendable (NookRecordWarning) -> Void) throws {
        self.writer = writer
        self.warn = warn
        super.init()
        guard let device = AVCaptureDevice.default(for: .audio) else {
            recordLog.error("record: no microphone is connected")
            throw NookRecordFailure.noMicrophone
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            recordLog.error("record: the microphone could not be opened: \(NookRecordRules.describe(error), privacy: .public)")
            throw NookRecordFailure.noMicrophone
        }
        let output = AVCaptureAudioDataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            recordLog.error("record: the microphone could not be added to the session")
            throw NookRecordFailure.noMicrophone
        }
        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        watch = NookCaptureSessionWatch(session: session) { [weak self] problem in
            recordLog.error("record: the microphone session reported \(String(describing: problem), privacy: .public)")
            self?.warnOnce(.voiceLost)
        }
    }

    /// `startRunning` blocks, so it never runs on the caller's thread. A
    /// session that is not running when it returns did not start.
    func start() {
        queue.async {
            self.session.startRunning()
            if !self.session.isRunning {
                recordLog.error("record: the microphone session did not start")
                self.warnOnce(.voiceDidNotStart)
            }
        }
    }

    func stop() async {
        watch?.stop()
        watch = nil
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                self.session.stopRunning()
                done.resume()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = onHostClock(sampleBuffer) else {
            // Counted, so a voice track that came out thin shows in the totals.
            writer.noteDropped(.voice)
            return
        }
        writer.append(buffer, to: .voice)
    }

    /// One warning per recording is enough.
    private func warnOnce(_ warning: NookRecordWarning) {
        let isFirst = lock.withLock { () -> Bool in
            defer { hasWarned = true }
            return !hasWarned
        }
        if isFirst { warn(warning) }
    }

    /// The buffer on the host clock. Most inputs already stamp it there and
    /// come back untouched. One that runs on its own device clock is moved over.
    private func onHostClock(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let clock = session.synchronizationClock else { return buffer }
        let stamp = buffer.presentationTimeStamp
        let host = CMSyncConvertTime(stamp, from: clock, to: CMClockGetHostTimeClock())
        guard host.isValid, CMTimeCompare(host, stamp) != 0 else { return buffer }
        return NookRecordWriter.retimed(buffer, shiftedBy: stamp - host)
    }
}

// MARK: - The window picker

/// How the picker ended.
private enum PickOutcome {
    case picked(Handoff<SCContentFilter>)
    /// The person closed it, or a Stop did.
    case cancelled
    /// Apple's picker reported an error instead of opening.
    case failed
}

/// Shows Apple's picker for one window and answers with the filter it hands
/// back. Picked content needs no Screen Recording permission (WWDC23,
/// "What's new in privacy", Screen Capture picker).
@MainActor
private final class WindowPickRequest: NSObject, SCContentSharingPickerObserver {
    private var continuation: CheckedContinuation<PickOutcome, Never>?
    /// Set by a Stop that came before the picker was up, which the picker
    /// then never opens for.
    private var isCancelled = false

    func run() async -> PickOutcome {
        guard !isCancelled else { return .cancelled }
        let picker = SCContentSharingPicker.shared
        var configuration = picker.defaultConfiguration
        configuration.allowedPickerModes = [.singleWindow]
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<PickOutcome, Never>) in
            self.continuation = continuation
            picker.present(using: .window)
        }
        picker.remove(self)
        picker.isActive = false
        return outcome
    }

    /// A Stop pressed while the picker is up closes it with no answer.
    func cancel() {
        isCancelled = true
        answer(.cancelled)
    }

    private func answer(_ outcome: PickOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let picked = Handoff(value: filter)
        Task { @MainActor in self.answer(.picked(picked)) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.answer(.cancelled) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        recordLog.error("record: picker failed: \(NookRecordRules.describe(error), privacy: .public)")
        Task { @MainActor in self.answer(.failed) }
    }
}
