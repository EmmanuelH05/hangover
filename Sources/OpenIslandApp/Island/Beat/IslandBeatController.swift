import AppKit
import Foundation
import Observation

/// Hears the Mac's sound and reports what it finds on the main actor (D56).
/// The real one is a Core Audio process tap. A test passes a fake.
@MainActor
protocol IslandBeatListening: AnyObject {
    /// How long after the sound leaves the app it leaves the speaker. It is
    /// read for every frame, because it changes with the output device.
    var outputDelay: TimeInterval { get }
    /// Asks for the tap to be built and started, and comes back at once:
    /// the building waits on Core Audio and is done off the main actor.
    /// Frames arrive once the tap has heard a sample that is not zero: the
    /// first frame means real sound. `onFailure` is called once, if the
    /// tap cannot be built, cannot be built again after the output changed,
    /// or hands over a buffer that is not its own.
    func start(
        onFrame: @escaping @MainActor (IslandBeatFrame) -> Void,
        onFailure: @escaping @MainActor () -> Void
    )
    /// Stops listening and destroys the tap and its device.
    func stop()
}

/// Where frames go: the island's glow layer. A plain object nobody
/// observes, which keeps a level from running any SwiftUI view body.
@MainActor
final class IslandBeatFeed {
    var onFrame: ((IslandBeatFrame) -> Void)?
}

/// Why the glow cannot follow the song.
enum IslandBeatProblem: Equatable, Sendable {
    /// The tap did not start, or it started and heard nothing while music
    /// played. Both are what macOS saying no looks like.
    case cannotHear
}

/// Starts and destroys the listener as the rule says (D56), and passes its
/// frames to the glow.
@MainActor
@Observable
final class IslandBeatController {
    /// How long a tap may hear exact silence while music plays before it is
    /// given up on.
    static let silenceLimit: TimeInterval = 5
    /// How long a tap is kept after the music paused or the island opened.
    static let grace: TimeInterval = 10
    /// How many taps in one run of the app may hear nothing before the
    /// caption says it and no more are tried.
    static let silentTries = 3

    /// True once the tap has heard real sound, and while the rule holds.
    /// The glow reads it to choose the pulse. Until then, which includes
    /// the time macOS takes to be answered, the glow is exactly the music
    /// glow it always was.
    private(set) var isPulsing = false
    /// Set when listening failed, for the caption in Settings.
    private(set) var problem: IslandBeatProblem?
    /// True while a tap exists: being built, running, or kept for the
    /// grace time. Nothing draws from it.
    @ObservationIgnored private(set) var isListening = false

    @ObservationIgnored let feed = IslandBeatFeed()

    /// Shows a frame after a wait, for a speaker that is slower than the
    /// way from the sound to the light. A test swaps it for one that keeps
    /// the frame and the wait.
    @ObservationIgnored var showLater: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { wait, show in
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            MainActor.assumeIsolated { show() }
        }
    }

    /// Runs a block once after a wait and gives back a way to call it off.
    /// The silence check and the end of the grace time go through it. A
    /// test swaps it for one that keeps the block.
    @ObservationIgnored var runLater: (TimeInterval, @escaping @MainActor () -> Void) -> @MainActor () -> Void = { wait, block in
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            block()
        }
        return { task.cancel() }
    }

    /// What a failure waits for before the tap is tried again.
    private enum HoldBack {
        case none
        /// macOS is never asked twice in a row: only the user switching the
        /// pulse off and on tries again.
        case untilSwitchIsFlipped
        /// The tap heard nothing. The next time music starts is a new try.
        case untilMusicStops
    }

    @ObservationIgnored private var makeListener: (@MainActor () -> (any IslandBeatListening)?)?
    @ObservationIgnored private var listener: (any IslandBeatListening)?
    /// Counts the taps. Anything that comes back from an older one is dropped.
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var holdBack = HoldBack.none
    @ObservationIgnored private var hasHeardSound = false
    /// False during the grace time: the tap is kept and nothing is drawn.
    @ObservationIgnored private var ruleHolds = false
    @ObservationIgnored private var silentTaps = 0
    @ObservationIgnored private var cancelSilenceCheck: (@MainActor () -> Void)?
    @ObservationIgnored private var cancelGraceEnd: (@MainActor () -> Void)?
    @ObservationIgnored private var quitWatch: (any NSObjectProtocol)?

    /// Hands over the way to make a listener. Only a real launch calls
    /// this: a test model, a harness run and the demo never listen. A quit
    /// destroys the tap at once.
    func activate(makeListener: @escaping @MainActor () -> (any IslandBeatListening)?) {
        self.makeListener = makeListener
        guard quitWatch == nil else { return }
        quitWatch = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutDown() }
        }
    }

    /// Called whenever one of the rule's inputs changed.
    func update(_ inputs: IslandBeatListeningInputs) {
        if !inputs.isSwitchOn {
            holdBack = .none
            silentTaps = 0
            // Written only when it changes: the caption in Settings watches it.
            if problem != nil { problem = nil }
        } else if holdBack == .untilMusicStops, !inputs.isMusicPlaying {
            holdBack = .none
        }

        switch IslandBeatRules.decision(inputs) {
        case .listen where holdBack == .none:
            cancelGraceEnd?()
            cancelGraceEnd = nil
            setRuleHolds(true)
            if !isListening {
                start()
            } else if !hasHeardSound, cancelSilenceCheck == nil {
                scheduleSilenceCheck()
            }
        case .linger where isListening:
            // Music paused or the island opened. Nothing is drawn, a pause
            // is not counted as a tap that hears nothing, and the tap goes
            // when the grace time is up unless the song is back first.
            setRuleHolds(false)
            cancelSilenceCheck?()
            cancelSilenceCheck = nil
            if cancelGraceEnd == nil {
                cancelGraceEnd = runLater(Self.grace) { [weak self] in
                    self?.cancelGraceEnd = nil
                    self?.stop()
                }
            }
        default:
            stop()
        }
    }

    /// Gives up on a tap that has run for `silenceLimit` and heard nothing.
    /// The glow stayed what it was all along. The next time music starts is
    /// a new try, and after the third tap that hears nothing the caption
    /// says it and no more are tried until the switch is flipped.
    func giveUpIfNothingWasHeard() {
        guard isListening, ruleHolds, !hasHeardSound else { return }
        silentTaps += 1
        if silentTaps >= Self.silentTries {
            fail(holdingBack: .untilSwitchIsFlipped, showsCaption: true)
        } else {
            fail(holdingBack: .untilMusicStops, showsCaption: false)
        }
    }

    /// Destroys the tap at once, whatever the rule says. A quit calls it.
    func shutDown() {
        stop()
    }

    private func start() {
        guard let listener = makeListener?() else { return }
        run += 1
        let run = run
        self.listener = listener
        isListening = true
        hasHeardSound = false
        listener.start(
            onFrame: { [weak self] frame in
                guard let self, self.run == run else { return }
                self.take(frame)
            },
            onFailure: { [weak self] in
                guard let self, self.run == run else { return }
                // The tap could not be built, or not built again: that is
                // said at once, and nothing is tried behind the user's back.
                self.fail(holdingBack: .untilSwitchIsFlipped, showsCaption: true)
            }
        )
        // A listener may fail before `start` comes back.
        if isListening, self.run == run { scheduleSilenceCheck() }
    }

    private func stop() {
        cancelSilenceCheck?()
        cancelSilenceCheck = nil
        cancelGraceEnd?()
        cancelGraceEnd = nil
        run += 1
        listener?.stop()
        listener = nil
        isListening = false
        hasHeardSound = false
        setRuleHolds(false)
    }

    private func fail(holdingBack hold: HoldBack, showsCaption: Bool) {
        stop()
        holdBack = hold
        if showsCaption, problem != .cannotHear { problem = .cannotHear }
    }

    private func setRuleHolds(_ holds: Bool) {
        ruleHolds = holds
        refreshPulsing()
    }

    private func refreshPulsing() {
        let pulses = isListening && hasHeardSound && ruleHolds
        if isPulsing != pulses { isPulsing = pulses }
    }

    private func take(_ frame: IslandBeatFrame) {
        // A frame that was already on its way when the tap was destroyed.
        guard isListening else { return }
        // The listener hands nothing over before real sound.
        if !hasHeardSound {
            hasHeardSound = true
            silentTaps = 0
            cancelSilenceCheck?()
            cancelSilenceCheck = nil
            refreshPulsing()
        }
        // Nothing is drawn before real sound, or during the grace time.
        guard isPulsing else { return }

        // The tap hears the sound before the speaker plays it. On the
        // Mac's own speakers and a cable that is a few milliseconds, less
        // than the light takes, and the frame is shown at once. A Bluetooth
        // speaker is slower, and the frame waits for the difference, which
        // puts the light on the sound the user hears.
        let wait = IslandBeatTiming.hold(outputDelay: listener?.outputDelay ?? 0)
        guard wait > 0 else {
            feed.onFrame?(frame)
            return
        }
        let run = run
        showLater(wait) { [weak self] in
            guard let self, self.run == run, self.isPulsing else { return }
            self.feed.onFrame?(frame)
        }
    }

    /// One look, once, a few seconds after the tap was asked for. A tap
    /// that macOS refuses may still start and deliver nothing but zeros,
    /// and one whose question is not answered yet delivers nothing at all.
    private func scheduleSilenceCheck() {
        cancelSilenceCheck?()
        cancelSilenceCheck = runLater(Self.silenceLimit) { [weak self] in
            self?.cancelSilenceCheck = nil
            self?.giveUpIfNothingWasHeard()
        }
    }
}

/// Whether anybody can see the screen, as plain values (D56).
struct IslandScreenState: Equatable, Sendable {
    enum Event: Equatable, Sendable {
        case willSleep
        case didWake
        case screensDidSleep
        case screensDidWake
        case locked
        case unlocked
        case sessionResigned
        case sessionBecameActive
    }

    var isAsleep = false
    var screensAreAsleep = false
    var isLocked = false
    /// False while another user's session is the one in front.
    var isSessionActive = true

    /// The Mac is awake, its screens are on, it is unlocked and this user's
    /// session is in front.
    var isOn: Bool { !isAsleep && !screensAreAsleep && !isLocked && isSessionActive }

    mutating func note(_ event: Event) {
        switch event {
        case .willSleep: isAsleep = true
        case .didWake: isAsleep = false
        case .screensDidSleep: screensAreAsleep = true
        case .screensDidWake: screensAreAsleep = false
        case .locked: isLocked = true
        case .unlocked: isLocked = false
        case .sessionResigned: isSessionActive = false
        case .sessionBecameActive: isSessionActive = true
        }
    }
}

/// Follows sleep, the screens, the lock and user switching. The beat glow
/// stops listening the moment the screen is not there to be seen.
@MainActor
@Observable
final class IslandScreenPresence {
    static let shared = IslandScreenPresence()

    private(set) var isOn = true

    @ObservationIgnored private var state = IslandScreenState()
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var hasStarted = false

    /// Called once at launch. Calling it again does nothing.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [(Notification.Name, IslandScreenState.Event)] = [
            (NSWorkspace.willSleepNotification, .willSleep),
            (NSWorkspace.didWakeNotification, .didWake),
            (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
            (NSWorkspace.screensDidWakeNotification, .screensDidWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive),
        ]
        for (name, event) in workspaceEvents {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.note(event) }
            })
        }
        let lockEvents: [(String, IslandScreenState.Event)] = [
            ("com.apple.screenIsLocked", .locked),
            ("com.apple.screenIsUnlocked", .unlocked),
        ]
        for (name, event) in lockEvents {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.note(event) }
            })
        }
    }

    func note(_ event: IslandScreenState.Event) {
        state.note(event)
        // Written only when it changes, which is all its observers need.
        if isOn != state.isOn { isOn = state.isOn }
    }
}
