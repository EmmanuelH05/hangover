import AppKit
import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

// A swipe sends the island away (D46): the recognizer, the rule, the scroll
// view walk and the hidden state of the closed island.

// MARK: - The recognizer

struct IslandSwipeRecognizerTests {
    /// A trackpad sample in finger direction, `step` seconds after the start.
    private static func sample(
        dx: Double = 0,
        dy: Double = 0,
        phase: IslandScrollSample.Phase = .changed,
        momentum: Bool = false,
        at time: TimeInterval = 0
    ) -> IslandScrollSample {
        IslandScrollSample(dx: dx, dy: dy, phase: phase, isMomentum: momentum, timestamp: time)
    }

    /// Feeds a gesture that begins with a zero sample and returns the last answer.
    private static func swipe(
        _ recognizer: inout IslandSwipeRecognizer,
        dx: Double = 0,
        dy: Double = 0,
        steps: Int = 4
    ) -> IslandSwipeDirection? {
        var fired: IslandSwipeDirection?
        _ = recognizer.feed(sample(phase: .began, at: 0))
        for step in 1...steps {
            let answer = recognizer.feed(sample(
                dx: dx / Double(steps),
                dy: dy / Double(steps),
                at: Double(step) * 0.01
            ))
            fired = fired ?? answer
        }
        return fired
    }

    @Test func firesOncePastTheThresholdInEachDirection() {
        let far = IslandSwipeRecognizer.threshold + 4
        var recognizer = IslandSwipeRecognizer()
        #expect(Self.swipe(&recognizer, dy: far) == .up)
        #expect(Self.swipe(&recognizer, dy: -far) == .down)
        #expect(Self.swipe(&recognizer, dx: far) == .right)
        #expect(Self.swipe(&recognizer, dx: -far) == .left)
    }

    @Test func doesNotFireBelowTheThreshold() {
        var recognizer = IslandSwipeRecognizer()
        #expect(Self.swipe(&recognizer, dy: IslandSwipeRecognizer.threshold - 1) == nil)
        #expect(recognizer.hasFired == false)
    }

    @Test func needsTwoToOneDominanceOverTheOtherAxis() {
        let far = IslandSwipeRecognizer.threshold + 4
        var recognizer = IslandSwipeRecognizer()
        // A diagonal drag is neither.
        #expect(Self.swipe(&recognizer, dx: far, dy: far) == nil)
        // Just under two to one still is not.
        #expect(Self.swipe(&recognizer, dx: far / 1.9, dy: far) == nil)
        // Just over it is.
        #expect(Self.swipe(&recognizer, dx: far / 2.1, dy: far) == .up)
    }

    @Test func momentumNeverCountsAndNeverFires() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(phase: .began))
        for step in 1...10 {
            #expect(recognizer.feed(Self.sample(dy: 50, momentum: true, at: Double(step) * 0.01)) == nil)
        }
        #expect(recognizer.hasFired == false)
        // The real fingers still count afterwards.
        #expect(recognizer.feed(Self.sample(dy: IslandSwipeRecognizer.threshold, at: 0.2)) == .up)
    }

    @Test func staysQuietAfterFiringUntilTheGestureEnds() {
        var recognizer = IslandSwipeRecognizer()
        #expect(Self.swipe(&recognizer, dy: 80) == .up)
        #expect(recognizer.hasFired)
        #expect(recognizer.feed(Self.sample(dy: 80, at: 0.5)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 80, phase: .ended, at: 0.51)) == nil)
        #expect(recognizer.hasFired)

        // The next gesture is a new one.
        #expect(Self.swipe(&recognizer, dy: 80) == .up)
    }

    @Test func aChangeWithoutABeginIsNotOurs() {
        var recognizer = IslandSwipeRecognizer()
        #expect(recognizer.feed(Self.sample(dy: 200, phase: .changed)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 200, phase: .ended)) == nil)
    }

    @Test func aWheelStartsANewGestureAfterAGap() {
        var recognizer = IslandSwipeRecognizer()
        let gap = IslandSwipeRecognizer.wheelGap
        #expect(recognizer.feed(Self.sample(dy: 30, phase: .none, at: 0)) == nil)
        // Within the gap the first notch still counts.
        #expect(recognizer.feed(Self.sample(dy: 30, phase: .none, at: gap - 0.05)) == .up)
        #expect(recognizer.feed(Self.sample(dy: 30, phase: .none, at: gap)) == nil)

        // After the gap the sums start again. The pieces do not add up
        // across it.
        var gapped = IslandSwipeRecognizer()
        #expect(gapped.feed(Self.sample(dy: 30, phase: .none, at: 0)) == nil)
        #expect(gapped.feed(Self.sample(dy: 30, phase: .none, at: gap + 0.1)) == nil)
        #expect(gapped.hasFired == false)
        #expect(gapped.feed(Self.sample(dy: 30, phase: .none, at: gap + 0.15)) == .up)
        // And after firing, the next gap makes it ready again.
        #expect(gapped.feed(Self.sample(dy: 60, phase: .none, at: gap * 3)) == .up)
    }

    @Test func aWheelsLinesAreScaledToPoints() {
        func make(lines: Double) -> IslandScrollSample {
            IslandScrollSample.make(
                scrollingDeltaX: 0,
                scrollingDeltaY: lines,
                hasPreciseScrollingDeltas: false,
                isDirectionInvertedFromDevice: false,
                phase: [],
                momentumPhase: [],
                timestamp: 0
            )
        }
        #expect(IslandScrollSample.pointsPerWheelLine == 12)
        #expect(make(lines: 1).dy == 12)
        // Three lines pass 36 points, one does not.
        var recognizer = IslandSwipeRecognizer()
        #expect(recognizer.feed(make(lines: 1)) == nil)
        var other = IslandSwipeRecognizer()
        #expect(other.feed(make(lines: 3)) == .up)
        #expect(make(lines: 1).phase == .none)
    }

    @Test func rawDeltasBecomeFingerDirectionForBothSettings() {
        func make(dx: Double, dy: Double, inverted: Bool) -> IslandScrollSample {
            IslandScrollSample.make(
                scrollingDeltaX: dx,
                scrollingDeltaY: dy,
                hasPreciseScrollingDeltas: true,
                isDirectionInvertedFromDevice: inverted,
                phase: .changed,
                momentumPhase: [],
                timestamp: 0
            )
        }
        // Natural scrolling: fingers up make the content move up, a negative delta.
        #expect(make(dx: 0, dy: -5, inverted: true).dy == 5)
        #expect(make(dx: 0, dy: 5, inverted: true).dy == -5)
        #expect(make(dx: 5, dy: 0, inverted: true).dx == 5)
        #expect(make(dx: -5, dy: 0, inverted: true).dx == -5)
        // Traditional scrolling is the other way round.
        #expect(make(dx: 0, dy: 5, inverted: false).dy == 5)
        #expect(make(dx: 0, dy: -5, inverted: false).dy == -5)
        #expect(make(dx: -5, dy: 0, inverted: false).dx == 5)
        #expect(make(dx: 5, dy: 0, inverted: false).dx == -5)
    }

    @Test func phasesAndMomentumAreRead() {
        func make(_ phase: NSEvent.Phase, momentum: NSEvent.Phase = []) -> IslandScrollSample {
            IslandScrollSample.make(
                scrollingDeltaX: 0, scrollingDeltaY: 0,
                hasPreciseScrollingDeltas: true, isDirectionInvertedFromDevice: true,
                phase: phase, momentumPhase: momentum, timestamp: 0
            )
        }
        #expect(make(.began).phase == .began)
        #expect(make(.changed).phase == .changed)
        #expect(make(.ended).phase == .ended)
        #expect(make(.cancelled).phase == .ended)
        #expect(make([]).phase == .none)
        #expect(make([], momentum: .changed).isMomentum)
        #expect(make(.changed).isMomentum == false)
    }

    @Test func consumingAGestureLastsUntilTheNextOneStarts() {
        var recognizer = IslandSwipeRecognizer()
        #expect(Self.swipe(&recognizer, dy: 80) == .up)
        #expect(recognizer.isConsumed == false)
        recognizer.markConsumed()
        #expect(recognizer.isConsumed)
        _ = recognizer.feed(Self.sample(phase: .began, at: 1))
        #expect(recognizer.isConsumed == false)
    }
}

// MARK: - The rule

@Suite struct IslandSwipeRuleTests {
    private static func context(
        _ status: NotchStatus,
        _ direction: IslandSwipeDirection,
        closed: Bool = false,
        expanded: Bool = false,
        scrollable: Bool = false,
        blocks: Bool = false,
        picker: Bool = false,
        tour: Bool = false
    ) -> IslandSwipeContext {
        IslandSwipeContext(
            status: status,
            direction: direction,
            isInClosedSurface: closed,
            isInExpandedArea: expanded,
            isOverScrollableContent: scrollable,
            blocksDismiss: blocks,
            hasOpenPicker: picker,
            holdsOpenForTour: tour
        )
    }

    @Test func aSwipeUpOnTheOpenIslandClosesIt() {
        #expect(IslandPointerRules.swipeAction(Self.context(.opened, .up, expanded: true)) == .close)
    }

    @Test func theOpenIslandIgnoresEveryOtherDirectionAndEveryOtherPlace() {
        for direction in [IslandSwipeDirection.down, .left, .right] {
            #expect(IslandPointerRules.swipeAction(Self.context(.opened, direction, expanded: true)) == .none)
        }
        #expect(IslandPointerRules.swipeAction(Self.context(.opened, .up)) == .none)
        // The closed surface alone is not the open island.
        #expect(IslandPointerRules.swipeAction(Self.context(.opened, .up, closed: true)) == .none)
    }

    @Test func eachRefusalKeepsTheOpenIslandOpen() {
        #expect(IslandPointerRules.swipeAction(Self.context(.opened, .up, expanded: true, scrollable: true)) == .none)
        #expect(IslandPointerRules.swipeAction(Self.context(.opened, .up, expanded: true, blocks: true)) == .none)
        #expect(IslandPointerRules.swipeAction(Self.context(.opened, .up, expanded: true, picker: true)) == .none)
        #expect(IslandPointerRules.swipeAction(Self.context(.opened, .up, expanded: true, tour: true)) == .none)
    }

    @Test func aSidewaysSwipeOnTheClosedIslandTogglesItsContent() {
        for direction in [IslandSwipeDirection.left, .right] {
            #expect(IslandPointerRules.swipeAction(Self.context(.closed, direction, closed: true)) == .toggleClosedContent)
            #expect(IslandPointerRules.swipeAction(Self.context(.closed, direction)) == .none)
        }
    }

    @Test func theClosedIslandIgnoresVerticalSwipes() {
        for direction in [IslandSwipeDirection.up, .down] {
            #expect(IslandPointerRules.swipeAction(Self.context(.closed, direction, closed: true)) == .none)
        }
    }

    @Test func aPoppingIslandIgnoresEverySwipe() {
        for direction in [IslandSwipeDirection.up, .down, .left, .right] {
            #expect(
                IslandPointerRules.swipeAction(Self.context(.popping, direction, closed: true, expanded: true)) == .none
            )
        }
    }
}

// MARK: - The scroll view walk

@MainActor
struct IslandScrollContentTests {
    private static func scrollView(documentHeight: CGFloat) -> (NSScrollView, NSView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: documentHeight))
        scrollView.documentView = document
        let inner = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        document.addSubview(inner)
        return (scrollView, inner)
    }

    @Test func aViewInsideATallDocumentIsScrollable() {
        let (scrollView, inner) = Self.scrollView(documentHeight: 400)
        #expect(IslandScrollContent.isScrollable(from: inner))
        #expect(IslandScrollContent.isScrollable(from: scrollView))
    }

    @Test func aDocumentThatFitsIsNotScrollable() {
        let (_, inner) = Self.scrollView(documentHeight: 100)
        #expect(IslandScrollContent.isScrollable(from: inner) == false)
    }

    @Test func aDocumentOnePointTallerDoesNotCount() {
        let (_, inner) = Self.scrollView(documentHeight: 101)
        #expect(IslandScrollContent.isScrollable(from: inner) == false)
        let (_, taller) = Self.scrollView(documentHeight: 102)
        #expect(IslandScrollContent.isScrollable(from: taller))
    }

    @Test func missingPiecesAnswerFalse() {
        #expect(IslandScrollContent.isScrollable(from: nil) == false)
        #expect(IslandScrollContent.isScrollable(from: NSView()) == false)
        let empty = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        #expect(IslandScrollContent.isScrollable(from: empty) == false)
    }

    /// A hosting view can answer a hit test with itself. The search down from it
    /// finds the scroll view under the point, and only that one.
    @Test func aScrollViewBelowTheHitViewIsFoundOnlyUnderThePoint() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let (scrollView, _) = Self.scrollView(documentHeight: 400)
        scrollView.frame = NSRect(x: 50, y: 50, width: 200, height: 100)
        container.addSubview(scrollView)

        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: NSPoint(x: 100, y: 80)))
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: NSPoint(x: 10, y: 10)) == false)
        #expect(IslandScrollContent.isScrollable(from: container) == false)
    }
}

// MARK: - The hidden state

@MainActor
struct ClosedContentHiddenTests {
    private static func model() -> AppModel {
        AppModel(
            isNotificationSessionAlreadyFrontmost: { _ in true },
            agentsDefaults: MemoryDefaults()
        )
    }

    private static func runningSession() -> AgentSession {
        var session = AgentSession(
            id: "running",
            title: "Claude · project",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )
        session.isProcessAlive = true
        return session
    }

    private static let music = NookClosedMediaActivity(
        artwork: nil, gifURL: nil, gifScale: 1, gifOffset: .zero, isPlaying: true
    )

    private static let notice = NookTransientActivity(symbol: "bolt.fill", text: "Charging", tint: .green)

    // MARK: The resolver

    @Test func hiddenMusicAndTimerResolveToNothing() {
        let preferences = NookDisplayPreferences()
        let shown = NookClosedActivity.resolve(
            transient: nil, timerText: "12:00", media: Self.music, preferences: preferences
        )
        #expect(shown != nil)
        let hidden = NookClosedActivity.resolve(
            transient: nil, timerText: "12:00", media: Self.music, preferences: preferences, isHidden: true
        )
        #expect(hidden == nil)
        let idle = NookClosedActivity.resolve(
            transient: nil, timerText: nil, media: nil, preferences: preferences
        )
        #expect(hidden == idle)
    }

    @Test func aNoticeShowsThroughWhileHidden() {
        let preferences = NookDisplayPreferences()
        let hidden = NookClosedActivity.resolve(
            transient: Self.notice, timerText: "12:00", media: Self.music, preferences: preferences, isHidden: true
        )
        let shown = NookClosedActivity.resolve(
            transient: Self.notice, timerText: nil, media: nil, preferences: preferences
        )
        #expect(hidden != nil)
        #expect(hidden == shown)
    }

    // MARK: The model

    @Test func hiddenContentIsWhatAnIdleIslandWithNothingOnEitherSideDraws() {
        let model = Self.model()
        model.state = SessionState(sessions: [Self.runningSession()])
        #expect(model.islandClosedMode == .running)
        #expect(model.islandClosedPillMode == .running)

        model.nook.closedContentHiddenBySwipe = true

        #expect(model.closedContentIsHidden)
        #expect(model.islandClosedPillMode == .idle)
        #expect(model.nookLeftSlotContent == .hidden)
        #expect(model.nookRightSlotContent == nil)
        #expect(model.islandClosedRightSlotContent() == nil)
        #expect(model.islandClosedLabelWithNook() == nil)
        #expect(model.nookClosedActivity == nil)
        #expect(model.nookAgentStatusTint == nil)
        #expect(model.islandHaloInputs.isRunning == false)
        #expect(model.islandHaloInputs.isMusicPlaying == false)
    }

    @Test func aNoticeShowsThroughWithoutClearingTheFlag() {
        let model = Self.model()
        model.nook.closedContentHiddenBySwipe = true

        model.nook.showTransient(symbol: "bolt.fill", text: "Charging", tint: .green, duration: .seconds(60))

        #expect(model.nookClosedActivity != nil)
        #expect(model.nook.closedContentHiddenBySwipe)
    }

    @Test func theFlashWhenAnAgentFinishesShowsThroughWhileHidden() {
        let model = Self.model()
        model.nook.closedContentHiddenBySwipe = true
        model.halo.noteCompletion()

        #expect(model.islandHaloInputs.flashToken != nil)
        #expect(model.nook.closedContentHiddenBySwipe)
    }

    @Test func aSecondSwipeBringsItBack() {
        let model = Self.model()
        model.state = SessionState(sessions: [Self.runningSession()])

        model.toggleClosedContentHidden()
        #expect(model.closedContentIsHidden)
        model.toggleClosedContentHidden()
        #expect(model.closedContentIsHidden == false)
        #expect(model.islandClosedPillMode == .running)
    }

    @Test func anAgentThatStartsWaitingBringsItBack() {
        let model = Self.model()
        model.state = SessionState(sessions: [Self.runningSession()])
        model.nook.closedContentHiddenBySwipe = true

        model.applyTrackedEvent(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "running",
                    request: PermissionRequest(title: "Edit", summary: "main.swift", affectedPath: "/tmp/main.swift"),
                    timestamp: .now
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.nook.closedContentHiddenBySwipe == false)
        #expect(model.islandClosedPillMode == .waiting)
    }

    @Test func aWaitingAgentIsNeverHidden() {
        let model = Self.model()
        var session = Self.runningSession()
        session.phase = .waitingForApproval
        session.permissionRequest = PermissionRequest(title: "Edit", summary: "x", affectedPath: "/tmp/x")
        model.state = SessionState(sessions: [session])

        model.nook.closedContentHiddenBySwipe = true

        #expect(model.closedContentIsHidden == false)
        #expect(model.islandClosedPillMode == .waiting)
    }

    @Test func aNotificationCardOpeningTheIslandBringsItBack() {
        let model = Self.model()
        model.nook.closedContentHiddenBySwipe = true

        model.notchOpen(reason: .notification, surface: .sessionList())

        #expect(model.nook.closedContentHiddenBySwipe == false)
    }

    @Test func openingByHoverOrClickAndClosingAgainLeavesItHidden() {
        let model = Self.model()
        model.nook.closedContentHiddenBySwipe = true

        model.notchOpen(reason: .hover)
        model.notchClose()
        model.notchOpen(reason: .click)
        model.notchClose()

        #expect(model.nook.closedContentHiddenBySwipe)
    }

    @Test func thePreviewsNeverFollowTheFlag() {
        let model = Self.model()
        let before = model.nook.previewClosedActivity(for: NookDisplayPreferences())
        model.nook.closedContentHiddenBySwipe = true
        let after = model.nook.previewClosedActivity(for: NookDisplayPreferences())
        #expect(before == after)
    }
}


