import CoreGraphics
import Foundation

/// What a recording captures (D67).
enum NookRecordCapture: String, CaseIterable, Identifiable, Sendable {
    case fullScreen
    case window
    case area

    var id: String { rawValue }
    var titleKey: String { "nook.record.capture.\(rawValue)" }
}

/// Standard suits quick clips, High suits tutorials.
enum NookRecordQuality: String, CaseIterable, Identifiable, Sendable {
    case standard
    case high

    var id: String { rawValue }
    var titleKey: String { "nook.record.quality.\(rawValue)" }
    /// The video's longest side in pixels. Nil keeps the screen's own size.
    var maxLongSide: Int? { self == .standard ? 1920 : nil }
    var framesPerSecond: Int { self == .standard ? 30 : 60 }
}

/// What the widget page and Settings decide before Record is pressed.
struct NookRecordOptions: Equatable, Sendable {
    var capture: NookRecordCapture = .fullScreen
    var faceCam = false
    var voice = false
    var macSound = true
    var quality: NookRecordQuality = .standard
    /// Settings, Record, "Show the notch in recordings". On by default.
    var includeIsland = true
}

/// What the engine records, already chosen.
enum NookRecordTarget: Equatable, Sendable {
    case display(CGDirectDisplayID)
    /// Part of a display, in the display's points, origin at the top left.
    case area(CGDirectDisplayID, CGRect)
    /// The engine shows Apple's window picker and records what is picked.
    case pickedWindow
}

enum NookRecordFailure: Error, Equatable, Sendable {
    case screenPermissionDenied
    case micPermissionDenied
    case pickerCancelled
    case noDisplay
    case lowDisk
    case writeFailed
    /// The stream was up and no frame came in the first seconds.
    case noPicture
    /// Something else went wrong before the first frame.
    case couldNotStart
    /// The file stopped taking data partway, `atSeconds` into the recording.
    case writerFailed(atSeconds: Int)
    /// No audio device, or none that can be opened.
    case noMicrophone
    /// Apple's window picker reported an error instead of opening.
    case pickerFailed

    /// The sentence the island shows. `writerFailed`'s names the time, so a
    /// caller shows `sentence(_:)`, which fills it in.
    var noticeKey: String {
        switch self {
        case .screenPermissionDenied: "nook.record.failure.screenPermission"
        case .micPermissionDenied: "nook.record.failure.micPermission"
        case .pickerCancelled: "nook.record.failure.pickerCancelled"
        case .noDisplay: "nook.record.failure.noDisplay"
        case .lowDisk: "nook.record.failure.lowDisk"
        case .writeFailed: "nook.record.failure.writeFailed"
        case .noPicture: "nook.record.failure.noPicture"
        case .couldNotStart: "nook.record.failure.couldNotStart"
        case .writerFailed: "nook.record.failure.writerFailed"
        case .noMicrophone: "nook.record.failure.noMicrophone"
        case .pickerFailed: "nook.record.failure.pickerFailed"
        }
    }

    /// The sentence in the language in use, with the time filled in where it
    /// names one ("Recording stopped at 12:40: ...").
    func sentence(_ lang: LanguageManager) -> String {
        switch self {
        case let .writerFailed(atSeconds):
            lang.t(noticeKey, NookRecordClock.text(TimeInterval(atSeconds)))
        default:
            lang.t(noticeKey)
        }
    }
}

/// Why a saved recording ended.
enum NookRecordEnd: Equatable, Sendable {
    /// Stop, the shortcut, a click on the notch, or a quit.
    case user
    /// It stopped itself under 1 GB of free space.
    case lowDisk
    /// macOS ended it: a display was unplugged, the screen locked, or the
    /// person ended the share from the menu bar.
    case system
    /// The file stopped taking data `atSeconds` in. What was written plays, so
    /// it is kept and goes to the tray like any other recording.
    case writeError(atSeconds: Int)
}

/// Things worth saying about a recording that was saved, beyond how it ended.
struct NookRecordNotes: OptionSet, Sendable, Hashable {
    let rawValue: Int

    /// Voice was on and not one voice buffer went into the file.
    static let noVoice = NookRecordNotes(rawValue: 1)
    /// More than 5% of the pictures were dropped.
    static let droppedFrames = NookRecordNotes(rawValue: 2)
    /// Always set together with `droppedFrames`, and only when the recording was
    /// made at High quality: Standard is a step down worth suggesting. A recording
    /// made at Standard has nowhere lower to go.
    static let suggestStandard = NookRecordNotes(rawValue: 4)
}

/// Something went wrong that does not end the recording.
enum NookRecordWarning: Equatable, Sendable {
    /// The microphone session failed or was interrupted: unplugged, or AirPods
    /// disconnected. The picture and the Mac sound go on.
    case voiceLost
    /// The microphone session would not start.
    case voiceDidNotStart

    var noticeKey: String {
        switch self {
        case .voiceLost: "nook.record.warning.voiceLost"
        case .voiceDidNotStart: "nook.record.warning.voiceDidNotStart"
        }
    }
}

/// Where a recording is. The engine moves between idle, recording, paused,
/// saving, finished and failed. The countdown belongs to the model alone.
enum NookRecordPhase: Equatable, Sendable {
    case idle
    case countdown(secondsLeft: Int)
    case recording(startedAt: Date, pausedTotal: TimeInterval)
    case paused(startedAt: Date, pausedAt: Date, pausedTotal: TimeInterval)
    case saving
    /// Saved, why it ended, and anything worth saying about what is in it.
    case finished(URL, endedBy: NookRecordEnd, notes: NookRecordNotes = [])
    case failed(NookRecordFailure)

    func pausing(at now: Date) -> NookRecordPhase {
        guard case let .recording(startedAt, pausedTotal) = self else { return self }
        return .paused(startedAt: startedAt, pausedAt: now, pausedTotal: pausedTotal)
    }

    func resuming(at now: Date) -> NookRecordPhase {
        guard case let .paused(startedAt, pausedAt, pausedTotal) = self else { return self }
        return .recording(startedAt: startedAt, pausedTotal: pausedTotal + max(0, now.timeIntervalSince(pausedAt)))
    }

    /// True from Record to the end of saving: no second start is allowed.
    var isBusy: Bool {
        switch self {
        case .countdown, .recording, .paused, .saving: true
        case .idle, .finished, .failed: false
        }
    }
}

/// The engine behind the Record widget. `NookScreenRecorder` is the real
/// one, tests use a fake. Every call comes from the main actor.
@MainActor
protocol NookRecording: AnyObject {
    /// Called on the main actor each time the phase changes.
    var onPhaseChange: ((NookRecordPhase) -> Void)? { get set }
    /// Called on the main actor when something goes wrong that does not end
    /// the recording, such as the microphone going away.
    var onWarning: ((NookRecordWarning) -> Void)? { get set }
    /// Records to `fileURL`. The phase goes to `.recording`, or to `.failed`
    /// with the reason. `islandWindows` are left out of the video when
    /// `options.includeIsland` is false.
    func start(options: NookRecordOptions, target: NookRecordTarget, fileURL: URL, islandWindows: [CGWindowID]) async
    func pause()
    func resume()
    /// Finishes the file. The phase goes to `.saving`, then `.finished` or
    /// `.failed(.writeFailed)`. Returns once the file is closed.
    func stop() async
}
