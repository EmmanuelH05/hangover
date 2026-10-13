import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

// Edge cases for the swipe (D46) that the first tests of it do not reach: a
// gesture that turns around, one that ends exactly on a limit, the wheel's
// gap on both sides of its limit, two gestures that overlap, a gesture that
// crosses the island's edge, and the whole table of what the rule answers.

// MARK: - The recognizer

struct EdgeCaseSwipeRecognizerTests {
    private static let threshold = IslandSwipeRecognizer.threshold
    private static let wheelGap = IslandSwipeRecognizer.wheelGap

    private static func sample(
        dx: Double = 0,
        dy: Double = 0,
        phase: IslandScrollSample.Phase = .changed,
        momentum: Bool = false,
        at time: TimeInterval
    ) -> IslandScrollSample {
        IslandScrollSample(dx: dx, dy: dy, phase: phase, isMomentum: momentum, timestamp: time)
    }

    /// Feeds a list of (dx, dy) steps after a zero begin, 10 ms apart, and
    /// returns what each step answered.
    private static func feed(
        _ recognizer: inout IslandSwipeRecognizer,
        steps: [(dx: Double, dy: Double)],
        begin: Bool = true
    ) -> [IslandSwipeDirection?] {
        if begin { _ = recognizer.feed(sample(phase: .began, at: 0)) }
        return steps.enumerated().map { index, step in
            recognizer.feed(sample(dx: step.dx, dy: step.dy, at: Double(index + 1) * 0.01))
        }
    }

    // MARK: A gesture that turns around

    /// The sums are net: fingers that go up 30 and come back down 30 have
    /// travelled nowhere, and a swipe that starts from there needs the whole
    /// threshold again.
    @Test func aGestureThatTurnsAroundCountsOnlyTheNetTravel() {
        var recognizer = IslandSwipeRecognizer()
        let answers = Self.feed(&recognizer, steps: [(0, 30), (0, -30), (0, 30), (0, 5)])
        #expect(answers.allSatisfy { $0 == nil })
        #expect(recognizer.hasFired == false)

        // 35 points up in all by now. Six more points up pass the limit.
        #expect(recognizer.feed(Self.sample(dy: 6, at: 0.1)) == .up)
    }

    @Test func aGestureThatTurnsAroundFiresTheWayItEndsUp() {
        var recognizer = IslandSwipeRecognizer()
        // Up 20, then down 60: the net is 40 down.
        let answers = Self.feed(&recognizer, steps: [(0, 20), (0, -30), (0, -30)])
        #expect(answers == [nil, nil, .down])
    }

    @Test func aGestureThatFiredIsDeafToTheTurnAround() {
        var recognizer = IslandSwipeRecognizer()
        let up = Self.feed(&recognizer, steps: [(0, 40)])
        #expect(up == [.up])
        // The fingers come all the way back and go on down. One gesture, one answer.
        let more = Self.feed(&recognizer, steps: [(0, -80), (0, -80), (0, -80)], begin: false)
        #expect(more.allSatisfy { $0 == nil })
    }

    @Test func aSidewaysGestureThatTurnsAroundFiresOnlyOnceForTheDirectionItReachedFirst() {
        var recognizer = IslandSwipeRecognizer()
        let answers = Self.feed(&recognizer, steps: [(40, 0), (-200, 0), (200, 0), (-200, 0)])
        #expect(answers == [.right, nil, nil, nil])
    }

    // MARK: Exactly on a limit

    @Test func theThresholdItselfFiresAndTheLastRepresentableValueBelowItDoesNot() {
        var onIt = IslandSwipeRecognizer()
        #expect(onIt.feed(Self.sample(dy: Self.threshold, phase: .began, at: 0)) == .up)

        var under = IslandSwipeRecognizer()
        let justUnder = Self.threshold.nextDown
        #expect(under.feed(Self.sample(dy: justUnder, phase: .began, at: 0)) == nil)
        // One more point of travel in any amount finishes it.
        #expect(under.feed(Self.sample(dy: 0.001, at: 0.01)) == .up)
    }

    @Test(arguments: [
        (dx: 0.0, dy: 36.0, expected: IslandSwipeDirection.up),
        (dx: 0.0, dy: -36.0, expected: .down),
        (dx: 36.0, dy: 0.0, expected: .right),
        (dx: -36.0, dy: 0.0, expected: .left),
    ])
    func eachDirectionFiresOnTheThresholdExactly(dx: Double, dy: Double, expected: IslandSwipeDirection) {
        var recognizer = IslandSwipeRecognizer()
        #expect(recognizer.feed(Self.sample(dx: dx, dy: dy, phase: .began, at: 0)) == expected)
    }

    /// Travel split into many small steps adds up to the same answer as one
    /// big step, whichever way it is cut.
    @Test(arguments: [1, 2, 3, 4, 6, 9, 12, 18, 36])
    func theThresholdIsReachedAtTheSameTotalHoweverTheTravelIsCut(parts: Int) {
        var recognizer = IslandSwipeRecognizer()
        let step = Self.threshold / Double(parts)
        let answers = Self.feed(&recognizer, steps: Array(repeating: (0.0, step), count: parts))
        #expect(answers.last == .up)
        #expect(answers.dropLast().allSatisfy { $0 == nil })
    }

    @Test func aGestureCanFireOnItsEndSampleAlone() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(phase: .began, at: 0))
        #expect(recognizer.feed(Self.sample(dy: 40, phase: .ended, at: 0.01)) == .up)
        // After the end, a change that has no begin is nobody's.
        #expect(recognizer.feed(Self.sample(dy: 400, at: 0.02)) == nil)
    }

    // MARK: Diagonal travel at the dominance ratio

    @Test func theMainAxisMustBeAtLeastTwiceTheOtherAndTwiceExactlyCounts() {
        let dominance = IslandSwipeRecognizer.dominance
        let main = 40.0

        var exact = IslandSwipeRecognizer()
        #expect(exact.feed(Self.sample(dx: main / dominance, dy: main, phase: .began, at: 0)) == .up)

        var over = IslandSwipeRecognizer()
        #expect(over.feed(Self.sample(dx: (main / dominance).nextUp, dy: main, phase: .began, at: 0)) == nil)

        var sideways = IslandSwipeRecognizer()
        #expect(sideways.feed(Self.sample(dx: main, dy: main / dominance, phase: .began, at: 0)) == .right)
        var sidewaysOver = IslandSwipeRecognizer()
        #expect(sidewaysOver.feed(Self.sample(dx: main, dy: (main / dominance).nextUp, phase: .began, at: 0)) == nil)
    }

    /// A drag that starts diagonal and straightens out becomes a swipe as
    /// soon as the main axis pulls ahead, and the cross travel before that
    /// still counts against it.
    @Test func aDiagonalStartStraightensIntoASwipeOnceTheMainAxisPullsAhead() {
        var recognizer = IslandSwipeRecognizer()
        let answers = Self.feed(&recognizer, steps: [(30, 30), (0, 20), (0, 20), (0, 11)])
        // After the third step it is 70 up against 30 sideways, which is
        // better than two to one.
        #expect(answers == [nil, nil, .up, nil])
    }

    @Test func aWobbleThatKeepsTheCrossTravelBigNeverFires() {
        var recognizer = IslandSwipeRecognizer()
        // 100 up and 60 sideways in the same direction never reaches two to one.
        let answers = Self.feed(&recognizer, steps: [(20, 33), (20, 33), (20, 34)])
        #expect(answers.allSatisfy { $0 == nil })
        // Once the sideways travel is walked back the swipe is clear.
        #expect(recognizer.feed(Self.sample(dx: -20, at: 0.1)) == .up)
    }

    // MARK: Momentum

    @Test func momentumBetweenRealSamplesAddsNothing() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(phase: .began, at: 0))
        #expect(recognizer.feed(Self.sample(dy: 20, at: 0.01)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 500, momentum: true, at: 0.02)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 15, at: 0.03)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 1, at: 0.04)) == .up)
    }

    /// Fingers lifted before the island: only the tail arrives. Nothing in a
    /// tail starts a gesture, with or without a phase.
    @Test(arguments: [IslandScrollSample.Phase.none, .changed, .began, .ended])
    func aTailThatNeverHadItsFingersHereNeverFires(phase: IslandScrollSample.Phase) {
        var recognizer = IslandSwipeRecognizer()
        for index in 0..<30 {
            #expect(recognizer.feed(Self.sample(dx: 40, dy: 40, phase: phase, momentum: true, at: Double(index) * 0.02)) == nil)
        }
        #expect(recognizer == IslandSwipeRecognizer(), "the tail left no trace")
    }

    @Test func aTailDoesNotHoldHoverOpenBackAfterTheFingersLift() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(dy: 4, phase: .began, at: 10))
        _ = recognizer.feed(Self.sample(dy: 4, phase: .ended, at: 10.1))
        for index in 1...20 {
            _ = recognizer.feed(Self.sample(dy: 9, momentum: true, at: 10.1 + Double(index) * 0.05))
        }
        // A second after the lift the tail is still rolling, and the pill is free.
        #expect(recognizer.isInProgress(at: 11.1) == false)
    }

    @Test func aSwipeMadeRightAfterATailBeganIsCountedFromZero() {
        var recognizer = IslandSwipeRecognizer()
        for index in 0..<10 {
            _ = recognizer.feed(Self.sample(dy: 40, momentum: true, at: Double(index) * 0.01))
        }
        _ = recognizer.feed(Self.sample(phase: .began, at: 0.2))
        #expect(recognizer.feed(Self.sample(dy: 20, at: 0.21)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 20, at: 0.22)) == .up)
    }

    // MARK: A wheel and its gap

    @Test func aWheelGapOfExactlyTheLimitIsStillOneGestureAndJustOverIsTwo() {
        var together = IslandSwipeRecognizer()
        #expect(together.feed(Self.sample(dy: 20, phase: .none, at: 0)) == nil)
        #expect(together.feed(Self.sample(dy: 20, phase: .none, at: Self.wheelGap)) == .up)

        var apart = IslandSwipeRecognizer()
        #expect(apart.feed(Self.sample(dy: 20, phase: .none, at: 0)) == nil)
        #expect(apart.feed(Self.sample(dy: 20, phase: .none, at: Self.wheelGap.nextUp)) == nil)
        #expect(apart.hasFired == false)
    }

    /// The recognizer decides a wheel gesture is over by one rule and the
    /// pill decides a scroll is under way by another. They must agree about
    /// the same instant, or hover could open under a wheel that is still going.
    @Test func theRecognizerAndTheHoverWaitAgreeWhereTheWheelGapEnds() {
        for offset in [0.0, Self.wheelGap, Self.wheelGap.nextUp, Self.wheelGap * 2] {
            var recognizer = IslandSwipeRecognizer()
            _ = recognizer.feed(Self.sample(dy: 20, phase: .none, at: 0))
            let isInProgress = recognizer.isInProgress(at: offset)
            // A sample at that instant continues the gesture exactly when
            // the pill still counts it as under way.
            let fired = recognizer.feed(Self.sample(dy: 20, phase: .none, at: offset)) == .up
            #expect(isInProgress == fired, "offset \(offset)")
        }
    }

    @Test func aWheelThatNeverPausesForTheGapIsOneGestureHoweverLongItRuns() {
        var recognizer = IslandSwipeRecognizer()
        var fires = 0
        for index in 0..<200 {
            // Each notch comes 0.2 s after the one before.
            if recognizer.feed(Self.sample(dy: 12, phase: .none, at: Double(index) * 0.2)) != nil { fires += 1 }
        }
        #expect(fires == 1)
    }

    @Test func aWheelThatPausesLongerThanTheGapBetweenEveryNotchNeverAddsUp() {
        var recognizer = IslandSwipeRecognizer()
        for index in 0..<50 {
            #expect(recognizer.feed(Self.sample(dy: 24, phase: .none, at: Double(index) * 0.5)) == nil)
        }
    }

    /// A trackpad gesture is bounded by its phases and not by time. Fingers
    /// that rest on the pad for a second and then move on are one gesture.
    @Test func aTrackpadPauseLongerThanTheWheelGapDoesNotSplitTheGesture() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(phase: .began, at: 0))
        #expect(recognizer.feed(Self.sample(dy: 20, at: 0.1)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 20, at: 2.0)) == .up)
    }

    @Test func aWheelNotchAfterATrackpadGestureEndedStartsFresh() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(phase: .began, at: 0))
        _ = recognizer.feed(Self.sample(dy: 30, at: 0.01))
        _ = recognizer.feed(Self.sample(dy: 0, phase: .ended, at: 0.02))
        // 30 points are already in the sum, but the gesture is over.
        #expect(recognizer.feed(Self.sample(dy: 12, phase: .none, at: 0.05)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 12, phase: .none, at: 0.06)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 12, phase: .none, at: 0.07)) == .up)
    }

    // MARK: Two gestures that overlap

    @Test func aSecondGestureThatBeginsBeforeTheFirstEndedStartsFromZero() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(phase: .began, at: 0))
        #expect(recognizer.feed(Self.sample(dy: 30, at: 0.01)) == nil)

        // The pad reports a new begin with no end for the first.
        #expect(recognizer.feed(Self.sample(phase: .began, at: 0.02)) == nil)
        #expect(recognizer.feed(Self.sample(dy: 30, at: 0.03)) == nil, "30 and 30 from two gestures do not add")
        #expect(recognizer.feed(Self.sample(dy: 6, at: 0.04)) == .up)
    }

    @Test func aSecondGestureThatBeginsAfterAFiredOneIsReadyAndNoLongerConsumed() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(phase: .began, at: 0))
        #expect(recognizer.feed(Self.sample(dy: 40, at: 0.01)) == .up)
        recognizer.markConsumed()

        _ = recognizer.feed(Self.sample(phase: .began, at: 0.02))
        #expect(recognizer.isConsumed == false)
        #expect(recognizer.hasFired == false)
        #expect(recognizer.feed(Self.sample(dx: -40, at: 0.03)) == .left)
    }

    /// The first gesture's end arrives after the second one began. The end
    /// closes the second, which is the best the pad's phases can say.
    @Test func aLateEndOfTheFirstGestureEndsTheSecondAndNothingAfterItCounts() {
        var recognizer = IslandSwipeRecognizer()
        _ = recognizer.feed(Self.sample(phase: .began, at: 0))
        _ = recognizer.feed(Self.sample(phase: .began, at: 0.01))
        _ = recognizer.feed(Self.sample(dy: 20, at: 0.02))
        _ = recognizer.feed(Self.sample(phase: .ended, at: 0.03))
        #expect(recognizer.feed(Self.sample(dy: 100, at: 0.04)) == nil)
    }

    // MARK: Zero and silly input

    @Test func aGestureOfZerosNeverFiresAndTwoBeginsInARowChangeNothing() {
        var recognizer = IslandSwipeRecognizer()
        for index in 0..<100 {
            #expect(recognizer.feed(Self.sample(phase: index.isMultiple(of: 40) ? .began : .changed, at: Double(index) * 0.01)) == nil)
        }
        #expect(recognizer.hasFired == false)
    }

    @Test func oneHugeSampleFiresOnceAndTheHugeTailOfItDoesNot() {
        var recognizer = IslandSwipeRecognizer()
        #expect(recognizer.feed(Self.sample(dy: 100_000, phase: .began, at: 0)) == .up)
        #expect(recognizer.feed(Self.sample(dy: 100_000, at: 0.01)) == nil)
    }

    /// `mayBegin` and `stationary` are not the start of a gesture. A pad
    /// that only reports touching fingers must not arm a swipe.
    @Test(arguments: [NSEvent.Phase.mayBegin, .stationary])
    func fingersThatOnlyRestOnThePadStartNothing(phase: NSEvent.Phase) {
        let sample = IslandScrollSample.make(
            scrollingDeltaX: 0, scrollingDeltaY: -400,
            hasPreciseScrollingDeltas: true, isDirectionInvertedFromDevice: true,
            phase: phase, momentumPhase: [], timestamp: 1
        )
        var recognizer = IslandSwipeRecognizer()
        #expect(recognizer.feed(sample) == nil)
        #expect(recognizer.hasFired == false)
        // Nothing that follows without a begin is a swipe either.
        #expect(recognizer.feed(Self.sample(dy: 400, at: 1.01)) == nil)
    }

    @Test func theLastEventOfATailIsStillATail() {
        let sample = IslandScrollSample.make(
            scrollingDeltaX: 0, scrollingDeltaY: -400,
            hasPreciseScrollingDeltas: true, isDirectionInvertedFromDevice: true,
            phase: [], momentumPhase: .ended, timestamp: 1
        )
        #expect(sample.isMomentum)
        var recognizer = IslandSwipeRecognizer()
        #expect(recognizer.feed(sample) == nil)
    }
}

// MARK: - What the rule answers, in full

/// Every status, direction, place and refusal at once, checked against the
/// rule written the other way round: by what each answer needs.
struct EdgeCaseSwipeRuleTableTests {
    private struct Case: CustomStringConvertible {
        var context: IslandSwipeContext
        var description: String {
            "\(context.status) \(context.direction) pill:\(context.isInClosedSurface) area:\(context.isInExpandedArea)"
                + " list:\(context.isOverScrollableContent) blocks:\(context.blocksDismiss)"
                + " picker:\(context.hasOpenPicker) tour:\(context.holdsOpenForTour)"
        }
    }

    /// Every combination the controller can build. On a closed island the
    /// expanded area is the pill. On an open one the pill lies inside it.
    private static let cases: [Case] = {
        var all: [Case] = []
        let bools = [false, true]
        for status in [NotchStatus.closed, .opened, .popping] {
            for direction in [IslandSwipeDirection.up, .down, .left, .right] {
                for onPill in bools {
                    for inArea in bools {
                        if status == .opened, onPill, !inArea { continue }
                        if status != .opened, onPill != inArea { continue }
                        for list in bools {
                            for blocks in bools {
                                for picker in bools {
                                    for tour in bools {
                                        all.append(Case(context: IslandSwipeContext(
                                            status: status, direction: direction,
                                            isInClosedSurface: onPill, isInExpandedArea: inArea,
                                            isOverScrollableContent: list, blocksDismiss: blocks,
                                            hasOpenPicker: picker, holdsOpenForTour: tour
                                        )))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return all
    }()

    private static func isSideways(_ direction: IslandSwipeDirection) -> Bool {
        direction == .left || direction == .right
    }

    @Test func theTableHoldsEveryCombinationTheControllerCanBuild() {
        // Each of the 4 directions with 16 choices of list and refusals, in
        // 2 places on a closed island, 2 on a popping one and 3 on an open one.
        #expect(Self.cases.count == 4 * 16 * (2 + 2 + 3))
    }

    @Test func aPoppingIslandAnswersNothingToAnything() {
        for entry in Self.cases where entry.context.status == .popping {
            #expect(IslandPointerRules.swipeAction(entry.context) == .none, "\(entry)")
        }
    }

    @Test func aCloseNeedsAnOpenIslandAnUpSwipeInsideAndNothingHoldingItOrScrolling() {
        for entry in Self.cases {
            let context = entry.context
            let answer = IslandPointerRules.swipeAction(context)
            let isCloseable = context.status == .opened
                && context.direction == .up
                && context.isInExpandedArea
                && !context.isOverScrollableContent
                && !context.blocksDismiss && !context.hasOpenPicker && !context.holdsOpenForTour
            #expect((answer == .close) == isCloseable, "\(entry)")
        }
    }

    @Test func aCloseWithAHideNeedsAnOpenIslandASidewaysSwipeOnThePillAndNothingHoldingIt() {
        for entry in Self.cases {
            let context = entry.context
            let answer = IslandPointerRules.swipeAction(context)
            let applies = context.status == .opened
                && Self.isSideways(context.direction)
                && context.isInClosedSurface
                && !context.blocksDismiss && !context.hasOpenPicker && !context.holdsOpenForTour
            #expect((answer == .closeAndToggleClosedContent) == applies, "\(entry)")
        }
    }

    /// A list under the pointer never blocks a sideways swipe: a list does
    /// not scroll sideways for the island's purposes.
    @Test func aListUnderThePointerOnlyEverHoldsBackAnUpSwipe() {
        for entry in Self.cases where entry.context.isOverScrollableContent {
            var without = entry.context
            without.isOverScrollableContent = false
            let withList = IslandPointerRules.swipeAction(entry.context)
            let withoutList = IslandPointerRules.swipeAction(without)
            if withList != withoutList {
                #expect(entry.context.direction == .up, "\(entry)")
                #expect(withoutList == .close, "\(entry)")
                #expect(withList == .none, "\(entry)")
            }
        }
    }

    @Test func aHideOnTheClosedIslandNeedsASidewaysSwipeOnThePillAndIgnoresEveryRefusal() {
        for entry in Self.cases {
            let context = entry.context
            let answer = IslandPointerRules.swipeAction(context)
            let applies = context.status == .closed && Self.isSideways(context.direction) && context.isInClosedSurface
            #expect((answer == .toggleClosedContent) == applies, "\(entry)")
        }
    }

    @Test func leftAndRightAreAlwaysTheSameAnswer() {
        for entry in Self.cases where entry.context.direction == .left {
            var mirrored = entry.context
            mirrored.direction = .right
            #expect(IslandPointerRules.swipeAction(entry.context) == IslandPointerRules.swipeAction(mirrored), "\(entry)")
        }
    }

    @Test func downIsNeverAnythingOnAnyIsland() {
        for entry in Self.cases where entry.context.direction == .down {
            #expect(IslandPointerRules.swipeAction(entry.context) == .none, "\(entry)")
        }
    }

    @Test func everyActionThatClosesTheIslandAsksHoverToWait() {
        for action in [IslandSwipeAction.close, .closeAndToggleClosedContent] {
            #expect(IslandScrollOutcome(action: action, swallows: true, cancelsHoverOpen: false).suppressesHover)
        }
        for action in [IslandSwipeAction.toggleClosedContent, .none] {
            #expect(IslandScrollOutcome(action: action, swallows: true, cancelsHoverOpen: false).suppressesHover == false)
        }
    }
}

// MARK: - The scroll step across the island's edge

/// What the panel controller does with each scroll event, driven as the pure
/// step with the facts changing under one gesture.
struct EdgeCaseScrollStepTests {
    private static func facts(
        status: NotchStatus,
        onPill: Bool = false,
        inArea: Bool = false,
        local: Bool = true,
        refusals: IslandSwipeRefusals = IslandSwipeRefusals()
    ) -> IslandScrollFacts {
        IslandScrollFacts(
            isEnabled: true, status: status, isInClosedSurface: onPill, isInExpandedArea: inArea,
            isLocalEvent: local, refusals: refusals
        )
    }

    private static func sample(
        dx: Double = 0, dy: Double = 0, phase: IslandScrollSample.Phase = .changed, at time: TimeInterval
    ) -> IslandScrollSample {
        IslandScrollSample(dx: dx, dy: dy, phase: phase, isMomentum: false, timestamp: time)
    }

    private static func step(
        _ recognizer: inout IslandSwipeRecognizer,
        _ sample: IslandScrollSample,
        _ facts: IslandScrollFacts,
        overList: @escaping (IslandSwipeDirection) -> Bool = { _ in false }
    ) -> IslandScrollOutcome {
        IslandPointerRules.scrollStep(recognizer: &recognizer, sample: sample, facts: facts, isOverScrollableContent: overList)
    }

    private static let onPill = facts(status: .closed, onPill: true, inArea: true)
    private static let offIsland = facts(status: .closed)

    // MARK: Across the edge

    @Test func aGestureThatBeganOnThePillAndLeftItIsForgottenEvenWhenItComesBack() {
        var recognizer = IslandSwipeRecognizer()
        _ = Self.step(&recognizer, Self.sample(phase: .began, at: 0), Self.onPill)
        _ = Self.step(&recognizer, Self.sample(dx: 20, at: 0.01), Self.onPill)

        let away = Self.step(&recognizer, Self.sample(dx: 5, at: 0.02), Self.offIsland)
        #expect(away == IslandScrollOutcome(action: .none, swallows: false, cancelsHoverOpen: false))
        #expect(recognizer == IslandSwipeRecognizer(), "leaving forgot the 20 points")

        // Back on the pill, the rest of that gesture is nobody's.
        for index in 3..<10 {
            let outcome = Self.step(&recognizer, Self.sample(dx: 20, at: Double(index) * 0.01), Self.onPill)
            #expect(outcome.action == .none)
        }
    }

    @Test func aTrackpadGestureThatBeganOffTheIslandIsNotASwipeWhereverItGoesAfterwards() {
        var recognizer = IslandSwipeRecognizer()
        _ = Self.step(&recognizer, Self.sample(phase: .began, at: 0), Self.offIsland)
        _ = Self.step(&recognizer, Self.sample(dx: 10, at: 0.01), Self.offIsland)
        for index in 2..<12 {
            let outcome = Self.step(&recognizer, Self.sample(dx: 20, at: Double(index) * 0.01), Self.onPill)
            #expect(outcome.action == .none)
        }
    }

    /// A wheel has no begin. One rolled onto the island starts there.
    @Test func aWheelRolledOntoThePillFromOutsideStartsItsGestureOnThePill() {
        var recognizer = IslandSwipeRecognizer()
        _ = Self.step(&recognizer, Self.sample(dx: 12, phase: .none, at: 0), Self.offIsland)
        var actions: [IslandSwipeAction] = []
        for index in 1...3 {
            actions.append(Self.step(&recognizer, Self.sample(dx: 12, phase: .none, at: Double(index) * 0.05), Self.onPill).action)
        }
        #expect(actions == [.none, .none, .toggleClosedContent], "36 points on the pill, the first notch was off it")
    }

    @Test func aGestureTheIslandActedOnStaysItsWhenThePointerLeavesAndComesBackAndNeverActsTwice() {
        var recognizer = IslandSwipeRecognizer()
        _ = Self.step(&recognizer, Self.sample(phase: .began, at: 0), Self.onPill)
        let acted = Self.step(&recognizer, Self.sample(dx: 40, at: 0.01), Self.onPill)
        #expect(acted.action == .toggleClosedContent)

        let gone = Self.step(&recognizer, Self.sample(dx: 40, at: 0.02), Self.offIsland)
        let back = Self.step(&recognizer, Self.sample(dx: 40, at: 0.03), Self.onPill)
        let again = Self.step(&recognizer, Self.sample(dx: -200, at: 0.04), Self.onPill)
        #expect(gone.swallows && back.swallows && again.swallows)
        #expect([gone, back, again].allSatisfy { $0.action == .none })
    }

    // MARK: The closed island hears the global monitor

    /// The closed panel passes the mouse through. A swipe on the closed pill
    /// reaches the app through the global monitor and never the local one.
    @Test func aSwipeOnTheClosedPillActsFromTheGlobalMonitorAndSwallowsNothing() {
        var recognizer = IslandSwipeRecognizer()
        let global = Self.facts(status: .closed, onPill: true, inArea: true, local: false)
        var outcomes = [Self.step(&recognizer, Self.sample(phase: .began, at: 0), global)]
        for index in 1...4 {
            outcomes.append(Self.step(&recognizer, Self.sample(dx: 10, at: Double(index) * 0.01), global))
        }

        #expect(outcomes.filter { $0.action == .toggleClosedContent }.count == 1)
        #expect(outcomes.allSatisfy { !$0.swallows })
        #expect(outcomes.allSatisfy { $0.cancelsHoverOpen })
    }

    // MARK: The list under the pointer is asked about once

    @Test func theListIsAskedOnceForAGestureThatFiredAndNotAtAllForOneThatDidNot() {
        let open = Self.facts(status: .opened, inArea: true)

        var fired = IslandSwipeRecognizer()
        var askedFired = 0
        _ = Self.step(&fired, Self.sample(phase: .began, at: 0), open) { _ in askedFired += 1; return false }
        for index in 1...100 {
            _ = Self.step(&fired, Self.sample(dy: 2, at: Double(index) * 0.01), open) { _ in askedFired += 1; return false }
        }
        #expect(askedFired == 1)

        var short = IslandSwipeRecognizer()
        var askedShort = 0
        _ = Self.step(&short, Self.sample(phase: .began, at: 0), open) { _ in askedShort += 1; return false }
        for index in 1...10 {
            _ = Self.step(&short, Self.sample(dy: 2, at: Double(index) * 0.01), open) { _ in askedShort += 1; return false }
        }
        #expect(askedShort == 0)
    }

    @Test func aClosedIslandNeverAsksAboutAListEvenForALocalEvent() {
        var recognizer = IslandSwipeRecognizer()
        var asked = 0
        let facts = Self.facts(status: .closed, onPill: true, inArea: true, local: true)
        _ = Self.step(&recognizer, Self.sample(phase: .began, at: 0), facts) { _ in asked += 1; return false }
        _ = Self.step(&recognizer, Self.sample(dx: 40, at: 0.01), facts) { _ in asked += 1; return false }
        #expect(asked == 0)
    }

    /// A swipe up that a list took is spent. If the list reaches its end a
    /// moment later in the same touch, the island does not close on the tail.
    @Test func aSwipeUpThatAListTookIsNotRetriedWhenTheListRunsOutInTheSameGesture() {
        var recognizer = IslandSwipeRecognizer()
        let open = Self.facts(status: .opened, inArea: true)
        var listCanTravel = true
        _ = Self.step(&recognizer, Self.sample(phase: .began, at: 0), open) { _ in listCanTravel }
        let first = Self.step(&recognizer, Self.sample(dy: 40, at: 0.01), open) { _ in listCanTravel }
        #expect(first.action == .none)

        listCanTravel = false
        for index in 2..<20 {
            let outcome = Self.step(&recognizer, Self.sample(dy: 20, at: Double(index) * 0.01), open) { _ in listCanTravel }
            #expect(outcome.action == .none)
            #expect(outcome.swallows == false)
        }
    }

    // MARK: The status changes under the gesture

    @Test func aSwipeThatPassesItsLimitWhileTheIslandPopsIsLostForTheRestOfThatGesture() {
        var recognizer = IslandSwipeRecognizer()
        _ = Self.step(&recognizer, Self.sample(phase: .began, at: 0), Self.onPill)
        let popping = Self.facts(status: .popping, onPill: true, inArea: true)
        #expect(Self.step(&recognizer, Self.sample(dx: 40, at: 0.01), popping).action == .none)

        // The pop is over, and more of the same swipe arrives.
        for index in 2..<10 {
            #expect(Self.step(&recognizer, Self.sample(dx: 40, at: Double(index) * 0.01), Self.onPill).action == .none)
        }
        // A new gesture works.
        _ = Self.step(&recognizer, Self.sample(phase: .ended, at: 0.2), Self.onPill)
        _ = Self.step(&recognizer, Self.sample(phase: .began, at: 1), Self.onPill)
        #expect(Self.step(&recognizer, Self.sample(dx: 40, at: 1.01), Self.onPill).action == .toggleClosedContent)
    }

    @Test func aRefusalThatAppearsBeforeTheLimitIsPassedHoldsTheSwipeBack() {
        var recognizer = IslandSwipeRecognizer()
        let free = Self.facts(status: .opened, onPill: true, inArea: true)
        let held = Self.facts(
            status: .opened, onPill: true, inArea: true,
            refusals: IslandSwipeRefusals(blocksDismiss: true)
        )
        _ = Self.step(&recognizer, Self.sample(phase: .began, at: 0), free)
        _ = Self.step(&recognizer, Self.sample(dx: 20, at: 0.01), free)
        let outcome = Self.step(&recognizer, Self.sample(dx: 20, at: 0.02), held)
        #expect(outcome.action == .none)
        #expect(outcome.swallows == false)
        #expect(recognizer.isConsumed == false)
    }
}

// MARK: - The scroll view rects

struct EdgeCaseScrollRectTests {
    private static let slack = IslandScrollContent.scrollableSlack

    @Test func aVisibleRectThatStopsJustMoreThanTheSlackShortOfTheEndCanStillTravel() {
        let document = CGRect(x: 0, y: 0, width: 200, height: 400)
        let atStartFlipped = CGRect(x: 0, y: 0, width: 200, height: 400 - Self.slack)
        let atStartFlippedMore = CGRect(x: 0, y: 0, width: 200, height: 400 - Self.slack - 0.01)
        #expect(IslandScrollContent.canTravel(.towardEnd, visible: atStartFlipped, document: document, isFlipped: true) == false)
        #expect(IslandScrollContent.canTravel(.towardEnd, visible: atStartFlippedMore, document: document, isFlipped: true))

        // Unflipped, the end is at low y.
        let atStartUnflipped = CGRect(x: 0, y: Self.slack, width: 200, height: 400 - Self.slack)
        let atStartUnflippedMore = CGRect(x: 0, y: Self.slack + 0.01, width: 200, height: 400 - Self.slack - 0.01)
        #expect(IslandScrollContent.canTravel(.towardEnd, visible: atStartUnflipped, document: document, isFlipped: false) == false)
        #expect(IslandScrollContent.canTravel(.towardEnd, visible: atStartUnflippedMore, document: document, isFlipped: false))
    }

    /// A document whose bounds do not start at the origin: the hidden part is
    /// measured from the document's own edge.
    @Test func aDocumentWithAnOffsetOriginIsMeasuredFromItsOwnEdges() {
        let document = CGRect(x: 0, y: -50, width: 200, height: 400)
        let top = CGRect(x: 0, y: -50, width: 200, height: 100)
        let bottom = CGRect(x: 0, y: 250, width: 200, height: 100)
        #expect(IslandScrollContent.canTravel(.towardEnd, visible: top, document: document, isFlipped: true))
        #expect(!IslandScrollContent.canTravel(.towardStart, visible: top, document: document, isFlipped: true))
        #expect(!IslandScrollContent.canTravel(.towardEnd, visible: bottom, document: document, isFlipped: true))
        #expect(IslandScrollContent.canTravel(.towardStart, visible: bottom, document: document, isFlipped: true))
    }

    @Test func aVisibleRectLargerThanTheDocumentTravelsNowhere() {
        let document = CGRect(x: 0, y: 0, width: 200, height: 80)
        let visible = CGRect(x: 0, y: -10, width: 200, height: 100)
        for isFlipped in [false, true] {
            for travel in [IslandScrollTravel.towardStart, .towardEnd] {
                #expect(!IslandScrollContent.canTravel(travel, visible: visible, document: document, isFlipped: isFlipped))
            }
        }
    }
}

// MARK: - Scroll views as views

@MainActor
struct EdgeCaseScrollViewWalkTests {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private static func tallScrollView(in container: NSView, frame: NSRect) -> NSScrollView {
        let scrollView = NSScrollView(frame: frame)
        scrollView.documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: frame.width, height: 400))
        container.addSubview(scrollView)
        return scrollView
    }

    /// Only height matters: a document wider than the view but no taller has
    /// nothing a swipe up could move.
    @Test func aDocumentThatIsOnlyWiderDoesNotHoldAnUpSwipe() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        let inner = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        scrollView.documentView?.addSubview(inner)

        #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardEnd) == false)
        #expect(IslandScrollContent.isScrollable(from: inner, travel: .towardStart) == false)
    }

    @Test func theNearestScrollViewThatCannotTravelDoesNotHideAnOuterOneThatCan() {
        let outer = tallOuter()
        let inner = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        inner.documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let leaf = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        inner.documentView?.addSubview(leaf)
        outer.documentView?.addSubview(inner)

        #expect(IslandScrollContent.isScrollable(from: leaf, travel: .towardEnd))
    }

    private func tallOuter() -> NSScrollView {
        let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        outer.documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 100, height: 400))
        return outer
    }

    @Test func aPointOutsideEveryScrollViewFindsNoneEvenWhenSomeAreInTheContainer() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        _ = Self.tallScrollView(in: container, frame: NSRect(x: 10, y: 10, width: 100, height: 100))
        _ = Self.tallScrollView(in: container, frame: NSRect(x: 200, y: 200, width: 100, height: 100))

        let between = NSPoint(x: 150, y: 150)
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: between, travel: .towardEnd) == false)
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: NSPoint(x: 250, y: 250), travel: .towardEnd))
    }

    @Test func aPointJustOutsideAScrollViewsEdgeFindsNothing() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        _ = Self.tallScrollView(in: container, frame: NSRect(x: 10, y: 10, width: 100, height: 100))

        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: NSPoint(x: 10, y: 10), travel: .towardEnd))
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: NSPoint(x: 9.9, y: 50), travel: .towardEnd) == false)
        #expect(IslandScrollContent.isScrollable(from: container, windowPoint: NSPoint(x: 110.5, y: 50), travel: .towardEnd) == false)
    }

    /// A scroll view that is hidden cannot be scrolled by anyone. A swipe up
    /// over it belongs to the island.
    @Test func aHiddenScrollViewUnderThePointerDoesNotHoldASwipeBack() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let scrollView = Self.tallScrollView(in: container, frame: NSRect(x: 10, y: 10, width: 100, height: 100))
        scrollView.isHidden = true

        let isHeld = IslandScrollContent.isScrollable(from: container, windowPoint: NSPoint(x: 50, y: 50), travel: .towardEnd)
        #expect(isHeld == false)
    }
}
