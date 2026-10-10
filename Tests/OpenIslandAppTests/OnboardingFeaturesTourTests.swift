import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

// The features page in a tour (D47): the ring follows the walk, the buttons
// reach the doors, and every way out of the page, or out of a widget's step,
// switches off what the tour switched on and leaves alone what the user had
// on before. Nothing here starts a camera or lights a screen: the doors are
// recorders that change a plain state.

@MainActor
struct OnboardingFeaturesTourTests {
    /// The app as the tour sees it: the state it reads, and the doors it
    /// pulled, in order. Each door does to the state what the real one does.
    @MainActor
    private final class World {
        var state = OnboardingState()
        var calls: [String] = []
        var outlines: [NookWidgetKind?] = []
        var holds: [Bool] = []

        init(
            kinds: [NookWidgetKind] = [.mirror, .media, .timer, .tray],
            features: OnboardingFeatureReading = OnboardingFeatureReading()
        ) {
            state.nookPlacements = kinds.map { NookWidgetPlacement(kind: $0, size: .medium) }
            state.enabledWidgets = Set(NookWidgetKind.allCases)
            state.features = features
        }

        var actions: OnboardingActions {
            var actions = OnboardingActions()
            actions.setMirror = { [self] in calls.append("mirror \($0)"); state.features.isMirrorOn = $0 }
            actions.setRingLight = { [self] in calls.append("ring \($0)"); state.features.isRingLightOn = $0 }
            actions.openPhotoBooth = { [self] in calls.append("booth open"); state.features.isBoothShowing = true }
            actions.cancelPhotoBooth = { [self] in
                calls.append("booth cancel")
                state.features.isBoothShowing = false
                state.features.hasBoothStrip = false
            }
            actions.startTimer = { [self] in
                calls.append("timer start")
                state.features.isTimerActive = true
                state.features.timerOneOff = $0
            }
            actions.stopTimer = { [self] in
                calls.append("timer stop")
                state.features.isTimerActive = false
                state.features.timerOneOff = nil
            }
            actions.copySampleLine = { [self] _ in calls.append("copy"); return copySucceeds }
            actions.outlineWidget = { [self] in outlines.append($0) }
            actions.holdIsland = { [self] in holds.append($0) }
            return actions
        }

        var copySucceeds = true

        /// What the user does by hand on the island, which no tour door sees.
        func userTimer(_ isOn: Bool) {
            state.features.isTimerActive = isOn
            state.features.timerOneOff = nil
        }

        /// What the tour switched off, in order.
        var switchedOff: [String] { calls.filter { $0.hasSuffix("false") || $0 == "timer stop" } }
    }

    private static func tour(_ world: World, onEnd: @escaping (OnboardingOutcome) -> Void = { _ in }) -> OnboardingTour {
        OnboardingTour(startingAt: .widgets, state: { world.state }, actions: world.actions, onEnd: onEnd)
    }

    /// A tour on the features page, on the mirror, with the camera and the
    /// ring light switched on by its buttons.
    private static func lit(_ world: World) -> OnboardingTour {
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setMirror(true)
        tour.actions.setRingLight(true)
        return tour
    }

    private func expectBothOff(_ world: World, _ comment: Comment) {
        #expect(!world.state.features.isMirrorOn, comment)
        #expect(!world.state.features.isRingLightOn, comment)
        #expect(world.switchedOff == ["ring false", "mirror false"], comment)
    }

    // MARK: The walk in a tour

    @Test func theFirstWidgetOnThePageIsShownAndRingedWhenThePageComesUp() {
        let world = World()
        let tour = Self.tour(world)
        #expect(tour.state.featureKind == nil, "nothing is picked before the page is up")

        tour.next()

        #expect(tour.page == .features)
        #expect(tour.state.featureKind == .mirror)
        #expect(tour.state.featureWalk.position == 1)
        #expect(world.outlines == [.mirror])
        #expect(world.holds == [true])
    }

    @Test func nextAndPreviousWidgetMoveTheRingAndTheCount() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()

        tour.actions.nextFeature()
        tour.actions.nextFeature()
        #expect(tour.state.featureKind == .timer)
        #expect(tour.state.featureWalk.position == 3 && tour.state.featureWalk.count == 4)

        tour.actions.previousFeature()
        #expect(tour.state.featureKind == .media)
        #expect(world.outlines == [.mirror, .media, .timer, .media])

        tour.actions.previousFeature()
        tour.actions.previousFeature()
        #expect(tour.state.featureKind == .mirror, "the first widget has no previous")
        #expect(world.outlines.count == 5)
    }

    @Test func theToursOwnNextLeavesFromAnyWidget() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()
        tour.actions.nextFeature()

        tour.next()

        #expect(tour.page == .layout)
        #expect(world.outlines.last == .some(nil), "the ring is let go")
        #expect(tour.state.featureKind == nil)
    }

    @Test func nextAndPreviousDoNothingOffThePage() {
        let world = World()
        let tour = Self.tour(world)

        tour.actions.nextFeature()

        #expect(tour.state.featureKind == nil && world.outlines.isEmpty)
    }

    @Test func aWidgetOffThePageIsNotWalked() {
        let world = World(kinds: [.media, .notes])
        let tour = Self.tour(world)
        tour.next()
        #expect(tour.state.featureWalk.kinds == [.media, .notes])
        tour.actions.nextFeature()
        #expect(tour.state.featureKind == .notes)
        tour.actions.nextFeature()
        #expect(tour.state.featureKind == .notes, "the last widget has no next")
    }

    // MARK: The clean-up

    @Test func movingToTheNextWidgetSwitchesOffTheMirrorAndItsLight() {
        let world = World()
        let tour = Self.lit(world)

        tour.actions.nextFeature()

        expectBothOff(world, "leaving the mirror's step")
        #expect(tour.state.featureKind == .media)
    }

    @Test func theToursNextBackAndADotSwitchThemOff() {
        let next = World()
        Self.lit(next).next()
        expectBothOff(next, "Next")

        let back = World()
        Self.lit(back).back()
        expectBothOff(back, "Back")

        let dot = World()
        Self.lit(dot).go(to: .done)
        expectBothOff(dot, "a progress dot")
    }

    @Test func skippingAndFinishingSwitchThemOffOnce() {
        let skipped = World()
        var ended: [OnboardingOutcome] = []
        let skipTour = Self.tour(skipped) { ended.append($0) }
        skipTour.next()
        skipTour.actions.setMirror(true)
        skipTour.actions.setRingLight(true)
        skipTour.skip()
        #expect(ended == [.skipped])
        expectBothOff(skipped, "Skip")

        let finished = World()
        let finishTour = Self.tour(finished) { ended.append($0) }
        finishTour.next()
        finishTour.actions.setMirror(true)
        finishTour.actions.setRingLight(true)
        finishTour.go(to: .done)
        finishTour.next()
        #expect(ended == [.skipped, .finished])
        expectBothOff(finished, "finishing")
    }

    @Test func theWindowClosingSwitchesThemOffBeforeTheSkip() {
        let world = World()
        let tour = Self.lit(world)

        tour.releaseIsland()
        expectBothOff(world, "the window closing")

        tour.skip()
        tour.releaseIsland()
        expectBothOff(world, "and nothing is switched off twice")
    }

    @Test func theUserLeavingTheAppSwitchesThemOffAndTheIslandGoes() {
        let world = World()
        let tour = Self.lit(world)

        tour.setPresence(appIsActive: false, windowIsVisible: true)

        expectBothOff(world, "the hold going off")
        #expect(world.holds.last == false)
    }

    @Test func aTourThatIsDroppedSwitchesThemOff() {
        let world = World()
        var tour: OnboardingTour? = Self.lit(world)
        #expect(world.state.features.isMirrorOn)

        tour = nil

        #expect(tour == nil)
        expectBothOff(world, "the tour being dropped")
    }

    @Test func comingBackToThePageStartsAgainWithTheCameraOff() {
        let world = World()
        let tour = Self.lit(world)
        tour.next()
        tour.back()

        #expect(tour.state.featureKind == .mirror)
        #expect(!world.state.features.isMirrorOn)
        #expect(tour.state.featureProgress.done.isEmpty, "the ticks start over with the page")
    }

    // MARK: What was on before

    @Test func aMirrorAndALightTheUserHadOnBeforeAreLeftAlone() {
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true))
        let tour = Self.tour(world)
        tour.next()

        // Pressing a switch that is already on does not make it the tour's.
        tour.actions.setMirror(true)
        tour.actions.setRingLight(true)
        tour.actions.nextFeature()
        tour.next()
        tour.releaseIsland()

        #expect(world.switchedOff.isEmpty)
        #expect(world.state.features.isMirrorOn && world.state.features.isRingLightOn)
    }

    @Test func aLightTheTourSwitchedOnGoesOffAndAMirrorTheUserHadOnStays() {
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true))
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setRingLight(true)

        tour.next()

        #expect(world.switchedOff == ["ring false"])
        #expect(world.state.features.isMirrorOn)
    }

    @Test func aTimerTheUserHadRunningIsNotStopped() {
        let world = World(kinds: [.timer], features: OnboardingFeatureReading(isTimerActive: true))
        let tour = Self.tour(world)
        tour.next()
        _ = tour.state
        #expect(world.state.features.isUsersTimer)

        // The user's timer keeps running while the tour leaves the page.
        tour.actions.nextFeature()
        tour.next()
        tour.releaseIsland()

        #expect(world.calls.isEmpty, "the tour pulled no door at all")
        #expect(world.switchedOff.isEmpty, "the tour stopped nothing of its own")
        #expect(world.state.features.isTimerActive, "and the user's timer is still running")
    }

    @Test func aTimerTheTourStartedIsStoppedWhenTheStepIsLeft() {
        let world = World(kinds: [.timer, .media])
        let tour = Self.tour(world)
        tour.next()
        tour.actions.startTimer(60)
        _ = tour.state
        #expect(tour.state.featureProgress.done.contains(.timerStart))

        tour.actions.nextFeature()

        #expect(world.calls == ["timer start", "timer stop"])
        #expect(!world.state.features.isTimerActive)
    }

    @Test func theTicksAreReadFromTheAppThroughTheTour() {
        let world = World(features: OnboardingFeatureReading(camera: .allowed))
        let tour = Self.tour(world)
        tour.next()
        #expect(!tour.state.isDone(.mirrorOn))

        tour.actions.setMirror(true)

        #expect(tour.state.isDone(.mirrorOn))
        #expect(!tour.state.isDone(.ringLight))
    }

    @Test func aNoteSavedWhileTheFeaturesPageIsUpTicksTheNotesStep() {
        let world = World(kinds: [.notes])
        world.state.notesSavedCount = 3
        let tour = Self.tour(world)
        tour.next()
        #expect(!tour.state.isDone(.notesLine))

        world.state.notesSavedCount = 4

        #expect(tour.state.isDone(.notesLine))
    }

    // MARK: The photo booth (D49)

    /// Every way out of the mirror's step or the page, each on a fresh tour.
    enum Exit: String, CaseIterable, Sendable {
        case nextWidget, toursNext, back, dot, skip, windowClosing, holdGoingOff

        @MainActor
        func leave(_ tour: OnboardingTour) {
            switch self {
            case .nextWidget: tour.actions.nextFeature()
            case .toursNext: tour.next()
            case .back: tour.back()
            case .dot: tour.go(to: .done)
            case .skip: tour.skip()
            case .windowClosing: tour.releaseIsland()
            case .holdGoingOff: tour.setPresence(appIsActive: false, windowIsVisible: true)
            }
        }
    }

    private static func usersMirror(booth: Bool = false) -> World {
        World(features: OnboardingFeatureReading(
            isMirrorOn: true, camera: .allowed, canStartBooth: true, isBoothShowing: booth
        ))
    }

    @Test(arguments: OnboardingFeaturesTourTests.Exit.allCases)
    func aBoothTheToursButtonStartedIsCancelledOnEveryWayOutAndTheUsersMirrorStays(exit: Exit) {
        let world = Self.usersMirror()
        let tour = Self.tour(world)
        tour.next()
        tour.actions.openPhotoBooth()
        #expect(world.state.features.isBoothShowing)

        exit.leave(tour)

        #expect(world.calls == ["booth open", "booth cancel"], "\(exit)")
        #expect(!world.state.features.isBoothShowing, "\(exit)")
        #expect(world.state.features.isMirrorOn, "the mirror was the user's, and stays on: \(exit)")
    }

    @Test func theBoothIsCancelledBeforeTheRingLightAndTheMirrorGoOff() {
        let world = World(features: OnboardingFeatureReading(camera: .allowed, canStartBooth: true))
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setMirror(true)
        tour.actions.setRingLight(true)
        tour.actions.openPhotoBooth()

        tour.actions.nextFeature()

        #expect(world.calls == ["mirror true", "ring true", "booth open", "booth cancel", "ring false", "mirror false"])
    }

    @Test func aBoothSessionThatWasAlreadyShowingIsTheUsersAndIsLeftAlone() {
        let world = Self.usersMirror(booth: true)
        let tour = Self.tour(world)
        tour.next()

        tour.actions.openPhotoBooth()
        tour.actions.nextFeature()
        tour.next()

        #expect(!world.calls.contains("booth cancel"))
        #expect(world.state.features.isBoothShowing)
    }

    @Test func aBoothSessionThatEndedByItselfIsNotCancelledAgain() {
        let world = Self.usersMirror()
        let tour = Self.tour(world)
        tour.next()
        tour.actions.openPhotoBooth()
        // The user finished the strip on the mirror.
        world.state.features.isBoothShowing = false
        _ = tour.state

        tour.actions.nextFeature()

        #expect(world.calls == ["booth open"])
    }

    // MARK: The timer (D49)

    @Test func aMinuteTheToursStopButtonStoppedDoesNotResetATimerTheUserStartsAfter() {
        let world = World(kinds: [.timer, .media])
        let tour = Self.tour(world)
        tour.next()
        tour.actions.startTimer(60)
        tour.actions.stopTimer()
        #expect(tour.state.isDone(.timerStop))
        world.userTimer(true)

        tour.actions.nextFeature()

        #expect(world.calls == ["timer start", "timer stop"], "the user's timer was not reset")
        #expect(world.state.features.isTimerActive)
    }

    @Test func aMinuteThatRanOutDoesNotResetATimerTheUserStartsAfter() {
        let world = World(kinds: [.timer, .media])
        let tour = Self.tour(world)
        tour.next()
        tour.actions.startTimer(60)
        // The minute ends by itself, and the page draws once.
        world.state.features.isTimerActive = false
        world.state.features.timerOneOff = nil
        _ = tour.state
        world.userTimer(true)

        tour.actions.nextFeature()

        #expect(world.calls == ["timer start"])
        #expect(world.state.features.isTimerActive)
    }

    @Test func aMinuteThatRanOutAndWasNotDrawnStillLeavesTheUsersNextTimerAlone() {
        let world = World(kinds: [.timer, .media])
        let tour = Self.tour(world)
        tour.next()
        tour.actions.startTimer(60)
        world.userTimer(false)
        world.userTimer(true)

        tour.next()

        #expect(world.calls == ["timer start"])
    }

    @Test func aPomodoroTheUserStartsOverTheMinuteIsNotReset() {
        let world = World(kinds: [.timer, .media])
        let tour = Self.tour(world)
        tour.next()
        tour.actions.startTimer(60)
        world.state.features.timerOneOff = nil

        tour.actions.nextFeature()

        #expect(world.calls == ["timer start"])
        #expect(world.state.features.isTimerActive)
    }

    @Test func aMinuteStillRunningWhenTheStepIsLeftIsReset() {
        let world = World(kinds: [.timer, .media])
        let tour = Self.tour(world)
        tour.next()
        tour.actions.startTimer(60)

        tour.actions.nextFeature()

        #expect(world.calls == ["timer start", "timer stop"])
    }

    @Test func theStopButtonTicksWhenItStoppedTheMinuteAndAMinuteThatRanOutDoesNot() {
        let pressed = World(kinds: [.timer])
        let pressedTour = Self.tour(pressed)
        pressedTour.next()
        pressedTour.actions.startTimer(60)
        #expect(!pressedTour.state.isDone(.timerStop))
        pressedTour.actions.stopTimer()
        #expect(pressedTour.state.isDone(.timerStop))

        let ranOut = World(kinds: [.timer])
        let ranOutTour = Self.tour(ranOut)
        ranOutTour.next()
        ranOutTour.actions.startTimer(60)
        _ = ranOutTour.state
        ranOut.state.features.isTimerActive = false
        #expect(ranOutTour.state.isDone(.timerStart))
        #expect(!ranOutTour.state.isDone(.timerStop))
    }

    @Test func theStopButtonStopsNothingWhenTheTimerIsTheUsers() {
        let world = World(kinds: [.timer], features: OnboardingFeatureReading(isTimerActive: true))
        let tour = Self.tour(world)
        tour.next()

        tour.actions.stopTimer()

        #expect(world.calls.isEmpty)
        #expect(world.state.features.isTimerActive)
        #expect(!tour.state.isDone(.timerStop))
    }

    @Test func theTimerStepUnlocksWhenTheUserStopsTheirOwnTimer() {
        let world = World(kinds: [.timer], features: OnboardingFeatureReading(isTimerActive: true))
        let tour = Self.tour(world)
        tour.next()
        var state = tour.state
        #expect(!OnboardingTry.timerStart.button(state.features, progress: state.featureProgress).isEnabled)

        world.userTimer(false)

        state = tour.state
        #expect(OnboardingTry.timerStart.button(state.features, progress: state.featureProgress).isEnabled)
    }

    // MARK: One baseline (D49)

    @Test func aRingLightSettingTheUserHadOnSurvivesTourOffThenTourOn() {
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true))
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setRingLight(false)
        tour.actions.setRingLight(true)
        world.calls.removeAll()

        tour.next()

        #expect(world.calls.isEmpty, "nothing is written over the user's saved setting")
        #expect(world.state.features.isRingLightOn && world.state.features.isMirrorOn)
    }

    @Test func aRingLightSettingTheUserHadOnComesBackAfterTheTourLeftItOff() {
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true))
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setRingLight(false)
        world.calls.removeAll()

        tour.next()

        #expect(world.calls == ["ring true"])
        #expect(world.state.features.isMirrorOn, "and the mirror is not touched")
    }

    @Test func tourOnTourOffTourOnLeavesTheMirrorAndLightAsTheyWereBefore() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()
        for isOn in [true, false, true] {
            tour.actions.setMirror(isOn)
            tour.actions.setRingLight(isOn)
        }

        tour.next()

        #expect(!world.state.features.isMirrorOn && !world.state.features.isRingLightOn)
        #expect(Array(world.calls.suffix(2)) == ["ring false", "mirror false"])
    }

    @Test func aRingLightTheUserTurnedOffAndOnByHandAfterTheTourIsTheirs() {
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true))
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setRingLight(true)
        world.state.features.isRingLightOn = false
        _ = tour.state
        world.state.features.isRingLightOn = true
        _ = tour.state
        world.calls.removeAll()

        tour.next()

        #expect(world.calls.isEmpty, "the tour does not write the setting the user last chose")
        #expect(world.state.features.isRingLightOn)
    }

    @Test func aMirrorTheUserHadOnIsNotSwitchedOffAfterTheTourSwitchedItOffAndOnAgain() {
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true, camera: .allowed))
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setMirror(false)
        tour.actions.setMirror(true)
        world.calls.removeAll()

        tour.next()

        #expect(world.calls.isEmpty)
        #expect(world.state.features.isMirrorOn)
    }

    @Test func leavingNeverSwitchesACameraOn() {
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true, camera: .allowed))
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setMirror(false)
        world.calls.removeAll()

        tour.actions.nextFeature()
        tour.next()

        #expect(world.calls.isEmpty)
        #expect(!world.state.features.isMirrorOn)
    }

    @Test func theBaselineIsTakenWhenThePageComesUpAndNotAtEachPress() {
        // The mirror is on only because the user turned it on before the page.
        let world = World(features: OnboardingFeatureReading(isMirrorOn: true))
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setMirror(true)
        tour.actions.setRingLight(true)

        tour.actions.nextFeature()

        #expect(world.state.features.isMirrorOn)
        #expect(world.switchedOff == ["ring false"])
    }

    // MARK: Losing focus keeps the place (D49)

    @Test func theWalkKeepsItsWidgetWhenFocusIsLostAndRegained() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()
        tour.actions.nextFeature()
        tour.actions.nextFeature()
        #expect(tour.state.featureKind == .timer)

        tour.setPresence(appIsActive: false, windowIsVisible: true)
        #expect(tour.state.featureKind == .timer, "still the timer while another app is in front")
        #expect(world.outlines.last == .some(nil), "the ring is let go with the hold")

        tour.setPresence(appIsActive: true, windowIsVisible: true)
        #expect(tour.state.featureKind == .timer)
        #expect(tour.state.featureWalk.position == 3)
        #expect(world.outlines.last == .some(.timer), "and the ring comes back on the same widget")
        #expect(world.holds == [true, false, true])
    }

    @Test func focusLostStillSwitchesOffWhatTheButtonsSwitchedOnAndKeepsThePlace() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()
        tour.actions.setMirror(true)
        tour.actions.setRingLight(true)

        tour.setPresence(appIsActive: false, windowIsVisible: true)
        tour.setPresence(appIsActive: true, windowIsVisible: true)

        #expect(world.switchedOff == ["ring false", "mirror false"])
        #expect(tour.state.featureKind == .mirror)
    }

    @Test func leavingThePageForgetsThePlaceAndComingBackStartsAtTheFirstWidget() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()
        tour.actions.nextFeature()
        tour.setPresence(appIsActive: false, windowIsVisible: true)

        tour.next()
        #expect(tour.state.featureKind == nil)
        tour.setPresence(appIsActive: true, windowIsVisible: true)
        tour.back()

        #expect(tour.state.featureKind == .mirror)
    }

    @Test func theWindowClosingForgetsThePlace() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()
        tour.actions.nextFeature()

        tour.releaseIsland()

        #expect(tour.state.featureKind == nil)
    }

    @Test func aKeptWidgetThatLeftThePageGivesWayToTheFirstOne() {
        let world = World()
        let tour = Self.tour(world)
        tour.next()
        tour.actions.nextFeature()
        tour.setPresence(appIsActive: false, windowIsVisible: true)
        world.state.nookPlacements = [.tray, .timer].map { NookWidgetPlacement(kind: $0, size: .medium) }

        tour.setPresence(appIsActive: true, windowIsVisible: true)

        #expect(tour.state.featureKind == .tray)
    }

    // MARK: A failed copy (D49)

    @Test func aFailedCopyShowsTheNoteAndAGoodCopyTakesItAway() {
        let world = World(kinds: [.tray], features: OnboardingFeatureReading(isClipboardOn: true))
        let tour = Self.tour(world)
        tour.next()
        world.copySucceeds = false

        _ = tour.actions.copySampleLine("a line")

        var state = tour.state
        #expect(OnboardingTry.trayCopy.button(state.features, progress: state.featureProgress).noteKey == "onboarding.features.copyFailed")

        world.copySucceeds = true
        #expect(tour.actions.copySampleLine("a line"))

        state = tour.state
        #expect(OnboardingTry.trayCopy.button(state.features, progress: state.featureProgress).noteKey == nil)
    }

    @Test func aFailedCopyIsForgottenWhenThePageIsLeft() {
        let world = World(kinds: [.tray])
        world.copySucceeds = false
        let tour = Self.tour(world)
        tour.next()
        _ = tour.actions.copySampleLine("a line")
        #expect(tour.state.featureProgress.copyFailed)

        tour.next()
        tour.back()

        #expect(!tour.state.featureProgress.copyFailed)
    }
}

// MARK: - Drawn pages

@MainActor
struct OnboardingFeaturesRenderTests {
    private static let scale: CGFloat = 2
    private static let snapshotEnvKey = "OPEN_ISLAND_RENDER_SNAPSHOTS"
    /// The window scrolls, and a picture cannot. A taller frame shows the
    /// buttons under a long list of lines.
    private static let tallHeight: CGFloat = 1300

    private static func state(_ kind: NookWidgetKind, kinds: [NookWidgetKind] = NookWidgetKind.allCases) -> OnboardingState {
        var state = OnboardingState()
        state.enabledWidgets = Set(kinds)
        state.nookPlacements = kinds.map { NookWidgetPlacement(kind: $0, size: .medium) }
        state.featureKind = kind
        return state
    }

    @Test(arguments: OnboardingTestSize.narrowWidths)
    func theFeaturesPageDrawsEachWidgetAtBothWidths(width: CGFloat) throws {
        var pictures: [Data] = []
        for kind in NookWidgetKind.allCases {
            pictures.append(try render("07-features-\(kind.rawValue)-\(Int(width))") {
                tourView(Self.state(kind), width: width)
            })
        }
        #expect(Set(pictures).count == NookWidgetKind.allCases.count, "two widgets drew the same page")
    }

    @Test func theMirrorPageDrawsItsStatesAtTheNarrowestWidth() throws {
        let off = Self.state(.mirror)
        var on = off
        on.features = OnboardingFeatureReading(isMirrorOn: true, isRingLightOn: true, camera: .allowed, canStartBooth: true)
        on.featureProgress = progress(on.features)
        var waiting = off
        waiting.features.isMirrorOn = true

        let pictures = [
            try render("07-features-mirror-off-320") { tourView(off, width: 320, height: Self.tallHeight) },
            try render("07-features-mirror-on-320") { tourView(on, width: 320, height: Self.tallHeight) },
            try render("07-features-mirror-waiting-320") { tourView(waiting, width: 320, height: Self.tallHeight) },
        ]
        #expect(Set(pictures).count == 3, "the mirror's three states should each draw differently")
    }

    @Test func theLastWidgetSaysTheOthersCanBeSwitchedOnAndAllOnSaysNothingOfTheSort() throws {
        let few = Self.state(.weather, kinds: [.media, .weather])
        let all = Self.state(.weather)
        let fewPicture = try render("07-features-weather-few-420") { tourView(few, width: 420) }
        let allPicture = try render(nil) { tourView(all, width: 420) }
        #expect(fewPicture != allPicture)
        #expect(few.featureWalk.isAtEnd && all.featureWalk.isAtEnd)
        #expect(few.featureWalk.kinds.count < NookWidgetKind.allCases.count)
    }

    @Test func noWidgetsDrawsTheEmptyPage() throws {
        var none = Self.state(.media, kinds: [])
        none.nookPlacements = []
        _ = try render("07-features-none-320") { tourView(none, width: 320) }
        #expect(none.featureWalk.current == nil)
    }

    @Test func thePageIsTheNarrowWindowsSize() throws {
        let size = try image { tourView(Self.state(.media), width: 320) }
        #expect(size.width == Int(320 * Self.scale))
        #expect(size.height == Int(OnboardingWindowFrame.narrowMaxHeight * Self.scale))
    }

    // MARK: Rendering

    private func progress(_ reading: OnboardingFeatureReading) -> OnboardingFeatureProgress {
        var progress = OnboardingFeatureProgress()
        progress.note(reading)
        return progress
    }

    private func tourView(_ state: OnboardingState, width: CGFloat, height: CGFloat = OnboardingWindowFrame.narrowMaxHeight) -> some View {
        OnboardingView(
            tour: OnboardingTour(startingAt: .features, state: { state }),
            lang: LanguageManager.shared
        )
        .frame(width: width, height: height)
    }

    private func image<Content: View>(@ViewBuilder _ content: () -> Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content().environment(\.nookDrawsStill, true))
        renderer.scale = Self.scale
        return try #require(renderer.cgImage, "ImageRenderer returned no image")
    }

    private func render<Content: View>(_ name: String?, @ViewBuilder _ content: () -> Content) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: try image(content))
        let png = try #require(representation.representation(using: .png, properties: [:]), "PNG encoding failed")
        if let name, ProcessInfo.processInfo.environment[Self.snapshotEnvKey] == "1" {
            let directory = HangoverBrandTests.repoRoot.appendingPathComponent("output/render/onboarding", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return png
    }
}

// MARK: - The tour's mirror door is the link's (D49)

@MainActor
@Suite(.noNewWindows)
struct OnboardingMirrorDoorTests {
    private static func waitingSession() -> AgentSession {
        AgentSession(
            id: "waiting",
            title: "Claude · project",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve command",
            updatedAt: .now,
            permissionRequest: PermissionRequest(title: "Approve", summary: "Allow edit?", affectedPath: "/tmp/file.swift")
        )
    }

    /// The camera is never switched on in these two: both refuse before the
    /// switch is written, which is the point.
    @Test func withAnApprovalInTheOpenListTheToursMirrorButtonLeavesTheMirrorOff() {
        let model = AppModel(defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        model.state = SessionState(sessions: [Self.waitingSession()])
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.nook.pageOverride = .agents
        let tour = model.makeWelcomeTour()

        tour.actions.setMirror(true)

        #expect(!model.nook.isMirrorOn, "the tour used to write the switch with no mirror on screen")
        #expect(model.nook.pageOverride == .agents, "and the approval stays where it is")
    }

    @Test func withTheMirrorTileOffThePageTheToursMirrorButtonLeavesTheMirrorOff() {
        let model = AppModel(defaults: MemoryDefaults())
        model.nook.presentRingLight = { _ in }
        model.nook.setWidget(.mirror, enabled: false)
        model.notchStatus = .opened
        model.notchOpenReason = .click
        let tour = model.makeWelcomeTour()

        tour.actions.setMirror(true)

        #expect(!model.nook.isMirrorOn)
    }
}
