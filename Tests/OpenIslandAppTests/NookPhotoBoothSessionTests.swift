import Foundation
import Testing
@testable import OpenIslandApp

/// The booth's session as a plain value, moved by hand. No camera and no
/// real clock.
@Suite(.serialized, .oneStripAtATime)
struct NookPhotoBoothSessionTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Moves a session to its end, answering the camera and the composer
    /// at once, with `step` seconds between looks at the clock.
    private static func run(
        _ plan: NookPhotoBoothPlan,
        step: TimeInterval
    ) -> (effects: [NookPhotoBoothEffect], phases: [NookPhotoBoothPhase]) {
        var now = start
        var session = NookPhotoBoothSession(plan: plan, at: now)
        var effects: [NookPhotoBoothEffect] = []
        var phases = [session.phase]
        var turns = 0
        while session.phase != .done, turns < 10_000 {
            turns += 1
            now = now.addingTimeInterval(step)
            let produced = session.advance(to: now)
            effects += produced
            if phases.last != session.phase { phases.append(session.phase) }
            for effect in produced {
                switch effect {
                case .capture: session.pictureArrived(at: now)
                case .compose: session.stripReady(at: now)
                case .showNumber: break
                }
                if phases.last != session.phase { phases.append(session.phase) }
            }
        }
        return (effects, phases)
    }

    @Test func aSessionCountsDownShootsAndShowsFourTimesThenPrints() {
        let plan = NookPhotoBoothPlan(shots: 4, firstCountdown: 5)
        let (effects, phases) = Self.run(plan, step: 0.1)

        var expected: [NookPhotoBoothEffect] = []
        for shot in 1...4 {
            let from = shot == 1 ? 5 : 3
            expected += stride(from: from, through: 1, by: -1).map { NookPhotoBoothEffect.showNumber($0) }
            expected.append(.capture(shot: shot))
        }
        expected.append(.compose)
        #expect(effects == expected)

        #expect(phases.first == .getReady)
        #expect(phases.last == .done)
        #expect(phases.contains(.preview(shot: 4)))
        #expect(phases.contains(.nextPose(shot: 2)))
        // The last picture goes to the printer, not to another pose.
        #expect(!phases.contains(.nextPose(shot: 5)))
    }

    @Test func everyPictureFollowsItsWholeCountdownHoweverTheClockJumps() {
        for step in [0.05, 0.4, 1, 3.7, 60, 86_400] {
            let plan = NookPhotoBoothPlan(shots: 4, firstCountdown: 10)
            let effects = Self.run(plan, step: step).effects
            var shown: [Int] = []
            var shots: [Int] = []
            for effect in effects {
                switch effect {
                case let .showNumber(number):
                    shown.append(number)
                case let .capture(shot):
                    let countdown = plan.countdown(beforeShot: shot)
                    #expect(shown == Array(stride(from: countdown, through: 1, by: -1)), "step \(step), shot \(shot)")
                    shown = []
                    shots.append(shot)
                case .compose:
                    #expect(shown.isEmpty, "step \(step)")
                }
            }
            #expect(shots == [1, 2, 3, 4], "step \(step)")
        }
    }

    @Test func aStepNeverEndsBeforeItsTime() {
        var session = NookPhotoBoothSession(plan: NookPhotoBoothPlan(firstCountdown: 3), at: Self.start)
        #expect(session.advance(to: Self.start.addingTimeInterval(0.99)).isEmpty)
        #expect(session.phase == .getReady)
        #expect(session.advance(to: Self.start.addingTimeInterval(1)) == [.showNumber(3)])

        let countdownStart = Self.start.addingTimeInterval(1)
        #expect(session.advance(to: countdownStart.addingTimeInterval(0.99)).isEmpty)
        #expect(session.phase == .countdown(shot: 1, number: 3))
        // A clock that runs backwards moves nothing.
        #expect(session.advance(to: Self.start.addingTimeInterval(-500)).isEmpty)
        #expect(session.phase == .countdown(shot: 1, number: 3))
    }

    @Test func aBigJumpMovesOneStepAndRestartsTheWait() {
        var session = NookPhotoBoothSession(plan: NookPhotoBoothPlan(firstCountdown: 3), at: Self.start)
        let late = Self.start.addingTimeInterval(3600)
        #expect(session.advance(to: late) == [.showNumber(3)])
        // The number that just came up still gets its whole second.
        #expect(session.advance(to: late.addingTimeInterval(0.5)).isEmpty)
        #expect(session.advance(to: late.addingTimeInterval(1)) == [.showNumber(2)])
    }

    @Test func thePictureIsWaitedForHoweverLongItTakes() {
        var session = NookPhotoBoothSession(plan: NookPhotoBoothPlan(firstCountdown: 1), at: Self.start)
        var now = Self.start.addingTimeInterval(1)
        #expect(session.advance(to: now) == [.showNumber(1)])
        now = now.addingTimeInterval(1)
        #expect(session.advance(to: now) == [.capture(shot: 1)])
        #expect(session.phase == .capturing(shot: 1))
        #expect(session.shotsTaken == 0)

        #expect(session.advance(to: now.addingTimeInterval(900)).isEmpty)
        #expect(session.phase == .capturing(shot: 1))

        session.pictureArrived(at: now)
        #expect(session.phase == .preview(shot: 1))
        #expect(session.shotsTaken == 1)
        // A second answer for the same picture changes nothing.
        session.pictureArrived(at: now.addingTimeInterval(5))
        #expect(session.phaseStart == now)
    }

    @Test func stripReadyOnlyCountsWhilePrinting() {
        var session = NookPhotoBoothSession(plan: NookPhotoBoothPlan(), at: Self.start)
        session.stripReady(at: Self.start)
        #expect(session.phase == .getReady)
    }

    @Test func aPlanMendsBadNumbers() {
        let plan = NookPhotoBoothPlan(shots: 0, firstCountdown: -4, beat: -1, getReady: -1, preview: -1, nextPose: -1)
        let one = 1
        let zero: TimeInterval = 0
        #expect(plan.shots == one)
        #expect(plan.firstCountdown == one)
        #expect(plan.laterCountdown == one)
        #expect(plan.beat == zero)
        #expect(plan.getReady == zero)
        #expect(plan.preview == zero)
        #expect(plan.nextPose == zero)
    }

    @Test func laterCountdownsAreShortButNeverLongerThanTheFirst() {
        let three = 3
        let five = 5
        #expect(NookPhotoBoothPlan(firstCountdown: 10).laterCountdown == three)
        #expect(NookPhotoBoothPlan(firstCountdown: 5).laterCountdown == three)
        #expect(NookPhotoBoothPlan(firstCountdown: 3).laterCountdown == three)
        #expect(NookPhotoBoothPlan(firstCountdown: 10).countdown(beforeShot: 1) == 10)
        #expect(NookPhotoBoothPlan(firstCountdown: 10).countdown(beforeShot: 2) == three)
        #expect(NookPhotoBoothPlan(firstCountdown: 5, laterCountdown: 5).countdown(beforeShot: 4) == five)
        #expect(NookPhotoBoothPlan.countdownChoices.contains(NookPhotoBoothPlan.defaultCountdown))
    }

    @Test func aFullSessionAtTheDefaultPaceTakesAboutTwentyFiveSeconds() {
        // 1 to get ready, 5, then three more rounds of 1.2 + 0.8 + 3, then
        // the last look: 1 + 5 + 3 * 5 + 1.2.
        let plan = NookPhotoBoothPlan()
        let countdowns = (1...plan.shots).reduce(0.0) { $0 + Double(plan.countdown(beforeShot: $1)) * plan.beat }
        let total = plan.getReady + countdowns + Double(plan.shots) * plan.preview + Double(plan.shots - 1) * plan.nextPose
        let expected: TimeInterval = 22.2
        #expect(abs(total - expected) < 0.001)
    }
}
