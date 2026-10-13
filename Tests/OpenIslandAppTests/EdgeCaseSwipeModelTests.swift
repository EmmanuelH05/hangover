import AppKit
import Foundation
import Observation
import OpenIslandCore
import Testing
@testable import OpenIslandApp

// The swipe as the running app wires it: the panel controller reads the
// scroll events, the app model counts and hides, and the welcome tour reads
// the count. These drive `OverlayPanelController.handleScroll` and the model
// with whole gestures, the way a trackpad would, and never start a monitor.

// MARK: - Helpers

/// Builds the samples of a gesture and sends them to a controller.
@MainActor
private enum EdgeSwipeDriver {
    static let far = IslandSwipeRecognizer.threshold + 4

    /// A trackpad gesture: a zero begin, `steps` equal changes, a zero end.
    static func gesture(
        dx: Double = 0,
        dy: Double = 0,
        steps: Int = 4,
        startingAt start: TimeInterval = 0,
        ends: Bool = true
    ) -> [IslandScrollSample] {
        var samples = [IslandScrollSample(dx: 0, dy: 0, phase: .began, isMomentum: false, timestamp: start)]
        for step in 1...steps {
            samples.append(IslandScrollSample(
                dx: dx / Double(steps), dy: dy / Double(steps),
                phase: .changed, isMomentum: false, timestamp: start + Double(step) * 0.01
            ))
        }
        if ends {
            samples.append(IslandScrollSample(
                dx: 0, dy: 0, phase: .ended, isMomentum: false, timestamp: start + Double(steps + 1) * 0.01
            ))
        }
        return samples
    }

    /// What each sample's `handleScroll` answered: whether to swallow it.
    @discardableResult
    static func send(
        _ samples: [IslandScrollSample],
        to controller: OverlayPanelController,
        at point: NSPoint = .zero,
        isLocal: Bool = true
    ) -> [Bool] {
        samples.map {
            controller.handleScroll(
                $0, screenLocation: point, windowLocation: .zero, windowNumber: 0, isLocalEvent: isLocal
            )
        }
    }

    static func model(defaults: UserDefaults = MemoryDefaults()) -> AppModel {
        AppModel(isNotificationSessionAlreadyFrontmost: { _ in true }, defaults: defaults)
    }

    /// A controller that was never placed on a screen, which has its pill at
    /// the origin. Fine for the closed island.
    static func bareController(for model: AppModel) -> OverlayPanelController {
        let controller = OverlayPanelController()
        controller.model = model
        return controller
    }

    static func waitingSession() -> AgentSession {
        var session = AgentSession(
            id: "waiting", title: "Claude · project", tool: .claudeCode,
            attachmentState: .attached, phase: .waitingForApproval, summary: "Approve",
            updatedAt: .now,
            permissionRequest: PermissionRequest(title: "Edit", summary: "x", affectedPath: "/tmp/x")
        )
        session.isProcessAlive = true
        return session
    }

    static func runningSession() -> AgentSession {
        var session = AgentSession(
            id: "running", title: "Claude · project", tool: .claudeCode, origin: .live,
            attachmentState: .attached, phase: .running, summary: "Working", updatedAt: .now
        )
        session.isProcessAlive = true
        return session
    }
}

// MARK: - Counting and hiding on the closed island

@MainActor
@Suite(.noNewWindows)
struct EdgeCaseSwipeCountTests {
    @Test func oneVeryLongGestureIsOneSwipeAndOneCount() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let controller = EdgeSwipeDriver.bareController(for: model)

        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dx: 6_000, steps: 300), to: controller)

        #expect(model.swipeActionCount == 1)
        #expect(model.nook.closedContentHiddenBySwipe)
    }

    @Test func manySeparateSwipesAreEachCountedOnceAndTheHiddenStateFollowsTheirParity() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let controller = EdgeSwipeDriver.bareController(for: model)

        for index in 1...41 {
            // Alternate the direction too: both hide and show.
            let dx = index.isMultiple(of: 2) ? -EdgeSwipeDriver.far : EdgeSwipeDriver.far
            EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dx: dx, startingAt: Double(index)), to: controller)
            #expect(model.swipeActionCount == index)
            #expect(model.nook.closedContentHiddenBySwipe == !index.isMultiple(of: 2), "after swipe \(index)")
        }
    }

    @Test func aSwipeThatWasTooShortIsNotCountedAndDoesNotHide() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let controller = EdgeSwipeDriver.bareController(for: model)

        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dx: IslandSwipeRecognizer.threshold - 1), to: controller)
        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: EdgeSwipeDriver.far, startingAt: 1), to: controller)

        #expect(model.swipeActionCount == 0, "a vertical swipe on the closed pill is nothing")
        #expect(model.nook.closedContentHiddenBySwipe == false)
    }

    // MARK: A wheel

    private static func notch(lines: Double, at time: TimeInterval) -> IslandScrollSample {
        IslandScrollSample(
            dx: lines * IslandScrollSample.pointsPerWheelLine, dy: 0, phase: .none, isMomentum: false, timestamp: time
        )
    }

    @Test func aWheelRolledSteadilyIsOneSwipeHoweverManyNotchesComeInAGestureThatDoesNotPause() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let controller = EdgeSwipeDriver.bareController(for: model)

        let gap = IslandSwipeRecognizer.wheelGap
        let samples = (0..<40).map { Self.notch(lines: 1, at: Double($0) * (gap - 0.05)) }
        EdgeSwipeDriver.send(samples, to: controller)

        #expect(model.swipeActionCount == 1)
    }

    @Test func eachNotchOfAWheelThatPausesBetweenThemIsItsOwnGestureAndOneNotchIsTooShort() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let controller = EdgeSwipeDriver.bareController(for: model)

        let gap = IslandSwipeRecognizer.wheelGap
        EdgeSwipeDriver.send((0..<10).map { Self.notch(lines: 1, at: Double($0) * (gap + 0.05)) }, to: controller)
        #expect(model.swipeActionCount == 0, "one line is 12 points")

        // Three lines at once is 36 points, enough alone, and each is a swipe.
        EdgeSwipeDriver.send((0..<5).map { Self.notch(lines: 3, at: 100 + Double($0) * (gap + 0.05)) }, to: controller)
        #expect(model.swipeActionCount == 5)
    }

    // MARK: The setting changes under a gesture

    @Test func theSettingSwitchedOffInTheMiddleOfAGestureStopsItDeadAndLeavesNothingHidden() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let controller = EdgeSwipeDriver.bareController(for: model)
        let gesture = EdgeSwipeDriver.gesture(dx: 200, steps: 20)

        EdgeSwipeDriver.send(Array(gesture[0..<3]), to: controller)
        model.swipeGesturesEnabled = false
        let rest = EdgeSwipeDriver.send(Array(gesture[3...]), to: controller)

        #expect(model.swipeActionCount == 0)
        #expect(model.nook.closedContentHiddenBySwipe == false)
        #expect(rest.allSatisfy { !$0 }, "nothing is swallowed while the swipe is off")
    }

    @Test func theSettingSwitchedOffRightAfterASwipeBringsTheContentBackAndFreesTheRest() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let controller = EdgeSwipeDriver.bareController(for: model)
        let gesture = EdgeSwipeDriver.gesture(dx: 200, steps: 20)

        EdgeSwipeDriver.send(Array(gesture[0..<5]), to: controller)
        #expect(model.nook.closedContentHiddenBySwipe)
        model.swipeGesturesEnabled = false
        #expect(model.nook.closedContentHiddenBySwipe == false)

        let rest = EdgeSwipeDriver.send(Array(gesture[5...]), to: controller)
        #expect(rest.allSatisfy { !$0 })
        #expect(model.nook.closedContentHiddenBySwipe == false, "the rest of the gesture hides nothing")
        #expect(model.swipeActionCount == 1, "the count is of what was done, and it was done")
    }

    /// The begin was missed while the setting was off. The rest of that
    /// gesture belongs to nobody.
    @Test func theSettingSwitchedOnInTheMiddleOfAGestureDoesNotJoinIt() {
        let model = EdgeSwipeDriver.model()
        let controller = EdgeSwipeDriver.bareController(for: model)
        let gesture = EdgeSwipeDriver.gesture(dx: 400, steps: 10)

        EdgeSwipeDriver.send(Array(gesture[0..<4]), to: controller)
        model.swipeGesturesEnabled = true
        EdgeSwipeDriver.send(Array(gesture[4...]), to: controller)
        #expect(model.swipeActionCount == 0)

        // The next whole gesture works.
        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dx: EdgeSwipeDriver.far, startingAt: 5), to: controller)
        #expect(model.swipeActionCount == 1)
    }

    @Test func fiveWholeGesturesWhileTheSettingIsOffCountForNothing() {
        let model = EdgeSwipeDriver.model()
        let controller = EdgeSwipeDriver.bareController(for: model)

        for index in 0..<5 {
            EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dx: 100, startingAt: Double(index)), to: controller)
        }

        #expect(model.swipeActionCount == 0)
        #expect(model.nook.closedContentHiddenBySwipe == false)
    }

    // MARK: An agent waits

    @Test func aSidewaysSwipeWhileAnAgentWaitsChangesNothingAndIsNotCountedUntilTheWaitEnds() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        model.state = SessionState(sessions: [EdgeSwipeDriver.waitingSession()])
        let controller = EdgeSwipeDriver.bareController(for: model)

        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dx: EdgeSwipeDriver.far), to: controller)
        #expect(model.swipeActionCount == 0)
        #expect(model.nook.closedContentHiddenBySwipe == false)
        #expect(model.islandClosedPillMode == .waiting)

        // The wait ends. Nothing was armed, and the next swipe works.
        model.state = SessionState(sessions: [EdgeSwipeDriver.runningSession()])
        #expect(model.islandClosedPillMode == .running)
        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dx: EdgeSwipeDriver.far, startingAt: 2), to: controller)
        #expect(model.swipeActionCount == 1)
        #expect(model.islandClosedPillMode == .idle)
    }

    @Test func anAgentThatStartsWaitingInTheMiddleOfAHidingGestureLeavesTheIslandShowingIt() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        model.state = SessionState(sessions: [EdgeSwipeDriver.runningSession()])
        let controller = EdgeSwipeDriver.bareController(for: model)
        let gesture = EdgeSwipeDriver.gesture(dx: 200, steps: 20)

        EdgeSwipeDriver.send(Array(gesture[0..<3]), to: controller)
        model.state = SessionState(sessions: [EdgeSwipeDriver.waitingSession()])
        EdgeSwipeDriver.send(Array(gesture[3...]), to: controller)

        #expect(model.swipeActionCount == 0, "it fired while the agent waited")
        #expect(model.closedContentIsHidden == false)
        model.state = SessionState(sessions: [EdgeSwipeDriver.runningSession()])
        #expect(model.closedContentIsHidden == false, "no hide was armed for when the wait ends")
    }

    // MARK: The count itself

    @Test func tenThousandSwipesAreTenThousandCountsAndNothingElseIs() {
        let model = EdgeSwipeDriver.model()
        for _ in 0..<10_000 {
            model.noteSwipe(.close)
            model.noteSwipe(.none)
        }
        for _ in 0..<5 { model.noteSwipe(.toggleClosedContent) }
        #expect(model.swipeActionCount == 10_005)
    }
}

// MARK: - The tour reads the count

@MainActor
@Suite(.noNewWindows)
struct EdgeCaseSwipeTourTests {
    /// A state a test changes under a tour.
    private final class Box {
        var state: OnboardingState
        init(_ state: OnboardingState) { self.state = state }
    }

    @Test func aTourCreatedAfterSwipesDoesNotTakeThemForItsOwn() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        for _ in 0..<3 { model.noteSwipe(.close) }

        let tour = model.makeWelcomeTour(startingAt: .opening)
        #expect(tour.state.swipeCount == 3)
        #expect(tour.state.hasSwiped == false)
        #expect(OnboardingOpeningStep.reading(tour.state) == .open(model.islandOpenTrigger))

        model.noteSwipe(.toggleClosedContent)
        #expect(tour.state.hasSwiped)
        #expect(OnboardingOpeningStep.reading(tour.state) == .swiped)
    }

    @Test func twoToursEachKeepTheirOwnBaseline() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let first = model.makeWelcomeTour(startingAt: .opening)
        model.noteSwipe(.close)
        let second = model.makeWelcomeTour(startingAt: .opening)

        #expect(first.state.hasSwiped, "the first tour was up for that swipe")
        #expect(second.state.hasSwiped == false, "the second came up after it")

        model.noteSwipe(.close)
        #expect(second.state.hasSwiped)
    }

    @Test func aTourThatIsLeftAndComesBackToTheOpeningPageStillHasItsAnswer() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let tour = model.makeWelcomeTour(startingAt: .welcome)
        tour.answerQuestion()
        model.noteSwipe(.close)

        var guardCount = 0
        while tour.page != .opening, guardCount < 20 {
            tour.next()
            guardCount += 1
        }
        #expect(tour.page == .opening)
        #expect(OnboardingOpeningStep.reading(tour.state) == .swiped)
    }

    @Test func switchingTheSwipeOffAndOnAgainKeepsTheAnswerThatWasGiven() {
        let model = EdgeSwipeDriver.model()
        model.swipeGesturesEnabled = true
        let tour = model.makeWelcomeTour(startingAt: .opening)
        model.noteSwipe(.close)
        #expect(OnboardingOpeningStep.reading(tour.state) == .swiped)

        tour.actions.setSwipeEnabled(false)
        #expect(OnboardingOpeningStep.reading(tour.state) == .open(model.islandOpenTrigger))

        tour.actions.setSwipeEnabled(true)
        #expect(OnboardingOpeningStep.reading(tour.state) == .swiped)
    }

    @Test func aSwipeBeforeTheTourWasUpAndNoneAfterNeverTicksItsPage() {
        let box = Box(OnboardingState(swipeEnabled: true, swipeCount: 40))
        let tour = OnboardingTour(startingAt: .opening, state: { box.state })

        box.state.swipeCount = 40
        #expect(tour.state.hasSwiped == false)
        box.state.swipeCount = 41
        #expect(tour.state.hasSwiped)
    }

    /// The count only ever goes up in the app. A state source that reports a
    /// lower number later (a model that was replaced) takes the tick away,
    /// where the sibling answer for opening the island stays once given.
    @Test func aCountThatGoesDownDoesNotTakeAnAnswerBack() {
        let box = Box(OnboardingState(swipeEnabled: true, swipeCount: 5))
        let tour = OnboardingTour(startingAt: .opening, state: { box.state })
        box.state.swipeCount = 7
        #expect(tour.state.hasSwiped)

        box.state.swipeCount = 2
        let stillSwiped = tour.state.hasSwiped
        #expect(stillSwiped)
    }

    @Test func anIslandOpenedOnceStaysOpenedForTheTourWhateverTheStateSaysAfterwards() {
        let box = Box(OnboardingState(isIslandOpen: true))
        let tour = OnboardingTour(startingAt: .opening, state: { box.state })
        #expect(tour.state.hasOpenedIsland)

        box.state.isIslandOpen = false
        #expect(tour.state.hasOpenedIsland, "the pattern the swipe's answer is compared with")
    }

    @Test func aTourWhoseModelIsGoneReadsAPlainStateAndDoesNotCrash() {
        var model: AppModel? = EdgeSwipeDriver.model()
        model?.swipeGesturesEnabled = true
        let tour = model!.makeWelcomeTour(startingAt: .opening)
        model?.noteSwipe(.close)
        #expect(tour.state.hasSwiped)

        model = nil
        #expect(tour.state.swipeCount == 0)
        #expect(tour.state.swipeEnabled == false)
    }
}

// MARK: - The panel controller with a real panel

@MainActor
@Suite(.serialized, .noNewWindows)
struct EdgeCaseSwipeControllerTests {
    private static let far = NSPoint(x: -10_000, y: -10_000)
    /// Comfortably past `AppModel.hoverOpenDelay`.
    private static let hoverWait: Duration = .milliseconds(500)

    private func modelWithPanel() -> (AppModel, OverlayPanelController) {
        let model = AppModel(defaults: MemoryDefaults())
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.overlay.pointerLocationProvider = { Self.far }
        model.overlay.ensureOverlayPanel()
        model.swipeGesturesEnabled = true
        return (model, model.overlay.overlayPanelController)
    }

    private func pill(_ controller: OverlayPanelController) -> NSPoint {
        NSPoint(x: controller.notchRect.midX, y: controller.notchRect.midY)
    }

    private func content(_ model: AppModel, _ controller: OverlayPanelController) throws -> NSPoint {
        let frame = try #require(controller.windowFrame)
        return NSPoint(x: frame.midX, y: frame.maxY - model.islandOpenedLayout.shapeHeight + 12)
    }

    // MARK: Up on the open island

    @Test func aSwipeUpOnTheOpenIslandClosesItSwallowsTheRestAndKeepsHoverFromReopeningIt() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)
        let point = try content(model, controller)

        let answers = EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: EdgeSwipeDriver.far), to: controller, at: point)

        #expect(model.notchStatus == .closed)
        #expect(model.swipeActionCount == 1)
        #expect(controller.isHoverSuppressedUntilExit)
        #expect(answers.last == true, "the end of the gesture is swallowed too")

        // The pointer rests on the pill. It must not open again.
        controller.handleMouseMoved(pill(controller))
        try await Task.sleep(for: Self.hoverWait)
        #expect(model.notchStatus == .closed)

        controller.handleMouseMoved(Self.far)
        #expect(controller.isHoverSuppressedUntilExit == false)
    }

    @Test func aSwipeOnTheOpenIslandIsRefusedWhileTheTourHoldsItAndNothingIsSwallowed() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.setTourHoldsIslandOpen(true)
        #expect(model.notchStatus == .opened)
        let point = try content(model, controller)

        let up = EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: EdgeSwipeDriver.far), to: controller, at: point)
        let sideways = EdgeSwipeDriver.send(
            EdgeSwipeDriver.gesture(dx: EdgeSwipeDriver.far, startingAt: 2), to: controller, at: pill(controller)
        )

        #expect(model.notchStatus == .opened)
        #expect(model.swipeActionCount == 0)
        #expect(up.allSatisfy { !$0 } && sideways.allSatisfy { !$0 })
        #expect(model.nook.closedContentHiddenBySwipe == false)
        model.setTourHoldsIslandOpen(false)
    }

    @Test func aSwipeUpIsRefusedWhileAnAgentWaitsAndTheIslandKeepsItselfOpenForIt() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.keepNotchOpenUntilDecision = true
        model.state = SessionState(sessions: [EdgeSwipeDriver.waitingSession()])
        model.notchOpen(reason: .click)
        let point = try content(model, controller)

        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: EdgeSwipeDriver.far), to: controller, at: point)
        #expect(model.notchStatus == .opened)
        #expect(model.swipeActionCount == 0)

        // With the setting off for waiting sessions, the same swipe closes it.
        model.keepNotchOpenUntilDecision = false
        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: EdgeSwipeDriver.far, startingAt: 2), to: controller, at: point)
        #expect(model.notchStatus == .closed)
        #expect(model.swipeActionCount == 1)
    }

    // MARK: Sideways on the pill of the open island

    @Test func aSidewaysSwipeOnThePillOfAHoverOpenedIslandClosesItAndHidesWhatItShowsOnce() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)

        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dx: -EdgeSwipeDriver.far, steps: 40), to: controller, at: pill(controller))

        #expect(model.notchStatus == .closed)
        #expect(model.nook.closedContentHiddenBySwipe)
        #expect(model.swipeActionCount == 1, "the 40 steps are one gesture")
        #expect(controller.isHoverSuppressedUntilExit)
    }

    @Test func aSidewaysSwipeOnThePillOfTheOpenIslandWhileAnAgentWaitsClosesItAndHidesNothing() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.state = SessionState(sessions: [EdgeSwipeDriver.waitingSession()])
        model.notchOpen(reason: .hover)

        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dx: EdgeSwipeDriver.far), to: controller, at: pill(controller))

        #expect(model.notchStatus == .closed)
        #expect(model.nook.closedContentHiddenBySwipe == false)
        #expect(model.swipeActionCount == 1, "closing the island was something")
    }

    @Test func aSwipeUpAndThenASidewaysSwipeOnTheNextOpenAreTwoCounts() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()

        model.notchOpen(reason: .hover)
        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: EdgeSwipeDriver.far), to: controller, at: try content(model, controller))
        model.notchOpen(reason: .hover)
        EdgeSwipeDriver.send(
            EdgeSwipeDriver.gesture(dx: EdgeSwipeDriver.far, startingAt: 3), to: controller, at: pill(controller)
        )

        #expect(model.swipeActionCount == 2)
        #expect(model.notchStatus == .closed)
        #expect(model.nook.closedContentHiddenBySwipe)
    }

    // MARK: The island changes under a gesture

    @Test func anIslandThatClosesByItselfInTheMiddleOfAnUpSwipeIsNotSwipedAgain() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)
        let point = try content(model, controller)
        let gesture = EdgeSwipeDriver.gesture(dy: 200, steps: 20)

        EdgeSwipeDriver.send(Array(gesture[0..<3]), to: controller, at: point)
        model.notchClose()
        let rest = EdgeSwipeDriver.send(Array(gesture[3...]), to: controller, at: point)

        #expect(model.swipeActionCount == 0)
        #expect(rest.allSatisfy { !$0 }, "the gesture was never the island's")
        #expect(model.nook.closedContentHiddenBySwipe == false)
    }

    /// A sideways gesture that began over the closed pill crosses its limit
    /// after a click has opened the island: it acts as the rule says for the
    /// open island, which is to close it and hide what the pill shows.
    @Test func aSidewaysGestureThatCrossesItsLimitAfterTheIslandOpenedActsOnTheOpenIsland() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        let gesture = EdgeSwipeDriver.gesture(dx: 200, steps: 20)

        EdgeSwipeDriver.send(Array(gesture[0..<3]), to: controller, at: pill(controller))
        #expect(model.swipeActionCount == 0)
        model.notchOpen(reason: .click)
        EdgeSwipeDriver.send(Array(gesture[3...]), to: controller, at: pill(controller))

        #expect(model.notchStatus == .closed)
        #expect(model.swipeActionCount == 1)
        #expect(model.nook.closedContentHiddenBySwipe)
    }

    @Test func aSwipeUpThatClosedTheIslandHoldsTheRestOfTheGestureForTheLocalMonitorOnly() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)
        let point = try content(model, controller)
        let gesture = EdgeSwipeDriver.gesture(dy: 400, steps: 20)

        EdgeSwipeDriver.send(Array(gesture[0..<8]), to: controller, at: point)
        #expect(model.notchStatus == .closed)

        let local = EdgeSwipeDriver.send(Array(gesture[8..<14]), to: controller, at: Self.far)
        let global = EdgeSwipeDriver.send(Array(gesture[14...]), to: controller, at: Self.far, isLocal: false)
        #expect(local.allSatisfy { $0 }, "the local monitor swallows the tail, wherever the pointer went")
        #expect(global.allSatisfy { !$0 }, "the global monitor only observes")
        #expect(model.swipeActionCount == 1)

        // The next gesture is nobody's tail.
        let next = EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: 10, startingAt: 5), to: controller, at: Self.far)
        #expect(next.allSatisfy { !$0 })
    }

    // MARK: Hover waits for a swipe

    @Test func fingersOnTheClosedPillCancelAHoverOpenThatWasWaiting() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()

        controller.handleMouseMoved(pill(controller))
        // Fingers land on the pill before the hover wait is over.
        let now = ProcessInfo.processInfo.systemUptime
        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: 5, steps: 1, startingAt: now, ends: false), to: controller, at: pill(controller))
        try await Task.sleep(for: Self.hoverWait)

        #expect(model.notchStatus == .closed)
    }

    @Test func hoverOpensAgainOnceTheScrollGestureHasGoneQuiet() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        let now = ProcessInfo.processInfo.systemUptime
        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: 5, steps: 1, startingAt: now), to: controller, at: pill(controller))

        controller.handleMouseMoved(pill(controller))
        try await Task.sleep(for: Self.hoverWait)
        #expect(model.notchStatus == .closed, "the gesture was a moment ago")

        // By now more than the wheel gap has passed since its last sample.

        controller.handleMouseMoved(pill(controller))
        try await Task.sleep(for: Self.hoverWait)
        #expect(model.notchStatus == .opened)
        model.notchClose()
    }

    // MARK: The panel after a swipe close

    @Test func thePanelTakesEventsForTheTailOfASwipeCloseAndThenLetsGoOfThem() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()
        model.notchOpen(reason: .hover)
        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: EdgeSwipeDriver.far), to: controller, at: try content(model, controller))
        #expect(model.notchStatus == .closed)
        #expect(controller.isClosedPanelDragReceptive, "the panel keeps taking events to swallow the tail")

        // A hard limit, not a promise to wait for the gesture's end.
        try await Task.sleep(for: .milliseconds(900))
        #expect(controller.isClosedPanelDragReceptive == false)
    }

    @Test func aSecondSwipeCloseInsideTheFirstHoldRestartsTheLimitAndStillEndsInTime() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let (model, controller) = modelWithPanel()

        model.notchOpen(reason: .hover)
        EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: EdgeSwipeDriver.far), to: controller, at: try content(model, controller))
        model.notchOpen(reason: .hover)
        EdgeSwipeDriver.send(
            EdgeSwipeDriver.gesture(dy: EdgeSwipeDriver.far, startingAt: 5), to: controller, at: try content(model, controller)
        )
        #expect(model.notchStatus == .closed)
        #expect(controller.isClosedPanelDragReceptive)

        try await Task.sleep(for: .milliseconds(900))
        #expect(controller.isClosedPanelDragReceptive == false)
    }

    // MARK: No panel

    @Test func aControllerWithNoPanelAndNoModelSwallowsNothingAndCrashesAtNothing() {
        let controller = OverlayPanelController()
        let answers = EdgeSwipeDriver.send(EdgeSwipeDriver.gesture(dy: 100), to: controller)
        #expect(answers.allSatisfy { !$0 })
        #expect(controller.hasPanel == false)
    }
}
