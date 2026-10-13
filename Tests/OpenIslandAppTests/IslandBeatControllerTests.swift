import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

/// A listener that hears nothing real: it counts its starts and stops and
/// hands on the frames a test gives it.
@MainActor
final class FakeBeatListener: IslandBeatListening {
    /// Fails the moment it is started, as a tap that cannot be built does.
    var refusesToStart = false
    var outputDelay: TimeInterval = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onFrame: (@MainActor (IslandBeatFrame) -> Void)?
    private var onFailure: (@MainActor () -> Void)?

    var isRunning: Bool { onFrame != nil }

    func start(
        onFrame: @escaping @MainActor (IslandBeatFrame) -> Void,
        onFailure: @escaping @MainActor () -> Void
    ) {
        startCount += 1
        if refusesToStart {
            onFailure()
            return
        }
        self.onFrame = onFrame
        self.onFailure = onFailure
    }

    func stop() {
        stopCount += 1
        onFrame = nil
    }

    func send(_ frame: IslandBeatFrame) {
        onFrame?(frame)
    }

    /// A tap that could not be built again after the output changed, or
    /// that was handed a buffer that is not its own.
    func fail() {
        onFailure?()
    }
}

/// Starting and destroying the listener (D56), with a fake in its place.
@MainActor
@Suite struct IslandBeatControllerTests {
    private static let listening = IslandBeatListeningInputs(
        isSwitchOn: true, style: .subtle, followsMusic: true, isMusicPlaying: true,
        policy: .full, islandShowsMusic: true, isIslandClosed: true, isScreenOn: true
    )

    private static func changed(_ change: (inout IslandBeatListeningInputs) -> Void) -> IslandBeatListeningInputs {
        var inputs = listening
        change(&inputs)
        return inputs
    }

    private static let paused = changed { $0.isMusicPlaying = false }
    private static let opened = changed { $0.isIslandClosed = false }

    /// Something the controller asked to run later.
    @MainActor
    private final class Later {
        let wait: TimeInterval
        let block: @MainActor () -> Void
        var isCalledOff = false
        var hasRun = false

        init(wait: TimeInterval, block: @escaping @MainActor () -> Void) {
            self.wait = wait
            self.block = block
        }

        /// What the clock would do when the wait is over.
        func fire() {
            guard !isCalledOff, !hasRun else { return }
            hasRun = true
            block()
        }
    }

    /// A controller that makes fakes, the fakes it made, newest last, and
    /// everything it asked to run later. No test waits for a real clock.
    @MainActor
    private final class Rig {
        let controller = IslandBeatController()
        var made: [FakeBeatListener] = []
        var nextRefuses = false
        var later: [Later] = []
        var received: [IslandBeatFrame] = []

        init() {
            controller.runLater = { [unowned self] wait, block in
                let entry = Later(wait: wait, block: block)
                self.later.append(entry)
                return { entry.isCalledOff = true }
            }
            controller.feed.onFrame = { [unowned self] in self.received.append($0) }
            controller.activate { [unowned self] in
                let listener = FakeBeatListener()
                listener.refusesToStart = self.nextRefuses
                self.made.append(listener)
                return listener
            }
        }

        /// What is still waiting to run after `wait` seconds.
        func pending(_ wait: TimeInterval) -> [Later] {
            later.filter { $0.wait == wait && !$0.isCalledOff && !$0.hasRun }
        }

        var silenceChecks: [Later] { pending(IslandBeatController.silenceLimit) }
        var graceEnds: [Later] { pending(IslandBeatController.grace) }
    }

    /// The listener hands nothing over before real sound: any frame is sound.
    private static let sound = IslandBeatFrame(low: 0.6, mid: 0.2, high: 0.1, hit: .snare)
    /// A quiet moment in a song that has been heard.
    private static let quiet = IslandBeatFrame(low: 0, mid: 0, high: 0, hit: nil)

    // MARK: Starting and destroying

    @Test func theTapStartsWhenTheRuleTurnsTrue() {
        let rig = Rig()

        rig.controller.update(.off)
        #expect(rig.made.isEmpty)
        #expect(!rig.controller.isListening)

        rig.controller.update(Self.listening)
        #expect(rig.made.count == 1)
        #expect(rig.made[0].isRunning)
        #expect(rig.controller.isListening)
        #expect(rig.controller.problem == nil)
    }

    @Test func theSameInputsAgainStartNothingNew() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        rig.controller.update(Self.listening)
        rig.controller.update(Self.changed { $0.style = .vivid })

        #expect(rig.made.count == 1)
        #expect(rig.made[0].startCount == 1)
        #expect(rig.made[0].stopCount == 0)
        #expect(rig.silenceChecks.count == 1)
    }

    @Test func theseDestroyTheTapAtOnceAndItIsBuiltAnewAfter() {
        let stops: [IslandBeatListeningInputs] = [
            .off,
            Self.changed { $0.style = .off },
            Self.changed { $0.followsMusic = false },
            Self.changed { $0.policy = .reduced },
            Self.changed { $0.policy = .conserving },
            Self.changed { $0.isScreenOn = false },
            Self.changed { $0.islandShowsMusic = false },
        ]
        for stop in stops {
            let rig = Rig()
            rig.controller.update(Self.listening)

            rig.controller.update(stop)
            #expect(!rig.controller.isListening)
            #expect(rig.made[0].stopCount == 1)
            #expect(!rig.made[0].isRunning)
            #expect(rig.graceEnds.isEmpty)

            // Not the old one woken up: a new one.
            rig.controller.update(Self.listening)
            #expect(rig.made.count == 2)
            #expect(rig.made[1].isRunning)
            #expect(rig.made[0].startCount == 1)
        }
    }

    @Test func aModelNobodyActivatedNeverListens() {
        let controller = IslandBeatController()

        controller.update(Self.listening)

        #expect(!controller.isListening)
        #expect(!controller.isPulsing)
        #expect(controller.problem == nil)
    }

    @Test func aMacTooOldForTheTapNeverListens() {
        let controller = IslandBeatController()
        controller.activate { nil }

        controller.update(Self.listening)

        #expect(!controller.isListening)
        #expect(controller.problem == nil)
    }

    @Test func aQuitDestroysTheTapAtOnce() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        rig.made[0].send(Self.sound)

        rig.controller.shutDown()

        #expect(!rig.controller.isListening)
        #expect(!rig.controller.isPulsing)
        #expect(rig.made[0].stopCount == 1)
    }

    // MARK: The grace time

    @Test func aPauseKeepsTheTapForTenSecondsAndDrawsNothing() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        rig.made[0].send(Self.sound)
        #expect(rig.controller.isPulsing)

        rig.controller.update(Self.paused)

        // Kept, not destroyed. The glow is the music glow it was.
        #expect(rig.controller.isListening)
        #expect(rig.made[0].stopCount == 0)
        #expect(!rig.controller.isPulsing)
        #expect(rig.graceEnds.count == 1)
        #expect(IslandBeatController.grace == 10)
        // A frame that arrives now moves nothing.
        rig.made[0].send(Self.sound)
        #expect(rig.received == [Self.sound])
    }

    @Test func theSongComingBackInTimeKeepsTheSameTap() {
        for away in [Self.paused, Self.opened] {
            let rig = Rig()
            rig.controller.update(Self.listening)
            rig.made[0].send(Self.sound)
            rig.controller.update(away)
            let end = rig.graceEnds[0]

            rig.controller.update(Self.listening)

            #expect(end.isCalledOff)
            #expect(rig.made.count == 1)
            #expect(rig.made[0].stopCount == 0)
            // It has heard this tap before, and pulses again at once.
            #expect(rig.controller.isPulsing)
            end.fire()
            #expect(rig.controller.isListening)
        }
    }

    @Test func theGraceTimeRunningOutDestroysTheTap() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        rig.controller.update(Self.opened)
        // More of the same changes nothing: one clock, not one a change.
        rig.controller.update(Self.changed { $0.isIslandClosed = false; $0.isMusicPlaying = false })
        #expect(rig.graceEnds.count == 1)

        rig.graceEnds[0].fire()

        #expect(!rig.controller.isListening)
        #expect(rig.made[0].stopCount == 1)
        rig.controller.update(Self.listening)
        #expect(rig.made.count == 2)
    }

    @Test func aLockDuringTheGraceTimeDestroysTheTapAtOnce() {
        for hard in [Self.changed { $0.isScreenOn = false; $0.isMusicPlaying = false }, .off,
                     Self.changed { $0.policy = .reduced; $0.isIslandClosed = false }] {
            let rig = Rig()
            rig.controller.update(Self.listening)
            rig.controller.update(Self.paused)
            let end = rig.graceEnds[0]

            rig.controller.update(hard)

            #expect(!rig.controller.isListening)
            #expect(rig.made[0].stopCount == 1)
            #expect(end.isCalledOff)
        }
    }

    @Test func aPauseWithNoTapRunningStartsNone() {
        let rig = Rig()
        rig.controller.update(Self.paused)
        rig.controller.update(Self.opened)

        #expect(rig.made.isEmpty)
        #expect(rig.graceEnds.isEmpty)
    }

    @Test func aPauseIsNotCountedAsATapThatHearsNothing() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        let check = rig.silenceChecks[0]

        rig.controller.update(Self.paused)

        #expect(check.isCalledOff)
        rig.controller.giveUpIfNothingWasHeard()
        #expect(rig.controller.isListening)
        #expect(rig.controller.problem == nil)
        // Back in time, and the look for silence is set again.
        rig.controller.update(Self.listening)
        #expect(rig.silenceChecks.count == 1)
    }

    // MARK: Frames, and pulsing only after real sound

    @Test func theGlowIsTodaysUntilTheTapHasHeardRealSound() {
        let rig = Rig()
        rig.controller.update(Self.listening)

        // Listening, and not pulsing: macOS may still be asking, and a tap
        // that hears only zeros hands nothing over.
        #expect(rig.controller.isListening)
        #expect(!rig.controller.isPulsing)
        #expect(rig.received.isEmpty)

        // The first frame is the first real sound.
        rig.made[0].send(Self.sound)
        #expect(rig.controller.isPulsing)
        #expect(rig.received == [Self.sound])
        // Silence in a song that has been heard is just a quiet moment.
        rig.made[0].send(Self.quiet)
        #expect(rig.controller.isPulsing)
        #expect(rig.received == [Self.sound, Self.quiet])
    }

    @Test func framesReachTheGlowOnlyWhileTheTapRuns() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        let listener = rig.made[0]
        listener.send(Self.sound)
        #expect(rig.received == [Self.sound])

        rig.controller.update(.off)
        listener.send(Self.sound)
        #expect(rig.received == [Self.sound])
        #expect(!rig.controller.isPulsing)
    }

    @Test func aNewTapMustHearSoundAgainBeforeItPulses() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        rig.made[0].send(Self.sound)
        rig.controller.update(.off)

        rig.controller.update(Self.listening)

        #expect(rig.controller.isListening)
        #expect(!rig.controller.isPulsing)
    }

    // MARK: The speaker's delay

    @Test func aFastSpeakerShowsTheFrameAtOnce() {
        let rig = Rig()
        var waits: [TimeInterval] = []
        rig.controller.showLater = { wait, _ in waits.append(wait) }
        rig.controller.update(Self.listening)
        // The MacBook's own speakers.
        rig.made[0].outputDelay = 0.0129

        rig.made[0].send(Self.sound)

        #expect(rig.received == [Self.sound])
        #expect(waits.isEmpty)
    }

    @Test func aSlowSpeakerHoldsTheFrameForTheDifference() {
        let rig = Rig()
        var held: [(wait: TimeInterval, show: @MainActor () -> Void)] = []
        rig.controller.showLater = { wait, show in held.append((wait, show)) }
        rig.controller.update(Self.listening)
        // A Bluetooth speaker.
        rig.made[0].outputDelay = 0.180

        rig.made[0].send(Self.sound)

        #expect(rig.received.isEmpty)
        #expect(held.count == 1)
        #expect(abs(held[0].wait - (0.180 - IslandBeatTiming.usualPipelineDelay)) < 0.000_001)
        held[0].show()
        #expect(rig.received == [Self.sound])
    }

    @Test func theHoldFollowsTheOutputAsItChanges() {
        let rig = Rig()
        var waits: [TimeInterval] = []
        rig.controller.showLater = { wait, _ in waits.append(wait) }
        rig.controller.update(Self.listening)

        rig.made[0].outputDelay = 3
        rig.made[0].send(Self.sound)
        // The headphones go back in their case.
        rig.made[0].outputDelay = 0.01
        rig.made[0].send(Self.sound)

        #expect(waits == [IslandBeatTiming.longestHold])
        #expect(rig.received == [Self.sound])
    }

    @Test func aHeldFrameIsDroppedWhenTheSongStopsBeforeItsTime() {
        for gone in [Self.paused, .off] {
            let rig = Rig()
            var held: [@MainActor () -> Void] = []
            rig.controller.showLater = { _, show in held.append(show) }
            rig.controller.update(Self.listening)
            rig.made[0].outputDelay = 0.2
            rig.made[0].send(Self.sound)

            rig.controller.update(gone)
            held.forEach { $0() }

            #expect(rig.received.isEmpty)
        }
    }

    // MARK: When macOS says no

    @Test func aTapThatCannotBeBuiltLeavesTodaysGlowAndSaysWhy() {
        let rig = Rig()
        rig.nextRefuses = true

        rig.controller.update(Self.listening)

        #expect(!rig.controller.isListening)
        #expect(!rig.controller.isPulsing)
        #expect(rig.controller.problem == .cannotHear)
        // Whatever it half built is taken down, and nothing waits to run.
        #expect(rig.made[0].stopCount == 1)
        #expect(rig.silenceChecks.isEmpty)
    }

    @Test func aTapThatCannotBeBuiltIsNotTriedAgainUntilTheUserFlipsTheSwitch() {
        let rig = Rig()
        rig.nextRefuses = true
        rig.controller.update(Self.listening)

        // The song goes on, pauses, plays, the island opens and closes.
        rig.controller.update(Self.listening)
        rig.controller.update(Self.paused)
        rig.controller.update(Self.listening)
        rig.controller.update(Self.opened)
        rig.controller.update(Self.listening)
        #expect(rig.made.count == 1)
        #expect(rig.controller.problem == .cannotHear)

        // Off clears the caption, and on is a new try.
        rig.nextRefuses = false
        rig.controller.update(.off)
        #expect(rig.controller.problem == nil)
        rig.controller.update(Self.listening)
        #expect(rig.made.count == 2)
        #expect(rig.controller.isListening)
        #expect(rig.controller.problem == nil)
    }

    @Test func aTapThatFailsWhileItRunsDoesNotStrandThePulse() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        rig.made[0].send(Self.sound)
        #expect(rig.controller.isPulsing)

        // The output changed and the tap could not be built again, or a
        // buffer came that was not its own.
        rig.made[0].fail()

        #expect(!rig.controller.isListening)
        #expect(!rig.controller.isPulsing)
        #expect(rig.controller.problem == .cannotHear)
        #expect(rig.made[0].stopCount == 1)
        rig.controller.update(Self.listening)
        #expect(rig.made.count == 1)
    }

    @Test func aFailureOfATapThatIsAlreadyGoneIsNotHeard() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        let old = rig.made[0]
        rig.controller.update(.off)
        rig.controller.update(Self.listening)

        old.fail()

        #expect(rig.controller.isListening)
        #expect(rig.controller.problem == nil)
    }

    @Test func aTapThatHearsNothingIsGivenUpOnQuietly() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        #expect(rig.silenceChecks.count == 1)
        #expect(IslandBeatController.silenceLimit == 5)

        rig.silenceChecks[0].fire()

        // Gone, and the glow never changed. Nothing is said yet.
        #expect(!rig.controller.isListening)
        #expect(!rig.controller.isPulsing)
        #expect(rig.controller.problem == nil)
        #expect(rig.made[0].stopCount == 1)
        // The same song does not start it again.
        rig.controller.update(Self.listening)
        #expect(rig.made.count == 1)
    }

    @Test func itIsTriedAgainWhenMusicNextStartsThreeTimesInAll() {
        let rig = Rig()
        for attempt in 1...3 {
            rig.controller.update(Self.listening)
            #expect(rig.made.count == attempt)
            #expect(rig.controller.problem == nil)
            rig.silenceChecks[0].fire()
            #expect(!rig.controller.isListening)
            // The caption comes only with the third.
            #expect((rig.controller.problem == .cannotHear) == (attempt == 3))
            rig.controller.update(Self.paused)
        }
        #expect(IslandBeatController.silentTries == 3)

        // After the third no song starts a fourth.
        rig.controller.update(Self.listening)
        rig.controller.update(Self.paused)
        rig.controller.update(Self.listening)
        #expect(rig.made.count == 3)
        #expect(rig.controller.problem == .cannotHear)
    }

    @Test func flippingTheSwitchGivesThreeNewTries() {
        let rig = Rig()
        for _ in 1...3 {
            rig.controller.update(Self.listening)
            rig.silenceChecks[0].fire()
            rig.controller.update(Self.paused)
        }
        #expect(rig.controller.problem == .cannotHear)

        rig.controller.update(.off)
        #expect(rig.controller.problem == nil)
        for attempt in 1...2 {
            rig.controller.update(Self.listening)
            #expect(rig.made.count == 3 + attempt)
            rig.silenceChecks[0].fire()
            #expect(rig.controller.problem == nil)
            rig.controller.update(Self.paused)
        }
    }

    @Test func aSlowAnswerToMacOSIsNotARefusal() {
        // The question stays up for twelve seconds. Two taps give up on
        // silence meanwhile, with nothing said, and the third hears sound.
        let rig = Rig()
        rig.controller.update(Self.listening)
        rig.silenceChecks[0].fire()
        rig.controller.update(Self.paused)
        rig.controller.update(Self.listening)
        rig.silenceChecks[0].fire()
        rig.controller.update(Self.paused)
        #expect(rig.controller.problem == nil)

        rig.controller.update(Self.listening)
        rig.made[2].send(Self.sound)

        #expect(rig.controller.isPulsing)
        #expect(rig.controller.problem == nil)
        #expect(rig.silenceChecks.isEmpty)
        // Hearing sound wipes the count: a later silent tap is a first one.
        rig.controller.update(.off)
        rig.controller.update(Self.listening)
        rig.silenceChecks[0].fire()
        #expect(rig.controller.problem == nil)
    }

    @Test func aTapThatHeardSoundIsKept() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        let check = rig.silenceChecks[0]
        rig.made[0].send(Self.sound)
        rig.made[0].send(Self.quiet)

        // Called off when the sound came, and harmless if it ran anyway.
        #expect(check.isCalledOff)
        rig.controller.giveUpIfNothingWasHeard()

        #expect(rig.controller.isListening)
        #expect(rig.controller.problem == nil)
        #expect(rig.made[0].stopCount == 0)
    }

    @Test func theCheckForSilenceDoesNothingOnceTheTapIsGone() {
        let rig = Rig()
        rig.controller.update(Self.listening)
        let check = rig.silenceChecks[0]
        rig.controller.update(.off)

        #expect(check.isCalledOff)
        rig.controller.giveUpIfNothingWasHeard()

        #expect(rig.controller.problem == nil)
        #expect(rig.made[0].stopCount == 1)
    }

    // MARK: A model of its own

    @Test func aModelOnAStoreOfItsOwnReadsTheSwitchAndNeverListens() {
        let model = AppModel(defaults: MemoryDefaults())
        let nook = model.nook

        #expect(model.beatListeningInputs == .off)
        nook.updateDisplayPreferences(for: model.activeAppearanceProfile) { $0.haloPulsesWithBeat = true }
        let inputs = model.beatListeningInputs
        #expect(inputs.isSwitchOn)
        #expect(inputs.followsMusic)
        #expect(inputs.isIslandClosed)
        // Nothing plays in a test.
        #expect(!inputs.isMusicPlaying)
        #expect(!IslandBeatRules.shouldListen(inputs))

        model.followBeatInputs()
        #expect(!model.beat.isListening)
        #expect(!model.beat.isPulsing)
        #expect(!model.islandHaloInputs.pulsesWithBeat)
    }
}
