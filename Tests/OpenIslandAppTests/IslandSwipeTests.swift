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

    @Test func aConsumedGestureStaysTheIslandsWhereverThePointerGoes() {
        var recognizer = IslandSwipeRecognizer()
        #expect(Self.swipe(&recognizer, dy: 80) == .up)
        recognizer.markConsumed()

        // The island closed and the pointer is on nothing it owns. The rest
        // of the gesture, its end and the tail after it are still swallowed.
        let kept = recognizer.feedOffIsland(Self.sample(dy: 5, at: 0.10))
        #expect(kept)
        let kept2 = recognizer.feedOffIsland(Self.sample(dy: 5, phase: .ended, at: 0.11))
        #expect(kept2)
        let kept3 = recognizer.feedOffIsland(Self.sample(dy: 3, momentum: true, at: 0.12))
        #expect(kept3)
        #expect(recognizer.isConsumed)

        // The next gesture is not the island's.
        let dropped = recognizer.feedOffIsland(Self.sample(dy: 5, phase: .began, at: 1))
        #expect(dropped == false)
        #expect(recognizer.isConsumed == false)
    }

    @Test func aWheelGapEndsAConsumedGestureOffTheIsland() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(dy: 80, phase: .none, at: 0))
        recognizer.markConsumed()
        let kept = recognizer.feedOffIsland(Self.sample(dy: 5, phase: .none, at: 0.1))
        #expect(kept)
        let later = 0.1 + IslandSwipeRecognizer.wheelGap + 0.1
        let dropped = recognizer.feedOffIsland(Self.sample(dy: 5, phase: .none, at: later))
        #expect(dropped == false)
    }

    @Test func aGestureTheIslandDidNotActOnIsForgottenOffTheIsland() {
        var recognizer = IslandSwipeRecognizer()
        #expect(Self.swipe(&recognizer, dy: 20) == nil)
        let dropped = recognizer.feedOffIsland(Self.sample(dy: 5, at: 0.2))
        #expect(dropped == false)
        // Reset: a change with no begin is not ours.
        #expect(recognizer.feed(Self.sample(dy: 80, at: 0.3)) == nil)
    }

    @Test func aScrollGestureIsInProgressUntilTheWheelGapPasses() {
        var recognizer = IslandSwipeRecognizer()
        #expect(recognizer.isInProgress(at: 0) == false)
        _ = recognizer.feed(Self.sample(dy: 4, phase: .began, at: 10))
        #expect(recognizer.isInProgress(at: 10.1))
        #expect(recognizer.isInProgress(at: 10 + IslandSwipeRecognizer.wheelGap + 0.01) == false)
    }

    @Test func theSampleRemembersWhetherScrollingIsNatural() {
        func make(inverted: Bool) -> IslandScrollSample {
            IslandScrollSample.make(
                scrollingDeltaX: 0, scrollingDeltaY: 5, hasPreciseScrollingDeltas: true,
                isDirectionInvertedFromDevice: inverted, phase: [], momentumPhase: [], timestamp: 0
            )
        }
        #expect(make(inverted: true).isNaturalScrolling)
        #expect(make(inverted: false).isNaturalScrolling == false)
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

    @Test func aSidewaysSwipeOnThePillOfTheOpenIslandClosesItAndTogglesItsContent() {
        // Hover opens the island 0.15 seconds after the pointer reaches the
        // pill, which is before a swipe can be made.
        for direction in [IslandSwipeDirection.left, .right] {
            #expect(
                IslandPointerRules.swipeAction(Self.context(.opened, direction, closed: true, expanded: true))
                    == .closeAndToggleClosedContent
            )
            // Off the pill, a sideways swipe on the open island is nothing.
            #expect(IslandPointerRules.swipeAction(Self.context(.opened, direction, expanded: true)) == .none)
        }
    }

    @Test func eachRefusalKeepsTheOpenIslandOpenForASidewaysSwipeToo() {
        for direction in [IslandSwipeDirection.left, .right] {
            #expect(IslandPointerRules.swipeAction(
                Self.context(.opened, direction, closed: true, expanded: true, blocks: true)) == .none)
            #expect(IslandPointerRules.swipeAction(
                Self.context(.opened, direction, closed: true, expanded: true, picker: true)) == .none)
            #expect(IslandPointerRules.swipeAction(
                Self.context(.opened, direction, closed: true, expanded: true, tour: true)) == .none)
        }
    }

    @Test func aSwipeUpOnThePillOfTheOpenIslandStillJustCloses() {
        #expect(IslandPointerRules.swipeAction(Self.context(.opened, .up, closed: true, expanded: true)) == .close)
    }

    @Test func hoverDoesNotOpenWhileAScrollGestureIsOverThePill() {
        #expect(IslandPointerRules.hoverOpens(trigger: .hover, isSuppressed: false))
        #expect(IslandPointerRules.hoverOpens(trigger: .hover, isSuppressed: false, isScrolling: false))
        #expect(IslandPointerRules.hoverOpens(trigger: .hover, isSuppressed: false, isScrolling: true) == false)
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
    /// A flipped document, as SwiftUI's hosting views and most lists have.
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private static func scrollView(
        documentHeight: CGFloat,
        flipped: Bool = false
    ) -> (NSScrollView, NSView, NSView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let frame = NSRect(x: 0, y: 0, width: 200, height: documentHeight)
        let document: NSView = flipped ? FlippedView(frame: frame) : NSView(frame: frame)
        scrollView.documentView = document
        let inner = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        document.addSubview(inner)
        return (scrollView, inner, document)
    }

    /// Scrolls the document to `fraction` of the way from its start to
    /// its end: 0 is the start (the top), 1 the end.
    private static func scroll(_ scrollView: NSScrollView, toFraction fraction: CGFloat) {
        guard let document = scrollView.documentView else { return }
        let travel = document.bounds.height - scrollView.contentSize.height
        let y = document.isFlipped ? travel * fraction : travel * (1 - fraction)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @Test func aListAtItsStartCanOnlyTravelTowardItsEnd() {
        for flipped in [false, true] {
            let (scrollView, inner, _) = Self.scrollView(documentHeight: 400, flipped: flipped)
            Self.scroll(scrollView, toFraction: 0)
            #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardEnd), "flipped \(flipped)")
            #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardStart) == false, "flipped \(flipped)")
        }
    }

    @Test func aListAtItsEndCanOnlyTravelTowardItsStart() {
        for flipped in [false, true] {
            let (scrollView, inner, _) = Self.scrollView(documentHeight: 400, flipped: flipped)
            Self.scroll(scrollView, toFraction: 1)
            #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardEnd) == false, "flipped \(flipped)")
            #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardStart), "flipped \(flipped)")
        }
    }

    @Test func aListInTheMiddleCanTravelBothWays() {
        for flipped in [false, true] {
            let (scrollView, inner, _) = Self.scrollView(documentHeight: 400, flipped: flipped)
            Self.scroll(scrollView, toFraction: 0.5)
            #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardEnd))
            #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardStart))
            #expect(IslandScrollContent.isScrollable(from: scrollView, travel: .towardEnd))
        }
    }

    @Test func theRectsDecideWithoutAnyView() {
        let document = CGRect(x: 0, y: 0, width: 200, height: 400)
        let top = CGRect(x: 0, y: 0, width: 200, height: 100)
        let bottom = CGRect(x: 0, y: 300, width: 200, height: 100)
        // Flipped: the start is at y 0.
        #expect(IslandScrollContent.canTravel(.towardEnd, visible: top, document: document, isFlipped: true))
        #expect(!IslandScrollContent.canTravel(.towardStart, visible: top, document: document, isFlipped: true))
        #expect(!IslandScrollContent.canTravel(.towardEnd, visible: bottom, document: document, isFlipped: true))
        // Unflipped: the start is at the highest y.
        #expect(IslandScrollContent.canTravel(.towardStart, visible: top, document: document, isFlipped: false))
        #expect(!IslandScrollContent.canTravel(.towardEnd, visible: top, document: document, isFlipped: false))
        #expect(!IslandScrollContent.canTravel(.towardStart, visible: bottom, document: document, isFlipped: false))
    }

    @Test func aSwipeUpTravelsTheWayTheScrollingSettingSays() {
        #expect(IslandScrollTravel.of(.up, isNaturalScrolling: true) == .towardEnd)
        #expect(IslandScrollTravel.of(.up, isNaturalScrolling: false) == .towardStart)
        #expect(IslandScrollTravel.of(.down, isNaturalScrolling: true) == .towardStart)
        #expect(IslandScrollTravel.of(.left, isNaturalScrolling: true) == nil)
        #expect(IslandScrollTravel.of(.right, isNaturalScrolling: false) == nil)
    }

    @Test func aDocumentThatFitsIsNotScrollable() {
        let (_, inner, _) = Self.scrollView(documentHeight: 100)
        #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardStart) == false)
        #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardEnd) == false)
    }

    @Test func aDocumentOnePointTallerDoesNotCount() {
        let (_, inner, _) = Self.scrollView(documentHeight: 101, flipped: true)
        #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardEnd) == false)
        let (_, taller, _) = Self.scrollView(documentHeight: 102, flipped: true)
        #expect(IslandScrollContent.isScrollable(from: taller, travel: .towardEnd))
    }

    @Test func missingPiecesAnswerFalse() {
        #expect(IslandScrollContent.isScrollable(from: nil, travel: .towardEnd) == false)
        #expect(IslandScrollContent.isScrollable(from: NSView(), travel: .towardEnd) == false)
        let empty = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        #expect(IslandScrollContent.isScrollable(from: empty, travel: .towardEnd) == false)
    }

    /// A hosting view can answer a hit test with itself. The search down from it
    /// finds the scroll view under the point, and only that one.
    @Test func aScrollViewBelowTheHitViewIsFoundOnlyUnderThePoint() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let (scrollView, _, _) = Self.scrollView(documentHeight: 400, flipped: true)
        scrollView.frame = NSRect(x: 50, y: 50, width: 200, height: 100)
        container.addSubview(scrollView)
        Self.scroll(scrollView, toFraction: 0)

        let inside = NSPoint(x: 100, y: 80)
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: inside, travel: .towardEnd))
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: inside, travel: .towardStart) == false)
        #expect(IslandScrollContent.isScrollable(
            from: container, windowPoint: NSPoint(x: 10, y: 10), travel: .towardEnd) == false)
        #expect(IslandScrollContent.isScrollable(from: container, travel: .towardEnd) == false)
    }

    /// The search used to stop at the first scroll view under the point. A
    /// short outer one that cannot travel may hold a long inner one that can.
    @Test func theSearchDownLooksInsideANestedScrollView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let outer = NSScrollView(frame: NSRect(x: 50, y: 50, width: 200, height: 100))
        let outerDocument = FlippedView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        outer.documentView = outerDocument
        let (inner, _, _) = Self.scrollView(documentHeight: 400, flipped: true)
        inner.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        outerDocument.addSubview(inner)
        container.addSubview(outer)
        Self.scroll(inner, toFraction: 0)

        let point = NSPoint(x: 100, y: 80)
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: point, travel: .towardEnd))
        Self.scroll(inner, toFraction: 1)
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: point, travel: .towardEnd) == false)
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: point, travel: .towardStart))
    }
}

// MARK: - The pill rectangle

struct IslandPillBoundsTests {
    @Test func aScrollEventNeverAsksTheScreen() {
        var bounds = IslandPillBounds()
        var screenQueries = 0
        bounds.refresh {
            screenQueries += 1
            return CGRect(x: 100, y: 900, width: 300, height: 32)
        }
        #expect(screenQueries == 1)

        // A thousand scroll events: the pointer is tested against the stored rect.
        var hits = 0
        for index in 0..<1000 where bounds.contains(CGPoint(x: 100 + Double(index % 400), y: 910)) {
            hits += 1
        }
        #expect(screenQueries == 1)
        #expect(hits == 802)
    }

    @Test func edgesCountAsInsideAndOutsideDoesNot() {
        var bounds = IslandPillBounds()
        bounds.refresh { CGRect(x: 100, y: 900, width: 300, height: 32) }
        #expect(bounds.contains(CGPoint(x: 100, y: 900)))
        #expect(bounds.contains(CGPoint(x: 400, y: 932)))
        #expect(bounds.contains(CGPoint(x: 99.9, y: 910)) == false)
        #expect(bounds.contains(CGPoint(x: 250, y: 932.1)) == false)
    }

    @Test func refreshingWorksTheRectOutAgain() {
        var bounds = IslandPillBounds()
        bounds.refresh { CGRect(x: 0, y: 0, width: 10, height: 10) }
        bounds.refresh { CGRect(x: 500, y: 500, width: 10, height: 10) }
        #expect(bounds.contains(CGPoint(x: 5, y: 5)) == false)
        #expect(bounds.contains(CGPoint(x: 505, y: 505)))
    }
}

// MARK: - The scroll step

/// What the panel controller does with one scroll event, as a pure step:
/// the recognizer, the sample and the facts go in, the action and whether to
/// swallow the event come out.
@Suite(.noNewWindows)
struct IslandScrollStepTests {
    private static let far = IslandSwipeRecognizer.threshold + 4

    private static func facts(
        status: NotchStatus,
        onPill: Bool = false,
        inExpanded: Bool = false,
        local: Bool = true,
        refusals: IslandSwipeRefusals = IslandSwipeRefusals(),
        enabled: Bool = true
    ) -> IslandScrollFacts {
        IslandScrollFacts(
            isEnabled: enabled,
            status: status,
            isInClosedSurface: onPill,
            isInExpandedArea: inExpanded,
            isLocalEvent: local,
            refusals: refusals
        )
    }

    private static func sample(
        dx: Double = 0,
        dy: Double = 0,
        phase: IslandScrollSample.Phase = .changed,
        at time: TimeInterval
    ) -> IslandScrollSample {
        IslandScrollSample(dx: dx, dy: dy, phase: phase, isMomentum: false, timestamp: time)
    }

    /// One whole gesture of four changes after a begin, every sample under
    /// the same facts. Returns the answer to each sample, begin first.
    private static func gesture(
        _ recognizer: inout IslandSwipeRecognizer,
        _ facts: IslandScrollFacts,
        dx: Double = 0,
        dy: Double = 0,
        overScrollable: @escaping (IslandSwipeDirection) -> Bool = { _ in false }
    ) -> [IslandScrollOutcome] {
        var outcomes = [IslandPointerRules.scrollStep(
            recognizer: &recognizer,
            sample: sample(phase: .began, at: 0),
            facts: facts,
            isOverScrollableContent: overScrollable
        )]
        for step in 1...4 {
            outcomes.append(IslandPointerRules.scrollStep(
                recognizer: &recognizer,
                sample: sample(dx: dx / 4, dy: dy / 4, at: Double(step) * 0.01),
                facts: facts,
                isOverScrollableContent: overScrollable
            ))
        }
        return outcomes
    }

    private static func acted(_ outcomes: [IslandScrollOutcome]) -> IslandScrollOutcome? {
        outcomes.first { $0.action != .none }
    }

    // MARK: Up on the open island

    @Test func aSwipeUpOnTheOpenIslandClosesItAndAsksForHoverSuppression() throws {
        var recognizer = IslandSwipeRecognizer()
        let outcomes = Self.gesture(&recognizer, Self.facts(status: .opened, inExpanded: true), dy: Self.far)

        let outcome = try #require(Self.acted(outcomes))
        #expect(outcome.action == .close)
        #expect(outcome.suppressesHover)
        #expect(outcome.swallows)
        #expect(outcome.cancelsHoverOpen == false, "the pill is not under the pointer")
        #expect(recognizer.isConsumed)
    }

    @Test func theRestOfAnActedOnGestureIsSwallowedFromTheLocalMonitor() {
        var recognizer = IslandSwipeRecognizer()
        let opened = Self.facts(status: .opened, inExpanded: true)
        _ = Self.gesture(&recognizer, opened, dy: Self.far)
        #expect(recognizer.isConsumed)

        // More of the same gesture, still over the island and then off it.
        let over = IslandPointerRules.scrollStep(
            recognizer: &recognizer, sample: Self.sample(dy: 5, at: 0.1), facts: opened, isOverScrollableContent: { _ in false }
        )
        #expect(over.action == .none)
        #expect(over.swallows)

        let gone = IslandPointerRules.scrollStep(
            recognizer: &recognizer,
            sample: Self.sample(dy: 5, at: 0.11),
            facts: Self.facts(status: .closed),
            isOverScrollableContent: { _ in false }
        )
        #expect(gone.action == .none)
        #expect(gone.swallows, "the gesture is still the island's wherever the pointer went")
    }

    @Test func aGlobalMonitorNeverSwallowsAnything() throws {
        var recognizer = IslandSwipeRecognizer()
        let outcomes = Self.gesture(&recognizer, Self.facts(status: .opened, inExpanded: true, local: false), dy: Self.far)

        let outcome = try #require(Self.acted(outcomes))
        #expect(outcome.action == .close, "it still acts on what it observes")
        #expect(outcome.swallows == false)
        #expect(outcomes.allSatisfy { !$0.swallows })

        // Nor the rest of the gesture, over the island or off it.
        let more = IslandPointerRules.scrollStep(
            recognizer: &recognizer,
            sample: Self.sample(dy: 5, at: 0.1),
            facts: Self.facts(status: .opened, inExpanded: true, local: false),
            isOverScrollableContent: { _ in false }
        )
        let off = IslandPointerRules.scrollStep(
            recognizer: &recognizer,
            sample: Self.sample(dy: 5, at: 0.11),
            facts: Self.facts(status: .closed, local: false),
            isOverScrollableContent: { _ in false }
        )
        #expect(more.swallows == false)
        #expect(off.swallows == false)
    }

    @Test func aSwipeUpOverAListThatCanStillTravelIsRefusedAndNotSwallowed() {
        var recognizer = IslandSwipeRecognizer()
        var asked: [IslandSwipeDirection] = []
        let outcomes = Self.gesture(&recognizer, Self.facts(status: .opened, inExpanded: true), dy: Self.far) {
            asked.append($0)
            return true
        }

        #expect(Self.acted(outcomes) == nil)
        #expect(outcomes.allSatisfy { !$0.swallows })
        #expect(recognizer.isConsumed == false, "the list keeps the rest of the gesture")
        #expect(asked == [.up], "asked once, for the swipe that fired")
    }

    @Test func aGlobalEventIsNeverAskedAboutTheListUnderThePointer() throws {
        var recognizer = IslandSwipeRecognizer()
        var asked = false
        let outcomes = Self.gesture(&recognizer, Self.facts(status: .opened, inExpanded: true, local: false), dy: Self.far) { _ in
            asked = true
            return true
        }

        #expect(asked == false)
        let outcome = try #require(Self.acted(outcomes))
        #expect(outcome.action == .close)
    }

    @Test func aSwipeDownOrOneOutsideTheIslandDoesNothing() {
        var down = IslandSwipeRecognizer()
        #expect(Self.acted(Self.gesture(&down, Self.facts(status: .opened, inExpanded: true), dy: -Self.far)) == nil)

        var outside = IslandSwipeRecognizer()
        let away = Self.gesture(&outside, Self.facts(status: .opened), dy: Self.far)
        #expect(Self.acted(away) == nil)
        #expect(away.allSatisfy { !$0.swallows })

        var closed = IslandSwipeRecognizer()
        #expect(Self.acted(Self.gesture(&closed, Self.facts(status: .closed, onPill: true), dy: Self.far)) == nil)
    }

    // MARK: Refusals

    @Test(arguments: [
        IslandSwipeRefusals(blocksDismiss: true),
        IslandSwipeRefusals(hasOpenPicker: true),
        IslandSwipeRefusals(holdsOpenForTour: true),
    ])
    func eachRefusalKeepsTheOpenIslandOpenAndTheGestureUnswallowed(refusals: IslandSwipeRefusals) {
        var up = IslandSwipeRecognizer()
        let opened = Self.facts(status: .opened, onPill: true, inExpanded: true, refusals: refusals)
        let outcomes = Self.gesture(&up, opened, dy: Self.far)
        #expect(Self.acted(outcomes) == nil)
        #expect(outcomes.allSatisfy { !$0.swallows })
        #expect(up.isConsumed == false)

        // A sideways swipe on the pill is refused the same way.
        var sideways = IslandSwipeRecognizer()
        #expect(Self.acted(Self.gesture(&sideways, opened, dx: Self.far)) == nil)
    }

    @Test func theRefusalsAreForTheOpenIslandOnly() throws {
        var recognizer = IslandSwipeRecognizer()
        let all = IslandSwipeRefusals(blocksDismiss: true, hasOpenPicker: true, holdsOpenForTour: true)
        let outcomes = Self.gesture(&recognizer, Self.facts(status: .closed, onPill: true, refusals: all), dx: Self.far)

        let outcome = try #require(Self.acted(outcomes))
        #expect(outcome.action == .toggleClosedContent)
    }

    // MARK: Refusals read from the model

    @MainActor
    private static func model() -> AppModel {
        AppModel(isNotificationSessionAlreadyFrontmost: { _ in true }, defaults: MemoryDefaults())
    }

    @MainActor
    @Test func aModelAtRestRefusesNothing() {
        #expect(Self.model().swipeRefusals == IslandSwipeRefusals())
    }

    @MainActor
    @Test func aWaitingSessionRefusesAnOpenIslandThatKeepsItselfOpenForADecision() {
        let model = Self.model()
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
        model.state = SessionState(sessions: [session])
        model.notchStatus = .opened

        // The setting is off: nothing is held.
        #expect(model.swipeRefusals.blocksDismiss == false)

        model.keepNotchOpenUntilDecision = true
        #expect(model.swipeRefusals.blocksDismiss)

        var recognizer = IslandSwipeRecognizer()
        let facts = IslandScrollFacts(
            isEnabled: true, status: .opened, isInClosedSurface: false, isInExpandedArea: true,
            isLocalEvent: true, refusals: model.swipeRefusals
        )
        #expect(Self.acted(Self.gesture(&recognizer, facts, dy: Self.far)) == nil)
    }

    @MainActor
    @Test func theToursHoldRefusesAnOpenIsland() {
        let model = Self.model()
        model.setTourHoldsIslandOpen(true)

        #expect(model.swipeRefusals.holdsOpenForTour)
        #expect(model.swipeRefusals.hasOpenPicker == false)
    }

    // MARK: Sideways on the pill

    @Test func aSidewaysSwipeOnTheClosedPillHidesWhatItShowsInBothDirections() throws {
        for dx in [Self.far, -Self.far] {
            var recognizer = IslandSwipeRecognizer()
            let outcomes = Self.gesture(&recognizer, Self.facts(status: .closed, onPill: true), dx: dx)

            let outcome = try #require(Self.acted(outcomes))
            #expect(outcome.action == .toggleClosedContent)
            #expect(outcome.suppressesHover == false, "nothing closed, hover has nothing to suppress")
            #expect(outcome.swallows)
            #expect(outcomes.allSatisfy { $0.cancelsHoverOpen }, "a hover open waiting under the fingers is cancelled")
        }
    }

    @Test func aSidewaysSwipeOnTheOpenIslandsPillClosesItAndTogglesTheContent() throws {
        var recognizer = IslandSwipeRecognizer()
        let outcomes = Self.gesture(&recognizer, Self.facts(status: .opened, onPill: true, inExpanded: true), dx: Self.far)

        let outcome = try #require(Self.acted(outcomes))
        #expect(outcome.action == .closeAndToggleClosedContent)
        #expect(outcome.suppressesHover)
        #expect(outcome.swallows)
        #expect(outcomes.allSatisfy { !$0.cancelsHoverOpen }, "only a closed island has a hover open to cancel")
    }

    @Test func aSidewaysSwipeOnTheOpenIslandAwayFromThePillDoesNothing() {
        var recognizer = IslandSwipeRecognizer()
        let outcomes = Self.gesture(&recognizer, Self.facts(status: .opened, inExpanded: true), dx: Self.far)

        #expect(Self.acted(outcomes) == nil)
        #expect(outcomes.allSatisfy { !$0.swallows })
    }

    @Test func aSidewaysSwipeOffTheClosedPillDoesNothing() {
        var recognizer = IslandSwipeRecognizer()
        let outcomes = Self.gesture(&recognizer, Self.facts(status: .closed), dx: Self.far)

        #expect(Self.acted(outcomes) == nil)
        #expect(outcomes.allSatisfy { !$0.swallows })
    }

    @Test func aPoppingIslandIgnoresEverySwipe() {
        var recognizer = IslandSwipeRecognizer()
        #expect(Self.acted(Self.gesture(&recognizer, Self.facts(status: .popping, onPill: true, inExpanded: true), dy: Self.far)) == nil)
        var sideways = IslandSwipeRecognizer()
        #expect(Self.acted(Self.gesture(&sideways, Self.facts(status: .popping, onPill: true, inExpanded: true), dx: Self.far)) == nil)
    }

    // MARK: Off

    @Test func withTheSwipeOffNothingIsFollowedSwallowedOrRecorded() {
        var recognizer = IslandSwipeRecognizer()
        let outcomes = Self.gesture(&recognizer, Self.facts(status: .opened, onPill: true, inExpanded: true, enabled: false), dy: Self.far)

        #expect(outcomes.allSatisfy { $0 == .ignored })
        #expect(recognizer == IslandSwipeRecognizer(), "the recognizer was not even fed")
    }
}

// MARK: - The hidden state

@MainActor
@Suite(.noNewWindows)
struct ClosedContentHiddenTests {
    /// A model on a store held in memory: it reads and writes no real
    /// setting, looks in no real folder, starts no relay, and puts nothing
    /// on screen.
    private static func model(defaults: UserDefaults = MemoryDefaults()) -> AppModel {
        AppModel(
            isNotificationSessionAlreadyFrontmost: { _ in true },
            defaults: defaults
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
        // Something on every side to hide: a running agent and a timer.
        model.nook.timer.start(length: 600)
        defer { model.nook.timer.reset() }
        #expect(model.islandClosedMode == .running)
        #expect(model.islandClosedPillMode == .running)
        #expect(model.closedContentIsHidden == false)
        #expect(model.nookLeftSlotContent != .hidden)
        #expect(model.islandClosedRightSlotContent() != nil)
        #expect(model.nookClosedActivity != nil)
        #expect(model.islandHaloInputs.isRunning)

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

    @Test func aSwipeWhileAnAgentWaitsArmsNothingForWhenTheWaitEnds() {
        let model = Self.model()
        var session = Self.runningSession()
        session.phase = .waitingForApproval
        session.permissionRequest = PermissionRequest(title: "Edit", summary: "x", affectedPath: "/tmp/x")
        model.state = SessionState(sessions: [session])
        #expect(model.islandClosedMode == .waiting)

        model.toggleClosedContentHidden()
        model.toggleClosedContentHidden()

        #expect(model.nook.closedContentHiddenBySwipe == false)
        // The wait ends: the island is not hidden.
        model.state = SessionState(sessions: [Self.runningSession()])
        #expect(model.closedContentIsHidden == false)
    }

    /// The rule `notchOpen` applies. The tests of it open nothing: opening
    /// the island builds a panel, and a test never does that.
    @Test func anIslandOpenedForANotificationBringsTheHiddenContentBack() {
        #expect(IslandPointerRules.openingBringsBackHiddenContent(reason: .notification))
    }

    @Test func anIslandOpenedByHoverClickOrTheBootLeavesTheHiddenContentAlone() {
        #expect(IslandPointerRules.openingBringsBackHiddenContent(reason: .hover) == false)
        #expect(IslandPointerRules.openingBringsBackHiddenContent(reason: .click) == false)
        #expect(IslandPointerRules.openingBringsBackHiddenContent(reason: .boot) == false)
    }

    /// The same rule through `notchOpen` itself. The model is on a store of
    /// its own, which keeps its panel off screen (`putsPanelOnScreen`), and
    /// the suite's trait fails the test if a window appears anyway.
    @Test func openingForANotificationCardThroughTheModelBringsItBack() {
        let model = Self.model()
        model.nook.closedContentHiddenBySwipe = true

        model.notchOpen(reason: .notification, surface: .sessionList())

        #expect(model.nook.closedContentHiddenBySwipe == false)
    }

    @Test func openingByHoverOrClickThroughTheModelAndClosingAgainLeavesItHidden() {
        let model = Self.model()
        model.nook.closedContentHiddenBySwipe = true

        model.notchOpen(reason: .hover)
        model.notchClose()
        model.notchOpen(reason: .click)
        model.notchClose()

        #expect(model.nook.closedContentHiddenBySwipe)
    }

    @Test func turningTheSwipeOffBringsHiddenContentBack() {
        let model = Self.model()
        model.state = SessionState(sessions: [Self.runningSession()])
        model.swipeGesturesEnabled = true
        model.toggleClosedContentHidden()
        #expect(model.closedContentIsHidden)
        #expect(model.islandClosedPillMode == .idle)

        model.swipeGesturesEnabled = false

        #expect(model.nook.closedContentHiddenBySwipe == false)
        #expect(model.closedContentIsHidden == false)
        #expect(model.islandClosedPillMode == .running)
    }

    @Test func theSwipeSettingIsReadFromAndSavedToTheStoreItWasGiven() {
        let defaults = MemoryDefaults()
        #expect(Self.model(defaults: defaults).swipeGesturesEnabled == false)

        defaults.set(true, forKey: IslandSwipeSetting.defaultsKey)
        let model = Self.model(defaults: defaults)
        #expect(model.swipeGesturesEnabled)

        model.swipeGesturesEnabled = false
        #expect(defaults.object(forKey: IslandSwipeSetting.defaultsKey) as? Bool == false)
    }

    @Test func aModelOnAStoreOfItsOwnLooksInNoRealFolderAndStartsNoRelay() {
        let model = Self.model()
        #expect(model.nook.gifURL == nil)
        #expect(model.watchNotificationEnabled == false)
        #expect(model.watchRelay == nil)
    }

    @Test func thePreviewsNeverFollowTheFlag() {
        let model = Self.model()
        let before = model.nook.previewClosedActivity(for: NookDisplayPreferences())
        model.nook.closedContentHiddenBySwipe = true
        let after = model.nook.previewClosedActivity(for: NookDisplayPreferences())
        #expect(before == after)
    }
}


