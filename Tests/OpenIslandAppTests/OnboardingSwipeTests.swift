import Foundation
import Observation
import OpenIslandCore
import os
import Testing
@testable import OpenIslandApp

// The swipe on the tour's opening page (D46): a switch that writes the
// setting, and a line that asks for a swipe and answers one.

// MARK: - The line under the choices

struct OnboardingOpeningStepTests {
    @Test(arguments: IslandOpenTrigger.allCases)
    func untilTheIslandWasOpenedTheLineAsksForThatWithTheSwipeOnOrOff(trigger: IslandOpenTrigger) {
        for isSwipeOn in [false, true] {
            let state = OnboardingState(swipeEnabled: isSwipeOn, openTrigger: trigger)
            let step = OnboardingOpeningStep.reading(state)
            #expect(step == .open(trigger))
            #expect(step.isDone == false)
            #expect(step.textKey == "onboarding.opening.try.\(trigger.rawValue)")
        }
    }

    @Test func withTheSwipeOffOpeningTheIslandIsAllThereIsToTry() {
        let open = OnboardingState(isIslandOpen: true)
        let closedAgain = OnboardingState(hasOpenedIsland: true)

        #expect(OnboardingOpeningStep.reading(open) == .opened)
        #expect(OnboardingOpeningStep.reading(closedAgain) == .opened)
        #expect(OnboardingOpeningStep.opened.isDone)
    }

    @Test func withTheSwipeOnAnOpenedIslandAsksForASwipeInTheWordsOfWhereItStands() {
        let open = OnboardingState(swipeEnabled: true, isIslandOpen: true)
        let closedAgain = OnboardingState(swipeEnabled: true, hasOpenedIsland: true)

        #expect(OnboardingOpeningStep.reading(open) == .swipe(isIslandOpen: true))
        #expect(OnboardingOpeningStep.reading(closedAgain) == .swipe(isIslandOpen: false))
        #expect(OnboardingOpeningStep.swipe(isIslandOpen: true).isDone == false)
        #expect(OnboardingOpeningStep.swipe(isIslandOpen: false).isDone == false)
    }

    /// A sideways swipe on the closed island counts too, which is why the
    /// island need not have been opened first.
    @Test func aSwipeTheIslandActedOnAnswersTheLine() {
        let neverOpened = OnboardingState(swipeEnabled: true, hasSwiped: true)
        let opened = OnboardingState(swipeEnabled: true, isIslandOpen: true, hasSwiped: true)

        #expect(OnboardingOpeningStep.reading(neverOpened) == .swiped)
        #expect(OnboardingOpeningStep.reading(opened) == .swiped)
        #expect(OnboardingOpeningStep.swiped.isDone)
    }

    @Test func withTheSwipeSwitchedOffAnEarlierSwipeIsNotSaidBack() {
        let state = OnboardingState(swipeEnabled: false, isIslandOpen: true, hasSwiped: true)

        #expect(OnboardingOpeningStep.reading(state) == .opened)
    }

    @Test func everyStepHasWordsOfItsOwn() {
        let steps: [OnboardingOpeningStep] = [
            .open(.hover), .open(.click), .opened,
            .swipe(isIslandOpen: true), .swipe(isIslandOpen: false), .swiped,
        ]

        #expect(Set(steps.map(\.textKey)).count == steps.count)
    }
}

// MARK: - The tour

/// A state a test changes under a tour, the way the app does.
@MainActor
private final class OnboardingStateBox {
    var state: OnboardingState

    init(_ state: OnboardingState) { self.state = state }
}

@MainActor
struct OnboardingSwipeTourTests {
    @Test func theSwipeSwitchReachesTheAppWithWhatItWasGiven() {
        let counter = OnboardingCallCounter()
        let tour = OnboardingTour(state: { OnboardingState() }, actions: counter.actions)

        tour.actions.setSwipeEnabled(true)
        tour.actions.setSwipeEnabled(false)

        #expect(counter.swipeSwitches == [true, false])
        #expect(counter.order == ["swipe", "swipe"])
    }

    /// Swipes from before the tour came up are not the tour's: only the
    /// count growing while it is up says the user tried it.
    @Test func aSwipeTheIslandActedOnWhileTheTourIsUpIsKept() {
        let box = OnboardingStateBox(OnboardingState(swipeEnabled: true, swipeCount: 3))
        let tour = OnboardingTour(startingAt: .opening, state: { box.state })
        #expect(tour.state.hasSwiped == false)

        box.state.swipeCount = 4
        #expect(tour.state.hasSwiped)

        // Another page and back: the answer stays.
        tour.next()
        tour.back()
        #expect(tour.page == .opening)
        #expect(tour.state.hasSwiped)
    }

    @Test func aStateHandedInAsSwipedIsKeptAsItIs() {
        let tour = OnboardingTour(state: { OnboardingState(hasSwiped: true) })

        #expect(tour.state.hasSwiped)
    }
}

// MARK: - The app

@MainActor
@Suite(.noNewWindows)
struct OnboardingSwipeModelTests {
    /// A model on a store held in memory, which reads and writes no real
    /// setting and puts nothing on screen.
    private static func model(defaults: UserDefaults = MemoryDefaults()) -> AppModel {
        AppModel(isNotificationSessionAlreadyFrontmost: { _ in true }, defaults: defaults)
    }

    private static func waitingSession() -> AgentSession {
        var session = AgentSession(
            id: "waiting",
            title: "Claude · project",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve",
            updatedAt: .now,
            permissionRequest: PermissionRequest(title: "Edit", summary: "x", affectedPath: "/tmp/x")
        )
        session.isProcessAlive = true
        return session
    }

    @Test func everySwipeTheIslandActsOnIsCountedAndAGestureItLetPassIsNot() {
        let model = Self.model()
        #expect(model.swipeActionCount == 0)

        model.noteSwipe(.none)
        #expect(model.swipeActionCount == 0)

        model.noteSwipe(.close)
        model.noteSwipe(.toggleClosedContent)
        model.noteSwipe(.closeAndToggleClosedContent)
        #expect(model.swipeActionCount == 3)
    }

    /// While an agent waits a sideways swipe on the closed island changes
    /// nothing, and the tour is not told one was made.
    @Test func aSidewaysSwipeWhileAnAgentWaitsIsNotCounted() {
        let model = Self.model()
        model.state = SessionState(sessions: [Self.waitingSession()])
        #expect(model.islandClosedMode == .waiting)

        model.noteSwipe(.toggleClosedContent)
        #expect(model.swipeActionCount == 0)

        // A swipe that closes the island did something either way.
        model.noteSwipe(.close)
        model.noteSwipe(.closeAndToggleClosedContent)
        #expect(model.swipeActionCount == 2)
    }

    @Test func thePagesAreToldTheSwipeSettingAndTheCount() {
        let model = Self.model()
        #expect(model.onboardingState.swipeEnabled == false)
        #expect(model.onboardingState.swipeCount == 0)

        model.swipeGesturesEnabled = true
        model.noteSwipe(.close)

        #expect(model.onboardingState.swipeEnabled)
        #expect(model.onboardingState.swipeCount == 1)
    }

    /// The opening page's switch writes the preference Settings writes, to
    /// the store the model was given, and the line under it follows.
    @Test func theToursSwitchWritesTheSwipeSettingAndASwipeAnswersItsLine() {
        let defaults = MemoryDefaults()
        let model = Self.model(defaults: defaults)
        let tour = model.makeWelcomeTour(startingAt: .opening)
        #expect(tour.page == .opening)
        #expect(OnboardingOpeningStep.reading(tour.state) == .open(model.islandOpenTrigger))

        tour.actions.setSwipeEnabled(true)

        #expect(model.swipeGesturesEnabled)
        #expect(defaults.object(forKey: IslandSwipeSetting.defaultsKey) as? Bool == true)
        #expect(tour.state.swipeEnabled)
        #expect(tour.state.hasSwiped == false)

        model.noteSwipe(.close)
        #expect(OnboardingOpeningStep.reading(tour.state) == .swiped)

        tour.actions.setSwipeEnabled(false)
        #expect(model.swipeGesturesEnabled == false)
        #expect(defaults.object(forKey: IslandSwipeSetting.defaultsKey) as? Bool == false)
    }

    /// The controller is where a swipe is acted on: a sideways swipe on the
    /// closed pill hides what it shows and is counted, and with the setting
    /// off the same fingers do nothing.
    @Test func aSwipeOnTheClosedPillIsActedOnAndCountedOnlyWhileTheSettingIsOn() {
        let model = Self.model()
        let controller = OverlayPanelController()
        controller.model = model

        Self.swipeSideways(on: controller)
        #expect(model.swipeActionCount == 0)
        #expect(model.nook.closedContentHiddenBySwipe == false)

        model.swipeGesturesEnabled = true
        Self.swipeSideways(on: controller)
        #expect(model.swipeActionCount == 1)
        #expect(model.nook.closedContentHiddenBySwipe)
    }

    /// One sideways gesture at the pill, which a controller that was never
    /// placed on a screen has at the origin.
    private static func swipeSideways(on controller: OverlayPanelController) {
        let far = IslandSwipeRecognizer.threshold + 4
        var samples = [IslandScrollSample(dx: 0, dy: 0, phase: .began, isMomentum: false, timestamp: 0)]
        samples += (1...4).map {
            IslandScrollSample(dx: far / 4, dy: 0, phase: .changed, isMomentum: false, timestamp: Double($0) * 0.01)
        }
        samples.append(IslandScrollSample(dx: 0, dy: 0, phase: .ended, isMomentum: false, timestamp: 0.05))
        for sample in samples {
            _ = controller.handleScroll(
                sample, screenLocation: .zero, windowLocation: .zero, windowNumber: 0, isLocalEvent: true
            )
        }
    }

    /// The live page ticks because the count is observed: a draw that read
    /// the tour's state is told when the island acts on a swipe.
    @Test func aDrawThatReadTheToursStateIsToldWhenTheIslandActsOnASwipe() {
        let model = Self.model()
        let tour = model.makeWelcomeTour(startingAt: .opening)
        let wasTold = OSAllocatedUnfairLock(initialState: false)

        withObservationTracking {
            _ = tour.state
        } onChange: {
            wasTold.withLock { $0 = true }
        }
        model.noteSwipe(.close)

        #expect(wasTold.withLock { $0 })
    }

    /// A sideways swipe tried on the opening page hides what the closed
    /// island shows. A pick on the page after it brings that back, which
    /// lets the real island show the pick.
    @Test func aPickOfWhatTheClosedIslandShowsBringsBackWhatASwipeHid() {
        let model = Self.model()
        let tour = model.makeWelcomeTour(startingAt: .closed)

        model.nook.closedContentHiddenBySwipe = true
        tour.actions.setClosedSide(.date)
        #expect(model.nook.closedContentHiddenBySwipe == false)

        model.nook.closedContentHiddenBySwipe = true
        tour.actions.setClosedLeft(.nothing)
        #expect(model.nook.closedContentHiddenBySwipe == false)

        model.nook.closedContentHiddenBySwipe = true
        tour.actions.setClosedMusic(.style(.artOnly))
        #expect(model.nook.closedContentHiddenBySwipe == false)
    }
}
