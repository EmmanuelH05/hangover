import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Why a recording is being closed. The engine passes this to the rule below.
enum NookRecordStopCause: Equatable, Sendable {
    /// Stop, Cancel, the shortcut, a click on the notch, or a quit.
    case user
    case lowDisk
    /// The stream died on its own: a display went away, the screen locked,
    /// or the person ended the share from the menu bar.
    case system
    /// The stream was up and no frame came.
    case noPicture
    /// The file stopped taking data.
    case writeError
}

/// Checks free space against the limit for one recording. When the space cannot
/// be read at all, the low-disk stop is off for that check, and the first time
/// that happens is worth a line in the log (and no more: it is checked every
/// second).
struct NookRecordSpaceWatch: Sendable {
    enum Verdict: Equatable, Sendable {
        case fine
        case stop
        /// The space could not be read. `isFirst` is true the first time.
        case unreadable(isFirst: Bool)
    }

    private var hasSeenUnreadable = false

    mutating func check(freeBytes: Int64?) -> Verdict {
        guard let freeBytes else {
            defer { hasSeenUnreadable = true }
            return .unreadable(isFirst: !hasSeenUnreadable)
        }
        return freeBytes < NookRecordRules.minimumFreeBytes ? .stop : .fine
    }
}

/// Plain rules for the recorder, kept apart from the stream for tests.
enum NookRecordRules {
    /// Under this much free space a recording stops and keeps what it has.
    static let minimumFreeBytes: Int64 = 1_000_000_000

    /// How long the stream gets to send its first frame before the start is
    /// given up on.
    static let firstFrameDeadline: Duration = .seconds(5)

    /// The video's pixel size: the source scaled down to the quality's
    /// longest side, never up, in even numbers, which H.264 needs.
    static func outputSize(source: CGSize, quality: NookRecordQuality) -> (width: Int, height: Int) {
        let longSide = max(source.width, source.height)
        let scale = quality.maxLongSide.map { min(1, CGFloat($0) / max(longSide, 1)) } ?? 1
        func even(_ value: CGFloat) -> Int {
            let n = Int((value * scale).rounded())
            return max(2, n - n % 2)
        }
        return (even(source.width), even(source.height))
    }

    /// The windows left out of the video. The face cam bubble is never in
    /// `island`, which keeps it in every recording.
    static func excludedWindows(island: [CGWindowID], includeIsland: Bool) -> [CGWindowID] {
        includeIsland ? [] : island
    }

    static func shouldStopForSpace(freeBytes: Int64?) -> Bool {
        guard let freeBytes else { return false }
        return freeBytes < minimumFreeBytes
    }

    /// Free space on the disk that holds `fileURL`. Nil when it cannot be read.
    static func freeBytes(near fileURL: URL) -> Int64? {
        let values = try? fileURL.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// More than this share of the video frames dropped is worth a word.
    static let droppedFramesLimit = 0.05

    /// What the engine reports once the file is closed. With no picture in the
    /// file there is nothing to keep: a person who cancelled sees no failure,
    /// and anything else says why nothing was recorded.
    ///
    /// A file that could not be closed properly, or whose writer failed, is
    /// still a recording when what was written plays (`partialPlays`): it is
    /// kept and goes to the tray like a finished one, and the notice says where
    /// it is. One that does not play is a failure that names the time it
    /// stopped at, and the engine deletes the file.
    static func phaseAfterFinish(
        fileURL: URL, cause: NookRecordStopCause, finishSucceeded: Bool, videoFramesWritten: Int, secondsWritten: Int = 0,
        notes: NookRecordNotes = [], partialPlays: Bool = false
    ) -> NookRecordPhase {
        guard videoFramesWritten > 0 else {
            switch cause {
            case .user: return .idle
            case .lowDisk: return .failed(.lowDisk)
            case .writeError: return .failed(.writerFailed(atSeconds: secondsWritten))
            case .system, .noPicture: return .failed(.noPicture)
            }
        }
        if cause == .writeError || !finishSucceeded {
            return partialPlays
                ? .finished(fileURL, endedBy: .writeError(atSeconds: secondsWritten), notes: notes)
                : .failed(.writerFailed(atSeconds: secondsWritten))
        }
        return .finished(fileURL, endedBy: end(of: cause), notes: notes)
    }

    /// Why a file that holds pictures and closed properly ended. A watchdog
    /// that fired just as the first picture landed is a plain stop.
    static func end(of cause: NookRecordStopCause) -> NookRecordEnd {
        switch cause {
        case .lowDisk: .lowDisk
        case .system: .system
        case .user, .noPicture, .writeError: .user
        }
    }

    /// What to add to the saved notice. Voice that was on and left nothing in
    /// the file, and a share of dropped pictures, are the cases a person cannot
    /// tell from the notch until they play the recording back. Advice to try
    /// Standard goes only to a recording that was made at High.
    static func notes(
        voiceWasOn: Bool, voiceBuffersWritten: Int, videoWritten: Int = 0, videoDropped: Int = 0,
        quality: NookRecordQuality = .standard
    ) -> NookRecordNotes {
        var notes: NookRecordNotes = []
        if voiceWasOn, voiceBuffersWritten == 0 { notes.insert(.noVoice) }
        if droppedFramesAreHigh(written: videoWritten, dropped: videoDropped) {
            notes.insert(.droppedFrames)
            if quality == .high { notes.insert(.suggestStandard) }
        }
        return notes
    }

    /// True when more than 5% of the video frames offered were dropped.
    static func droppedFramesAreHigh(written: Int, dropped: Int) -> Bool {
        let offered = written + dropped
        guard offered > 0 else { return false }
        return Double(dropped) / Double(offered) > droppedFramesLimit
    }

    // MARK: Face cam

    /// A recording of one window never holds the bubble: the bubble is a window of
    /// its own, and a single-window capture holds the one window picked. Full
    /// screen and area recordings show everything on the display, bubble included.
    static func faceCamFits(capture: NookRecordCapture) -> Bool {
        capture != .window
    }

    static func faceCamFits(target: NookRecordTarget) -> Bool {
        target != .pickedWindow
    }

    /// How the Face cam switch looks on the card: lit only when it is wanted and
    /// can work, and out of reach where it cannot.
    static func faceCamSwitch(capture: NookRecordCapture, wanted: Bool) -> (isOn: Bool, isEnabled: Bool, helpKey: String?) {
        guard faceCamFits(capture: capture) else { return (false, false, "nook.record.facecam.windowHelp") }
        return (wanted, true, nil)
    }

    // MARK: Errors

    /// The sentence for an error thrown while starting. The stream's own
    /// errors that have a fix of their own get their own sentence, and the rest
    /// are only "could not start": the raw error goes to the log.
    static func startFailure(domain: String, code: Int) -> NookRecordFailure {
        guard domain == SCStreamErrorDomain else { return .couldNotStart }
        switch code {
        case SCStreamError.userDeclined.rawValue: return .screenPermissionDenied
        case SCStreamError.noDisplayList.rawValue, SCStreamError.noWindowList.rawValue: return .noDisplay
        default: return .couldNotStart
        }
    }

    /// An error's domain and code, and its underlying error's, for the log. It
    /// says nothing a person typed or a path, so it is logged in the open.
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(nsError.domain) \(nsError.code)"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " (\(underlying.domain) \(underlying.code))"
        }
        return text
    }
}
